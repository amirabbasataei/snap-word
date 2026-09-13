package service

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"regexp"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

var (
	ErrInvalidPhone     = errors.New("invalid_phone")
	ErrInvalidToken     = errors.New("invalid_token")
	ErrResendCooldown   = errors.New("resend_cooldown")
	ErrOTPRateLimited   = errors.New("rate_limited")
	ErrOTPNotRequested  = errors.New("otp_not_requested")
	ErrInvalidOTP       = errors.New("invalid_code")
	ErrOTPExpired       = errors.New("code_expired")
	ErrOTPMaxAttempts   = errors.New("too_many_attempts")
	ErrSelfReferral     = errors.New("self_referral")
	ErrReferralNotFound = errors.New("referral_not_found")
)

var phoneRe = regexp.MustCompile(`^09\d{9}$`)

const referralCharset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // excludes ambiguous 0/O/1/I

// TokenPair holds an access token, a refresh token, and the authenticated user's identity.
type TokenPair struct {
	AccessToken  string
	RefreshToken string
	UserID       string
	Username     string
}

// VerifyResult carries the non-token outcome of a successful verify-otp call.
type VerifyResult struct {
	UserID          string
	Username        string
	Coins           int
	IsNewUser       bool
	ReferralWarning string // "referral_not_found" — soft, never blocks signup
}

type claims struct {
	UserID   string `json:"sub"`
	Username string `json:"username"`
	Type     string `json:"type"` // "access" | "refresh"
	jwt.RegisteredClaims
}

// AuthService handles OTP send/verify, token issuance, and referral redemption.
type AuthService struct {
	userRepo  *repository.UserRepository
	kavenegar *KavenegarClient
	rdb       *redis.Client // nil-safe: daily send-rate cap no-ops if unset/unreachable
	cfg       *config.Config
}

func NewAuthService(userRepo *repository.UserRepository, kavenegar *KavenegarClient, rdb *redis.Client, cfg *config.Config) *AuthService {
	return &AuthService{userRepo: userRepo, kavenegar: kavenegar, rdb: rdb, cfg: cfg}
}

// SendOTP normalizes and validates phone, enforces the resend cooldown and a
// daily send cap, generates a fresh 4-digit code, and delivers it via Kavenegar.
func (s *AuthService) SendOTP(ctx context.Context, rawPhone string, voice bool) error {
	phone, err := normalizePhone(rawPhone)
	if err != nil {
		return err
	}

	user, err := s.userRepo.UpsertByPhone(ctx, phone)
	if err != nil {
		return fmt.Errorf("SendOTP: %w", err)
	}

	if user.OTPSentAt != nil && time.Since(*user.OTPSentAt) < s.cfg.OTPResendCooldown {
		return ErrResendCooldown
	}
	if err := s.checkAndIncrSendRate(ctx, phone); err != nil {
		return err
	}

	var code string
	if s.kavenegar.Configured() {
		code, err = randomDigits(4)
		if err != nil {
			return fmt.Errorf("SendOTP generate code: %w", err)
		}
	} else {
		// Dev fallback: no SMS provider configured, so use a fixed code
		// (1111) instead of a random one nobody could ever read.
		code = "1111"
	}
	now := time.Now()
	if err := s.userRepo.SetOTP(ctx, user.ID, code, now.Add(s.cfg.OTPCodeTTL), now); err != nil {
		return fmt.Errorf("SendOTP: %w", err)
	}

	if err := s.kavenegar.SendOTP(ctx, phone, code, voice); err != nil {
		return fmt.Errorf("SendOTP deliver: %w", err)
	}
	return nil
}

// VerifyOTP validates the submitted code and issues a session. On a phone's
// first successful verification, it completes signup: assigns a username and
// referral code, and — if referralCode is supplied and valid — links the
// referrer and awards the new-user welcome bonus. An unresolvable referral
// code never blocks signup; it's surfaced as VerifyResult.ReferralWarning.
func (s *AuthService) VerifyOTP(ctx context.Context, rawPhone, code, referralCode string) (*TokenPair, VerifyResult, error) {
	phone, err := normalizePhone(rawPhone)
	if err != nil {
		return nil, VerifyResult{}, err
	}

	user, err := s.userRepo.GetUserByPhone(ctx, phone)
	if errors.Is(err, repository.ErrUserNotFound) {
		return nil, VerifyResult{}, ErrOTPNotRequested
	}
	if err != nil {
		return nil, VerifyResult{}, fmt.Errorf("VerifyOTP: %w", err)
	}

	if user.OTPCode == nil || user.OTPExpiresAt == nil {
		return nil, VerifyResult{}, ErrOTPNotRequested
	}
	if user.OTPAttempts >= config.OTPMaxAttempts {
		return nil, VerifyResult{}, ErrOTPMaxAttempts
	}
	if time.Now().After(*user.OTPExpiresAt) {
		return nil, VerifyResult{}, ErrOTPExpired
	}
	if *user.OTPCode != code {
		if _, ierr := s.userRepo.IncrementOTPAttempts(ctx, user.ID); ierr != nil {
			return nil, VerifyResult{}, fmt.Errorf("VerifyOTP: %w", ierr)
		}
		return nil, VerifyResult{}, ErrInvalidOTP
	}

	result := VerifyResult{UserID: user.ID, IsNewUser: user.PhoneVerifiedAt == nil}

	if result.IsNewUser {
		referredByID, warning, rerr := s.resolveReferrer(ctx, referralCode)
		if rerr != nil {
			return nil, VerifyResult{}, rerr
		}
		result.ReferralWarning = warning

		username, newReferralCode, cerr := s.completeSignupWithRetry(ctx, user.ID, referredByID)
		if cerr != nil {
			return nil, VerifyResult{}, cerr
		}
		user.Username = username
		user.ReferralCode = newReferralCode

		if referredByID != "" {
			if err := s.userRepo.AwardCoins(ctx, user.ID, config.CoinReferralSignup); err != nil {
				return nil, VerifyResult{}, fmt.Errorf("VerifyOTP award signup bonus: %w", err)
			}
			user.Coins += config.CoinReferralSignup
		}
	} else {
		if err := s.userRepo.MarkVerified(ctx, user.ID); err != nil {
			return nil, VerifyResult{}, fmt.Errorf("VerifyOTP: %w", err)
		}
	}

	pair, err := s.generateTokenPair(user.ID, user.Username)
	if err != nil {
		return nil, VerifyResult{}, err
	}

	result.Username = user.Username
	result.Coins = user.Coins
	return pair, result, nil
}

// resolveReferrer looks up a referral code supplied at signup. An empty code
// is not an error (no code offered). An unknown code is a soft warning, not
// a failure — self-referral can't occur here since the new user's own code
// doesn't exist yet at this point in the flow.
func (s *AuthService) resolveReferrer(ctx context.Context, referralCode string) (referrerID, warning string, err error) {
	if referralCode == "" {
		return "", "", nil
	}
	referrer, gerr := s.userRepo.GetUserByReferralCode(ctx, referralCode)
	if errors.Is(gerr, repository.ErrUserNotFound) {
		return "", "referral_not_found", nil
	}
	if gerr != nil {
		return "", "", fmt.Errorf("resolveReferrer: %w", gerr)
	}
	return referrer.ID, "", nil
}

func (s *AuthService) completeSignupWithRetry(ctx context.Context, userID, referredByID string) (username, referralCode string, err error) {
	const maxAttempts = 5
	for range maxAttempts {
		username, err = generateUsername()
		if err != nil {
			return "", "", fmt.Errorf("completeSignupWithRetry: %w", err)
		}
		referralCode, err = generateReferralCode()
		if err != nil {
			return "", "", fmt.Errorf("completeSignupWithRetry: %w", err)
		}

		err = s.userRepo.CompleteSignup(ctx, userID, username, referralCode, referredByID)
		if err == nil {
			return username, referralCode, nil
		}
		if errors.Is(err, repository.ErrUsernameExists) || errors.Is(err, repository.ErrReferralCodeExists) {
			continue
		}
		return "", "", fmt.Errorf("completeSignupWithRetry: %w", err)
	}
	return "", "", fmt.Errorf("completeSignupWithRetry: exhausted %d attempts", maxAttempts)
}

// RedeemReferral is the post-login, one-time entry point: an existing user
// submits a code after the fact. Rejects self-referral and re-use.
func (s *AuthService) RedeemReferral(ctx context.Context, userID, referralCode string) (coinsAwarded int, err error) {
	user, err := s.userRepo.GetUserByID(ctx, userID)
	if err != nil {
		return 0, fmt.Errorf("RedeemReferral: %w", err)
	}
	if referralCode == user.ReferralCode {
		return 0, ErrSelfReferral
	}

	referrer, err := s.userRepo.GetUserByReferralCode(ctx, referralCode)
	if errors.Is(err, repository.ErrUserNotFound) {
		return 0, ErrReferralNotFound
	}
	if err != nil {
		return 0, fmt.Errorf("RedeemReferral: %w", err)
	}

	if err := s.userRepo.RedeemReferral(ctx, userID, referrer.ID); err != nil {
		return 0, err // repository.ErrReferralAlreadyUsed surfaces as-is
	}
	if err := s.userRepo.AwardCoins(ctx, userID, config.CoinReferralRedeem); err != nil {
		return 0, fmt.Errorf("RedeemReferral award: %w", err)
	}
	return config.CoinReferralRedeem, nil
}

// checkAndIncrSendRate enforces a per-phone daily send cap via Redis. It
// never fails closed: if rdb is nil or unreachable, the check is skipped
// (availability over strictness) — the per-phone resend cooldown still applies.
func (s *AuthService) checkAndIncrSendRate(ctx context.Context, phone string) error {
	if s.rdb == nil {
		return nil
	}
	key := "otp_sends:" + phone
	n, err := s.rdb.Incr(ctx, key).Result()
	if err != nil {
		return nil
	}
	if n == 1 {
		s.rdb.Expire(ctx, key, 24*time.Hour)
	}
	if int(n) > config.OTPMaxSendsPerDay {
		return ErrOTPRateLimited
	}
	return nil
}

// RefreshToken validates a refresh token and returns a new token pair.
func (s *AuthService) RefreshToken(ctx context.Context, rawToken string) (*TokenPair, error) {
	c, err := s.parseToken(rawToken)
	if err != nil || c.Type != "refresh" {
		return nil, ErrInvalidToken
	}

	user, err := s.userRepo.GetUserByID(ctx, c.UserID)
	if err != nil {
		return nil, ErrInvalidToken
	}

	return s.generateTokenPair(user.ID, user.Username)
}

func (s *AuthService) generateTokenPair(userID, username string) (*TokenPair, error) {
	now := time.Now()

	access, err := s.sign(&claims{
		UserID:   userID,
		Username: username,
		Type:     "access",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.cfg.JWTAccessTTL)),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("sign access token: %w", err)
	}

	refresh, err := s.sign(&claims{
		UserID:   userID,
		Username: username,
		Type:     "refresh",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.cfg.JWTRefreshTTL)),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("sign refresh token: %w", err)
	}

	return &TokenPair{AccessToken: access, RefreshToken: refresh, UserID: userID, Username: username}, nil
}

func (s *AuthService) sign(c *claims) (string, error) {
	return jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString([]byte(s.cfg.JWTSecret))
}

// ParseAccessToken parses and validates an access token, returning (userID, username, error).
func (s *AuthService) ParseAccessToken(raw string) (string, string, error) {
	c, err := s.parseToken(raw)
	if err != nil || c.Type != "access" {
		return "", "", ErrInvalidToken
	}
	return c.UserID, c.Username, nil
}

func (s *AuthService) parseToken(raw string) (*claims, error) {
	tok, err := jwt.ParseWithClaims(raw, &claims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return []byte(s.cfg.JWTSecret), nil
	})
	if err != nil || !tok.Valid {
		return nil, ErrInvalidToken
	}
	c, ok := tok.Claims.(*claims)
	if !ok {
		return nil, ErrInvalidToken
	}
	return c, nil
}

// normalizePhone converts Persian/Arabic-Indic digits and common Iran mobile
// prefixes (+98, 0098, 98) to the canonical 09XXXXXXXXX form and validates it.
func normalizePhone(raw string) (string, error) {
	s := convertToASCIIDigits(raw)
	s = strings.Map(func(r rune) rune {
		switch r {
		case ' ', '-', '(', ')':
			return -1
		}
		return r
	}, s)

	switch {
	case strings.HasPrefix(s, "+98"):
		s = "0" + strings.TrimPrefix(s, "+98")
	case strings.HasPrefix(s, "0098"):
		s = "0" + strings.TrimPrefix(s, "0098")
	case strings.HasPrefix(s, "98") && len(s) == 12:
		s = "0" + strings.TrimPrefix(s, "98")
	}

	if !phoneRe.MatchString(s) {
		return "", ErrInvalidPhone
	}
	return s, nil
}

// convertToASCIIDigits maps Persian (۰-۹) and Arabic-Indic (٠-٩) digits to ASCII.
func convertToASCIIDigits(s string) string {
	return strings.Map(func(r rune) rune {
		switch {
		case r >= '۰' && r <= '۹':
			return '0' + (r - '۰')
		case r >= '٠' && r <= '٩':
			return '0' + (r - '٠')
		}
		return r
	}, s)
}

func randomDigits(n int) (string, error) {
	limit := big.NewInt(1)
	for range n {
		limit.Mul(limit, big.NewInt(10))
	}
	num, err := rand.Int(rand.Reader, limit)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%0*d", n, num.Int64()), nil
}

func generateReferralCode() (string, error) {
	b := make([]byte, 6)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(referralCharset))))
		if err != nil {
			return "", err
		}
		b[i] = referralCharset[n.Int64()]
	}
	return string(b), nil
}

func generateUsername() (string, error) {
	suffix, err := randomDigits(6)
	if err != nil {
		return "", err
	}
	return "Player" + suffix, nil
}
