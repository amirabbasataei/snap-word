package repository

import (
	"context"
	"database/sql"
	"fmt"
)

// FriendshipRepository handles friendship DB operations.
// Phase 10 adds GetFriendIDs for the friends leaderboard.
// Phase 11 will add full CRUD methods.
type FriendshipRepository struct {
	db *sql.DB
}

func NewFriendshipRepository(db *sql.DB) *FriendshipRepository {
	return &FriendshipRepository{db: db}
}

// GetFriendIDs returns all accepted friend IDs for userID (both directions).
func (r *FriendshipRepository) GetFriendIDs(ctx context.Context, userID string) ([]string, error) {
	const q = `
		SELECT CASE WHEN requester_id = $1 THEN addressee_id ELSE requester_id END
		FROM friendships
		WHERE (requester_id = $1 OR addressee_id = $1) AND status = 'accepted'`

	rows, err := r.db.QueryContext(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("GetFriendIDs: %w", err)
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("GetFriendIDs scan: %w", err)
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}
