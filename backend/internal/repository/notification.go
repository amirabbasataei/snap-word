package repository

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/lib/pq"
)

// DeviceToken is a single FCM registration record.
type DeviceToken struct {
	UserID   string
	Token    string
	Platform string
}

// NotificationRepository manages device tokens stored in the device_tokens table.
type NotificationRepository struct {
	db *sql.DB
}

func NewNotificationRepository(db *sql.DB) *NotificationRepository {
	return &NotificationRepository{db: db}
}

// Notification permission as reported by the client (device_tokens.permission).
// PermUnknown marks rows registered before the column existed.
const (
	PermGranted       = "granted"
	PermDenied        = "denied"
	PermNotDetermined = "not_determined"
	PermUnknown       = "unknown"
)

// ValidPermission reports whether p is a value a client may send.
func ValidPermission(p string) bool {
	return p == PermGranted || p == PermDenied || p == PermNotDetermined
}

// RegisterToken upserts a device token for the given user. permission is what
// the OS currently allows for this app (see Perm*); an old client that does
// not report it passes PermUnknown, which never overwrites a known value.
func (r *NotificationRepository) RegisterToken(ctx context.Context, userID, token, platform, permission string) error {
	const q = `
		INSERT INTO device_tokens (user_id, token, platform, permission, updated_at)
		VALUES ($1, $2, $3, $4, now())
		ON CONFLICT (user_id, token) DO UPDATE SET
			platform   = EXCLUDED.platform,
			permission = CASE WHEN EXCLUDED.permission = 'unknown' THEN device_tokens.permission ELSE EXCLUDED.permission END,
			updated_at = now()`
	_, err := r.db.ExecContext(ctx, q, userID, token, platform, permission)
	if err != nil {
		return fmt.Errorf("RegisterToken: %w", err)
	}
	return nil
}

// DeregisterToken removes a specific device token belonging to the user.
func (r *NotificationRepository) DeregisterToken(ctx context.Context, userID, token string) error {
	const q = `DELETE FROM device_tokens WHERE user_id = $1 AND token = $2`
	_, err := r.db.ExecContext(ctx, q, userID, token)
	if err != nil {
		return fmt.Errorf("DeregisterToken: %w", err)
	}
	return nil
}

// GetTokensForUser returns all FCM tokens registered by userID.
func (r *NotificationRepository) GetTokensForUser(ctx context.Context, userID string) ([]string, error) {
	const q = `SELECT token FROM device_tokens WHERE user_id = $1`
	rows, err := r.db.QueryContext(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("GetTokensForUser: %w", err)
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, fmt.Errorf("GetTokensForUser scan: %w", err)
		}
		tokens = append(tokens, t)
	}
	return tokens, rows.Err()
}

// GetAllTokens returns every registered device token across all users.
// Used by the scheduler to send broadcast notifications.
func (r *NotificationRepository) GetAllTokens(ctx context.Context) ([]DeviceToken, error) {
	const q = `SELECT user_id, token, platform FROM device_tokens`
	rows, err := r.db.QueryContext(ctx, q)
	if err != nil {
		return nil, fmt.Errorf("GetAllTokens: %w", err)
	}
	defer rows.Close()

	var result []DeviceToken
	for rows.Next() {
		var dt DeviceToken
		if err := rows.Scan(&dt.UserID, &dt.Token, &dt.Platform); err != nil {
			return nil, fmt.Errorf("GetAllTokens scan: %w", err)
		}
		result = append(result, dt)
	}
	return result, rows.Err()
}

// DeleteTokens removes device tokens FCM reported as dead (uninstalled app,
// rotated token), for every user that held them.
func (r *NotificationRepository) DeleteTokens(ctx context.Context, tokens []string) error {
	if len(tokens) == 0 {
		return nil
	}
	if _, err := r.db.ExecContext(ctx, `DELETE FROM device_tokens WHERE token = ANY($1)`, pq.Array(tokens)); err != nil {
		return fmt.Errorf("DeleteTokens: %w", err)
	}
	return nil
}
