package service

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

const (
	AdminRoleOwner    = "owner"
	AdminRoleOperator = "operator"
	AdminRoleViewer   = "viewer"

	adminBcryptCost  = 12
	adminSessPrefix  = "admin:sess:"
	adminIndexPrefix = "admin:sessions:" // set of live session tokens per admin, for revoke-all
	adminEnabledTTL  = 5 * time.Second
)

var (
	ErrAdminInvalidCredentials = errors.New("invalid admin credentials")
	ErrAdminRateLimited        = errors.New("too many failed admin logins")
	ErrAdminSessionInvalid     = errors.New("admin session missing or expired")
	ErrAdminInvalidUsername    = errors.New("invalid admin username")
	ErrAdminWeakPassword       = errors.New("admin password too short or too long")
	ErrAdminInvalidRole        = errors.New("invalid admin role")
	ErrAdminUsernameTaken      = repository.ErrAdminUsernameTaken
	ErrAdminNotFound           = repository.ErrAdminNotFound
)

var (
	adminUsernameRE = regexp.MustCompile(`^[a-z][a-z0-9_.-]{2,31}$`)
	adminTokenRE    = regexp.MustCompile(`^[0-9a-f]{64}$`)
	adminRoleRank   = map[string]int{AdminRoleViewer: 1, AdminRoleOperator: 2, AdminRoleOwner: 3}
)

// AdminRoleAtLeast reports whether role grants at least the privileges of min.
func AdminRoleAtLeast(role, min string) bool {
	r, ok := adminRoleRank[role]
	m, okMin := adminRoleRank[min]
	return ok && okMin && r >= m
}

type adminStore interface {
	GetByUsername(ctx context.Context, username string) (*repository.AdminUser, error)
	GetByID(ctx context.Context, id string) (*repository.AdminUser, error)
	Create(ctx context.Context, username, passwordHash, role string) (*repository.AdminUser, error)
	SetPassword(ctx context.Context, id, passwordHash string) error
	SetDisabled(ctx context.Context, id string, disabled bool) error
	TouchLogin(ctx context.Context, id string) error
	CountActive(ctx context.Context) (int, error)
}

// AdminSession is a validated panel session. Role is the admin's current role
// (read from the database on every request), not the one at login time.
type AdminSession struct {
	Token     string
	AdminID   string
	Username  string
	Role      string
	CreatedAt time.Time
}

// storedSession is the JSON held under admin:sess:<token>.
type storedSession struct {
	AdminID   string    `json:"admin_id"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"created_at"`
}

// AdminAuthService handles panel logins and Redis-backed sessions. Sessions are
// revocable and deliberately separate from the player JWTs.
type AdminAuthService struct {
	store   adminStore
	rdb     *redis.Client
	idleTTL time.Duration
	absTTL  time.Duration
	now     func() time.Time

	mu        sync.Mutex
	enabled   bool
	enabledAt time.Time
	dummyOnce sync.Once
	dummyHash []byte
}

func NewAdminAuthService(store adminStore, rdb *redis.Client, cfg *config.Config) *AdminAuthService {
	idle := cfg.AdminSessionTTL
	if idle <= 0 {
		idle = config.AdminSessionIdleTTL
	}
	return &AdminAuthService{
		store:   store,
		rdb:     rdb,
		idleTTL: idle,
		absTTL:  config.AdminSessionAbsoluteTTL,
		now:     time.Now,
	}
}

// AbsoluteTTL is the longest a session can live regardless of activity.
func (s *AdminAuthService) AbsoluteTTL() time.Duration { return s.absTTL }

// Enabled reports whether the panel is usable: at least one active admin
// account exists. The answer is cached briefly because the middleware asks on
// every admin request.
func (s *AdminAuthService) Enabled(ctx context.Context) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.enabledAt.IsZero() && s.now().Sub(s.enabledAt) < adminEnabledTTL {
		return s.enabled
	}
	n, err := s.store.CountActive(ctx)
	if err != nil {
		slog.Error("admin enabled check failed", "error", err)
		return s.enabled // keep the last known answer
	}
	s.enabled = n > 0
	s.enabledAt = s.now()
	return s.enabled
}

// Login verifies the credentials and opens a session. Every failure mode that
// could reveal whether a username exists returns the same error.
func (s *AdminAuthService) Login(ctx context.Context, ip, username, password string) (*AdminSession, *repository.AdminUser, error) {
	username = normalizeAdminUsername(username)
	ipKey, userKey := "admin:login:ip:"+ip, "admin:login:user:"+username

	if limited, err := s.loginThrottled(ctx, ipKey, userKey); err != nil {
		return nil, nil, err
	} else if limited {
		return nil, nil, ErrAdminRateLimited
	}

	admin, err := s.store.GetByUsername(ctx, username)
	switch {
	case errors.Is(err, repository.ErrAdminNotFound):
		s.burnPasswordCheck(password) // keep unknown-user timing close to wrong-password timing
		s.recordLoginFailure(ctx, ipKey, userKey)
		return nil, nil, ErrAdminInvalidCredentials
	case err != nil:
		return nil, nil, fmt.Errorf("AdminAuthService.Login: %w", err)
	}
	if bcrypt.CompareHashAndPassword([]byte(admin.PasswordHash), []byte(password)) != nil || admin.DisabledAt != nil {
		s.recordLoginFailure(ctx, ipKey, userKey)
		return nil, nil, ErrAdminInvalidCredentials
	}

	sess, err := s.createSession(ctx, admin)
	if err != nil {
		return nil, nil, err
	}
	if err := s.store.TouchLogin(ctx, admin.ID); err != nil {
		slog.Error("admin last_login update failed", "admin", admin.Username, "error", err)
	}
	s.rdb.Del(ctx, userKey)
	return sess, admin, nil
}

func (s *AdminAuthService) loginThrottled(ctx context.Context, ipKey, userKey string) (bool, error) {
	vals, err := s.rdb.MGet(ctx, ipKey, userKey).Result()
	if err != nil {
		return false, fmt.Errorf("AdminAuthService.loginThrottled: %w", err)
	}
	return counterAtLeast(vals[0], config.AdminLoginMaxFailsIP) || counterAtLeast(vals[1], config.AdminLoginMaxFailsUser), nil
}

func counterAtLeast(v any, limit int) bool {
	str, ok := v.(string)
	if !ok {
		return false
	}
	var n int
	_, _ = fmt.Sscanf(str, "%d", &n)
	return n >= limit
}

func (s *AdminAuthService) recordLoginFailure(ctx context.Context, keys ...string) {
	for _, k := range keys {
		if n, err := s.rdb.Incr(ctx, k).Result(); err != nil {
			slog.Error("admin login counter failed", "error", err)
		} else if n == 1 {
			s.rdb.Expire(ctx, k, config.AdminLoginWindow)
		}
	}
}

func (s *AdminAuthService) burnPasswordCheck(password string) {
	s.dummyOnce.Do(func() {
		s.dummyHash, _ = bcrypt.GenerateFromPassword([]byte("dummy-password"), adminBcryptCost)
	})
	_ = bcrypt.CompareHashAndPassword(s.dummyHash, []byte(password))
}

func (s *AdminAuthService) createSession(ctx context.Context, admin *repository.AdminUser) (*AdminSession, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return nil, fmt.Errorf("AdminAuthService.createSession: %w", err)
	}
	token := hex.EncodeToString(raw)
	now := s.now().UTC()
	val, err := json.Marshal(storedSession{AdminID: admin.ID, Role: admin.Role, CreatedAt: now})
	if err != nil {
		return nil, fmt.Errorf("AdminAuthService.createSession: %w", err)
	}
	pipe := s.rdb.TxPipeline()
	pipe.Set(ctx, adminSessPrefix+token, val, s.idleTTL)
	pipe.SAdd(ctx, adminIndexPrefix+admin.ID, token)
	pipe.Expire(ctx, adminIndexPrefix+admin.ID, s.absTTL)
	if _, err := pipe.Exec(ctx); err != nil {
		return nil, fmt.Errorf("AdminAuthService.createSession: %w", err)
	}
	return &AdminSession{Token: token, AdminID: admin.ID, Username: admin.Username, Role: admin.Role, CreatedAt: now}, nil
}

// Authenticate resolves a session cookie value. Each successful call slides
// the idle window, never past the absolute cap. The admin row is re-read so a
// disabled account or a role change takes effect immediately.
func (s *AdminAuthService) Authenticate(ctx context.Context, token string) (*AdminSession, error) {
	if !adminTokenRE.MatchString(token) {
		return nil, ErrAdminSessionInvalid
	}
	raw, err := s.rdb.Get(ctx, adminSessPrefix+token).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, ErrAdminSessionInvalid
	}
	if err != nil {
		return nil, fmt.Errorf("AdminAuthService.Authenticate: %w", err)
	}
	var st storedSession
	if err := json.Unmarshal(raw, &st); err != nil {
		return nil, fmt.Errorf("AdminAuthService.Authenticate: decode: %w", err)
	}

	remaining := st.CreatedAt.Add(s.absTTL).Sub(s.now())
	if remaining <= 0 {
		s.revoke(ctx, st.AdminID, token)
		return nil, ErrAdminSessionInvalid
	}
	admin, err := s.store.GetByID(ctx, st.AdminID)
	if errors.Is(err, repository.ErrAdminNotFound) || (err == nil && admin.DisabledAt != nil) {
		s.revoke(ctx, st.AdminID, token)
		return nil, ErrAdminSessionInvalid
	}
	if err != nil {
		return nil, fmt.Errorf("AdminAuthService.Authenticate: %w", err)
	}

	ttl := s.idleTTL
	if remaining < ttl {
		ttl = remaining
	}
	s.rdb.Expire(ctx, adminSessPrefix+token, ttl)
	return &AdminSession{Token: token, AdminID: admin.ID, Username: admin.Username, Role: admin.Role, CreatedAt: st.CreatedAt}, nil
}

// Logout ends one session.
func (s *AdminAuthService) Logout(ctx context.Context, sess *AdminSession) {
	s.revoke(ctx, sess.AdminID, sess.Token)
}

func (s *AdminAuthService) revoke(ctx context.Context, adminID, token string) {
	pipe := s.rdb.TxPipeline()
	pipe.Del(ctx, adminSessPrefix+token)
	pipe.SRem(ctx, adminIndexPrefix+adminID, token)
	if _, err := pipe.Exec(ctx); err != nil {
		slog.Error("admin session revoke failed", "error", err)
	}
}

// RevokeAll ends every session of one admin (password change, disable).
func (s *AdminAuthService) RevokeAll(ctx context.Context, adminID string) error {
	tokens, err := s.rdb.SMembers(ctx, adminIndexPrefix+adminID).Result()
	if err != nil {
		return fmt.Errorf("AdminAuthService.RevokeAll: %w", err)
	}
	keys := []string{adminIndexPrefix + adminID}
	for _, t := range tokens {
		keys = append(keys, adminSessPrefix+t)
	}
	if err := s.rdb.Del(ctx, keys...).Err(); err != nil {
		return fmt.Errorf("AdminAuthService.RevokeAll: %w", err)
	}
	return nil
}

// --- account management (used by cmd/adminctl) ---

func normalizeAdminUsername(u string) string { return strings.ToLower(strings.TrimSpace(u)) }

func validateAdminPassword(p string) error {
	// bcrypt only reads the first 72 bytes; refuse longer input rather than truncate silently.
	if len(p) < config.AdminPasswordMinLength || len(p) > 72 {
		return ErrAdminWeakPassword
	}
	return nil
}

func hashAdminPassword(p string) (string, error) {
	h, err := bcrypt.GenerateFromPassword([]byte(p), adminBcryptCost)
	if err != nil {
		return "", fmt.Errorf("hash admin password: %w", err)
	}
	return string(h), nil
}

func (s *AdminAuthService) CreateAdmin(ctx context.Context, username, password, role string) (*repository.AdminUser, error) {
	username = normalizeAdminUsername(username)
	if !adminUsernameRE.MatchString(username) {
		return nil, ErrAdminInvalidUsername
	}
	if _, ok := adminRoleRank[role]; !ok {
		return nil, ErrAdminInvalidRole
	}
	if err := validateAdminPassword(password); err != nil {
		return nil, err
	}
	hash, err := hashAdminPassword(password)
	if err != nil {
		return nil, err
	}
	admin, err := s.store.Create(ctx, username, hash, role)
	if err != nil {
		return nil, fmt.Errorf("AdminAuthService.CreateAdmin: %w", err)
	}
	return admin, nil
}

// SetPassword changes an admin's password and ends all their sessions.
func (s *AdminAuthService) SetPassword(ctx context.Context, username, password string) error {
	if err := validateAdminPassword(password); err != nil {
		return err
	}
	admin, err := s.store.GetByUsername(ctx, normalizeAdminUsername(username))
	if err != nil {
		return fmt.Errorf("AdminAuthService.SetPassword: %w", err)
	}
	hash, err := hashAdminPassword(password)
	if err != nil {
		return err
	}
	if err := s.store.SetPassword(ctx, admin.ID, hash); err != nil {
		return fmt.Errorf("AdminAuthService.SetPassword: %w", err)
	}
	return s.RevokeAll(ctx, admin.ID)
}

// SetDisabled disables or re-enables an admin; disabling also ends their sessions.
func (s *AdminAuthService) SetDisabled(ctx context.Context, username string, disabled bool) error {
	admin, err := s.store.GetByUsername(ctx, normalizeAdminUsername(username))
	if err != nil {
		return fmt.Errorf("AdminAuthService.SetDisabled: %w", err)
	}
	if err := s.store.SetDisabled(ctx, admin.ID, disabled); err != nil {
		return fmt.Errorf("AdminAuthService.SetDisabled: %w", err)
	}
	if disabled {
		return s.RevokeAll(ctx, admin.ID)
	}
	return nil
}
