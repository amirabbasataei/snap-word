package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"wordchain/backend/internal/config"
)

// InboxMessage is an admin in-app message as the player sees it.
type InboxMessage struct {
	ID        string
	Title     string
	Body      string
	Route     string
	CreatedAt time.Time
}

// InboxRepository serves the player's unread admin messages.
type InboxRepository struct {
	db *sql.DB
}

func NewInboxRepository(db *sql.DB) *InboxRepository { return &InboxRepository{db: db} }

// ListUnread returns the player's unread messages from the retention window, newest first.
func (r *InboxRepository) ListUnread(ctx context.Context, userID string) ([]InboxMessage, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT m.id, c.title, c.body, c.route, m.created_at
		   FROM inbox_messages m JOIN notification_campaigns c ON c.id = m.campaign_id
		  WHERE m.user_id = $1 AND m.read_at IS NULL AND m.created_at > now() - make_interval(secs => $2)
		  ORDER BY m.created_at DESC LIMIT $3`,
		userID, config.InboxMessageTTL.Seconds(), config.InboxMessageListMax)
	if err != nil {
		return nil, fmt.Errorf("InboxRepository.ListUnread: %w", err)
	}
	defer rows.Close()
	out := []InboxMessage{}
	for rows.Next() {
		var m InboxMessage
		if err := rows.Scan(&m.ID, &m.Title, &m.Body, &m.Route, &m.CreatedAt); err != nil {
			return nil, fmt.Errorf("InboxRepository.ListUnread scan: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// MarkRead marks one of the player's messages read; false when it is not theirs
// or was already read (the call is idempotent either way).
func (r *InboxRepository) MarkRead(ctx context.Context, userID, id string) (bool, error) {
	res, err := r.db.ExecContext(ctx,
		`UPDATE inbox_messages SET read_at = now() WHERE id = $1 AND user_id = $2 AND read_at IS NULL`, id, userID)
	if err != nil {
		return false, fmt.Errorf("InboxRepository.MarkRead: %w", err)
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}
