package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/lib/pq"
)

var (
	ErrAdminNotFound      = errors.New("admin not found")
	ErrAdminUsernameTaken = errors.New("admin username taken")
)

type AdminUser struct {
	ID           string
	Username     string
	PasswordHash string
	Role         string
	TOTPSecret   *string
	DisabledAt   *time.Time
	LastLoginAt  *time.Time
	CreatedAt    time.Time
}

// AuditEntry is one row of admin_audit_log. AdminID is empty for the
// X-Admin-Key script and for failed logins.
type AuditEntry struct {
	AdminID    string
	Actor      string
	Action     string
	TargetType string
	TargetID   string
	Payload    any
	IP         string
}

// AdminRepository stores admin accounts and the audit trail.
type AdminRepository struct {
	db *sql.DB
}

func NewAdminRepository(db *sql.DB) *AdminRepository {
	return &AdminRepository{db: db}
}

const adminColumns = `id, username, password_hash, role, totp_secret, disabled_at, last_login_at, created_at`

func scanAdmin(row interface{ Scan(...any) error }) (*AdminUser, error) {
	var a AdminUser
	var totp sql.NullString
	var disabled, lastLogin sql.NullTime
	if err := row.Scan(&a.ID, &a.Username, &a.PasswordHash, &a.Role, &totp, &disabled, &lastLogin, &a.CreatedAt); err != nil {
		return nil, err
	}
	if totp.Valid {
		a.TOTPSecret = &totp.String
	}
	if disabled.Valid {
		a.DisabledAt = &disabled.Time
	}
	if lastLogin.Valid {
		a.LastLoginAt = &lastLogin.Time
	}
	return &a, nil
}

func (r *AdminRepository) GetByUsername(ctx context.Context, username string) (*AdminUser, error) {
	a, err := scanAdmin(r.db.QueryRowContext(ctx, `SELECT `+adminColumns+` FROM admin_users WHERE username = $1`, username))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrAdminNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.GetByUsername: %w", err)
	}
	return a, nil
}

func (r *AdminRepository) GetByID(ctx context.Context, id string) (*AdminUser, error) {
	a, err := scanAdmin(r.db.QueryRowContext(ctx, `SELECT `+adminColumns+` FROM admin_users WHERE id::text = $1`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrAdminNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.GetByID: %w", err)
	}
	return a, nil
}

func (r *AdminRepository) Create(ctx context.Context, username, passwordHash, role string) (*AdminUser, error) {
	a, err := scanAdmin(r.db.QueryRowContext(ctx,
		`INSERT INTO admin_users (username, password_hash, role) VALUES ($1, $2, $3) RETURNING `+adminColumns,
		username, passwordHash, role))
	var pqErr *pq.Error
	if errors.As(err, &pqErr) && pqErr.Code == "23505" {
		return nil, ErrAdminUsernameTaken
	}
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.Create: %w", err)
	}
	return a, nil
}

func (r *AdminRepository) SetPassword(ctx context.Context, id, passwordHash string) error {
	return r.execOne(ctx, "SetPassword", `UPDATE admin_users SET password_hash = $2 WHERE id = $1`, id, passwordHash)
}

func (r *AdminRepository) SetDisabled(ctx context.Context, id string, disabled bool) error {
	return r.execOne(ctx, "SetDisabled",
		`UPDATE admin_users SET disabled_at = CASE WHEN $2 THEN COALESCE(disabled_at, now()) ELSE NULL END WHERE id = $1`, id, disabled)
}

func (r *AdminRepository) TouchLogin(ctx context.Context, id string) error {
	return r.execOne(ctx, "TouchLogin", `UPDATE admin_users SET last_login_at = now() WHERE id = $1`, id)
}

func (r *AdminRepository) execOne(ctx context.Context, op, query string, args ...any) error {
	res, err := r.db.ExecContext(ctx, query, args...)
	if err != nil {
		return fmt.Errorf("AdminRepository.%s: %w", op, err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrAdminNotFound
	}
	return nil
}

// CountActive returns the number of admin accounts that are not disabled.
func (r *AdminRepository) CountActive(ctx context.Context) (int, error) {
	var n int
	if err := r.db.QueryRowContext(ctx, `SELECT count(*) FROM admin_users WHERE disabled_at IS NULL`).Scan(&n); err != nil {
		return 0, fmt.Errorf("AdminRepository.CountActive: %w", err)
	}
	return n, nil
}

func (r *AdminRepository) InsertAudit(ctx context.Context, e AuditEntry) error {
	var payload any
	if e.Payload != nil {
		b, err := json.Marshal(e.Payload)
		if err != nil {
			return fmt.Errorf("AdminRepository.InsertAudit payload: %w", err)
		}
		payload = b
	}
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO admin_audit_log (admin_id, actor, action, target_type, target_id, payload, ip)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		nullIfEmpty(e.AdminID), e.Actor, e.Action, nullIfEmpty(e.TargetType), nullIfEmpty(e.TargetID), payload, nullIfEmpty(e.IP))
	if err != nil {
		return fmt.Errorf("AdminRepository.InsertAudit: %w", err)
	}
	return nil
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}
