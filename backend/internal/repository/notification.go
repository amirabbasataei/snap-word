package repository

import (
	"context"
	"database/sql"
	"fmt"
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

// RegisterToken upserts a device token for the given user.
func (r *NotificationRepository) RegisterToken(ctx context.Context, userID, token, platform string) error {
	const q = `
		INSERT INTO device_tokens (user_id, token, platform, updated_at)
		VALUES ($1, $2, $3, now())
		ON CONFLICT (user_id, token) DO UPDATE SET platform = EXCLUDED.platform, updated_at = now()`
	_, err := r.db.ExecContext(ctx, q, userID, token, platform)
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
