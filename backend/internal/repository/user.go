package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/lib/pq"
)

var (
	ErrUserNotFound        = errors.New("user not found")
	ErrUsernameExists      = errors.New("username already exists")
	ErrReferralCodeExists  = errors.New("referral code already exists")
	ErrReferralAlreadyUsed = errors.New("referral code already used")
	ErrInsufficientCoins   = errors.New("insufficient_coins")
)

// User represents a phone-authenticated account. Username and ReferralCode
// are "" until CompleteSignup runs (first successful verify-otp) — a phone
// number can have an UpsertByPhone row (pending OTP) before that happens.
// ReferredBy is "" if no referrer is linked.
type User struct {
	ID              string
	Phone           string
	Username        string
	Coins           int
	ReferralCode    string
	ReferredBy      string
	OTPCode         *string
	OTPExpiresAt    *time.Time
	OTPAttempts     int
	OTPSentAt       *time.Time
	PhoneVerifiedAt *time.Time
	CreatedAt       time.Time
}

const userColumns = `id, phone, username, coins, referral_code, referred_by,
	otp_code, otp_expires_at, otp_attempts, otp_sent_at, phone_verified_at, created_at`

type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	return &UserRepository{db: db}
}

func scanUser(row interface{ Scan(...any) error }) (*User, error) {
	var (
		u            User
		username     sql.NullString
		referralCode sql.NullString
		referredBy   sql.NullString
		otpCode      sql.NullString
		otpExpires   sql.NullTime
		otpSent      sql.NullTime
		phoneVerified sql.NullTime
	)
	err := row.Scan(&u.ID, &u.Phone, &username, &u.Coins, &referralCode, &referredBy,
		&otpCode, &otpExpires, &u.OTPAttempts, &otpSent, &phoneVerified, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	u.Username = username.String
	u.ReferralCode = referralCode.String
	u.ReferredBy = referredBy.String
	if otpCode.Valid {
		u.OTPCode = &otpCode.String
	}
	if otpExpires.Valid {
		u.OTPExpiresAt = &otpExpires.Time
	}
	if otpSent.Valid {
		u.OTPSentAt = &otpSent.Time
	}
	if phoneVerified.Valid {
		u.PhoneVerifiedAt = &phoneVerified.Time
	}
	return &u, nil
}

// UpsertByPhone returns the existing row for phone, or creates a bare
// (unverified, no username/referral_code yet) row if none exists. Idempotent
// so a resend reuses the same account row.
func (r *UserRepository) UpsertByPhone(ctx context.Context, phone string) (*User, error) {
	const q = `
		INSERT INTO users (phone) VALUES ($1)
		ON CONFLICT (phone) DO UPDATE SET phone = EXCLUDED.phone
		RETURNING ` + userColumns

	u, err := scanUser(r.db.QueryRowContext(ctx, q, phone))
	if err != nil {
		return nil, fmt.Errorf("UpsertByPhone: %w", err)
	}
	return u, nil
}

func (r *UserRepository) GetUserByPhone(ctx context.Context, phone string) (*User, error) {
	const q = `SELECT ` + userColumns + ` FROM users WHERE phone = $1`

	u, err := scanUser(r.db.QueryRowContext(ctx, q, phone))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetUserByPhone: %w", err)
	}
	return u, nil
}

func (r *UserRepository) GetUserByID(ctx context.Context, id string) (*User, error) {
	const q = `SELECT ` + userColumns + ` FROM users WHERE id = $1`

	u, err := scanUser(r.db.QueryRowContext(ctx, q, id))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetUserByID: %w", err)
	}
	return u, nil
}

func (r *UserRepository) GetUserByUsername(ctx context.Context, username string) (*User, error) {
	const q = `SELECT ` + userColumns + ` FROM users WHERE username = $1`

	u, err := scanUser(r.db.QueryRowContext(ctx, q, username))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetUserByUsername: %w", err)
	}
	return u, nil
}

func (r *UserRepository) GetUserByReferralCode(ctx context.Context, code string) (*User, error) {
	const q = `SELECT ` + userColumns + ` FROM users WHERE referral_code = $1`

	u, err := scanUser(r.db.QueryRowContext(ctx, q, code))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetUserByReferralCode: %w", err)
	}
	return u, nil
}

// SetOTP stores a freshly generated code/expiry/sent-at and resets the
// attempt counter — always call this for a new send, never to bump expiry alone.
func (r *UserRepository) SetOTP(ctx context.Context, userID, code string, expiresAt, sentAt time.Time) error {
	const q = `
		UPDATE users
		SET otp_code = $1, otp_expires_at = $2, otp_sent_at = $3, otp_attempts = 0
		WHERE id = $4`
	if _, err := r.db.ExecContext(ctx, q, code, expiresAt, sentAt, userID); err != nil {
		return fmt.Errorf("SetOTP: %w", err)
	}
	return nil
}

// IncrementOTPAttempts records one failed verify attempt and returns the new count.
func (r *UserRepository) IncrementOTPAttempts(ctx context.Context, userID string) (int, error) {
	const q = `UPDATE users SET otp_attempts = otp_attempts + 1 WHERE id = $1 RETURNING otp_attempts`

	var attempts int
	if err := r.db.QueryRowContext(ctx, q, userID).Scan(&attempts); err != nil {
		return 0, fmt.Errorf("IncrementOTPAttempts: %w", err)
	}
	return attempts, nil
}

// CompleteSignup marks a phone as verified for the first time, assigning it a
// username and referral code, and optionally linking a referrer. Returns
// ErrUsernameExists/ErrReferralCodeExists on a unique-constraint collision so
// the caller can retry with freshly generated values.
func (r *UserRepository) CompleteSignup(ctx context.Context, userID, username, referralCode, referredBy string) error {
	const q = `
		UPDATE users
		SET username = $1, referral_code = $2, referred_by = NULLIF($3, '')::uuid,
		    phone_verified_at = now(), otp_code = NULL, otp_expires_at = NULL
		WHERE id = $4`

	_, err := r.db.ExecContext(ctx, q, username, referralCode, referredBy, userID)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			if pqErr.Constraint == "users_referral_code_key" {
				return ErrReferralCodeExists
			}
			return ErrUsernameExists
		}
		return fmt.Errorf("CompleteSignup: %w", err)
	}
	return nil
}

// MarkVerified clears a pending OTP for a returning (already-signed-up) user.
func (r *UserRepository) MarkVerified(ctx context.Context, userID string) error {
	const q = `UPDATE users SET otp_code = NULL, otp_expires_at = NULL WHERE id = $1`
	if _, err := r.db.ExecContext(ctx, q, userID); err != nil {
		return fmt.Errorf("MarkVerified: %w", err)
	}
	return nil
}

// RedeemReferral links referrerID as userID's referrer, but only if userID
// hasn't already linked one — atomic one-time check-and-set.
func (r *UserRepository) RedeemReferral(ctx context.Context, userID, referrerID string) error {
	const q = `UPDATE users SET referred_by = $1 WHERE id = $2 AND referred_by IS NULL`

	res, err := r.db.ExecContext(ctx, q, referrerID, userID)
	if err != nil {
		return fmt.Errorf("RedeemReferral: %w", err)
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("RedeemReferral rows: %w", err)
	}
	if rows == 0 {
		return ErrReferralAlreadyUsed
	}
	return nil
}

// AwardCoins atomically adds amount to a user's coin balance.
func (r *UserRepository) AwardCoins(ctx context.Context, userID string, amount int) error {
	const q = `UPDATE users SET coins = coins + $1 WHERE id = $2`
	_, err := r.db.ExecContext(ctx, q, amount, userID)
	if err != nil {
		return fmt.Errorf("AwardCoins: %w", err)
	}
	return nil
}

// SpendCoins atomically deducts amount from a user's coin balance.
// Returns ErrInsufficientCoins if balance is too low.
func (r *UserRepository) SpendCoins(ctx context.Context, userID string, amount int) error {
	const q = `
		UPDATE users SET coins = coins - $1
		WHERE id = $2 AND coins >= $1`
	res, err := r.db.ExecContext(ctx, q, amount, userID)
	if err != nil {
		return fmt.Errorf("SpendCoins: %w", err)
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("SpendCoins rows: %w", err)
	}
	if rows == 0 {
		return ErrInsufficientCoins
	}
	return nil
}

// GetUsernames returns a map of userID → username for the given IDs.
// Missing IDs are silently omitted from the result.
func (r *UserRepository) GetUsernames(ctx context.Context, userIDs []string) (map[string]string, error) {
	if len(userIDs) == 0 {
		return map[string]string{}, nil
	}
	const q = `SELECT id, COALESCE(username, '') FROM users WHERE id = ANY($1)`
	rows, err := r.db.QueryContext(ctx, q, pq.Array(userIDs))
	if err != nil {
		return nil, fmt.Errorf("GetUsernames: %w", err)
	}
	defer rows.Close()

	result := make(map[string]string, len(userIDs))
	for rows.Next() {
		var id, username string
		if err := rows.Scan(&id, &username); err != nil {
			return nil, fmt.Errorf("GetUsernames scan: %w", err)
		}
		result[id] = username
	}
	return result, rows.Err()
}
