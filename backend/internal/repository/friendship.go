package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

var (
	ErrFriendshipNotFound = errors.New("friendship not found")
	ErrFriendshipExists   = errors.New("friendship already exists")
)

type Friendship struct {
	RequesterID string
	AddresseeID string
	Status      string
	CreatedAt   time.Time
}

type FriendInfo struct {
	UserID    string
	Username  string
	CreatedAt time.Time
}

type PendingRequest struct {
	RequesterID string
	Username    string
	CreatedAt   time.Time
}

// FriendshipRepository handles friendship DB operations.
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

// SendRequest creates a pending friendship request. Returns ErrFriendshipExists if one already exists.
func (r *FriendshipRepository) SendRequest(ctx context.Context, requesterID, addresseeID string) error {
	const q = `
		INSERT INTO friendships (requester_id, addressee_id, status)
		VALUES ($1, $2, 'pending')
		ON CONFLICT (requester_id, addressee_id) DO NOTHING`

	res, err := r.db.ExecContext(ctx, q, requesterID, addresseeID)
	if err != nil {
		return fmt.Errorf("SendRequest: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrFriendshipExists
	}
	return nil
}

// GetFriendship returns the friendship row between two users (either direction).
func (r *FriendshipRepository) GetFriendship(ctx context.Context, userID1, userID2 string) (*Friendship, error) {
	const q = `
		SELECT requester_id, addressee_id, status, created_at
		FROM friendships
		WHERE (requester_id = $1 AND addressee_id = $2)
		   OR (requester_id = $2 AND addressee_id = $1)`

	f := &Friendship{}
	err := r.db.QueryRowContext(ctx, q, userID1, userID2).
		Scan(&f.RequesterID, &f.AddresseeID, &f.Status, &f.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrFriendshipNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetFriendship: %w", err)
	}
	return f, nil
}

// RespondToRequest updates a pending friendship from requesterID → addresseeID.
func (r *FriendshipRepository) RespondToRequest(ctx context.Context, requesterID, addresseeID, status string) error {
	const q = `
		UPDATE friendships SET status = $1
		WHERE requester_id = $2 AND addressee_id = $3 AND status = 'pending'`

	res, err := r.db.ExecContext(ctx, q, status, requesterID, addresseeID)
	if err != nil {
		return fmt.Errorf("RespondToRequest: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrFriendshipNotFound
	}
	return nil
}

// ListFriends returns all accepted friends with usernames for the given user.
func (r *FriendshipRepository) ListFriends(ctx context.Context, userID string) ([]*FriendInfo, error) {
	const q = `
		SELECT u.id, u.username, f.created_at
		FROM friendships f
		JOIN users u ON u.id = CASE
			WHEN f.requester_id = $1 THEN f.addressee_id
			ELSE f.requester_id
		END
		WHERE (f.requester_id = $1 OR f.addressee_id = $1) AND f.status = 'accepted'
		ORDER BY u.username`

	rows, err := r.db.QueryContext(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("ListFriends: %w", err)
	}
	defer rows.Close()

	var friends []*FriendInfo
	for rows.Next() {
		fi := &FriendInfo{}
		if err := rows.Scan(&fi.UserID, &fi.Username, &fi.CreatedAt); err != nil {
			return nil, fmt.Errorf("ListFriends scan: %w", err)
		}
		friends = append(friends, fi)
	}
	return friends, rows.Err()
}

// ListPendingRequests returns all pending friend requests addressed to addresseeID.
func (r *FriendshipRepository) ListPendingRequests(ctx context.Context, addresseeID string) ([]*PendingRequest, error) {
	const q = `
		SELECT u.id, u.username, f.created_at
		FROM friendships f
		JOIN users u ON u.id = f.requester_id
		WHERE f.addressee_id = $1 AND f.status = 'pending'
		ORDER BY f.created_at DESC`

	rows, err := r.db.QueryContext(ctx, q, addresseeID)
	if err != nil {
		return nil, fmt.Errorf("ListPendingRequests: %w", err)
	}
	defer rows.Close()

	var requests []*PendingRequest
	for rows.Next() {
		pr := &PendingRequest{}
		if err := rows.Scan(&pr.RequesterID, &pr.Username, &pr.CreatedAt); err != nil {
			return nil, fmt.Errorf("ListPendingRequests scan: %w", err)
		}
		requests = append(requests, pr)
	}
	return requests, rows.Err()
}

// RemoveFriend deletes the friendship between two users (either direction).
func (r *FriendshipRepository) RemoveFriend(ctx context.Context, userID, friendID string) error {
	const q = `
		DELETE FROM friendships
		WHERE (requester_id = $1 AND addressee_id = $2)
		   OR (requester_id = $2 AND addressee_id = $1)`

	_, err := r.db.ExecContext(ctx, q, userID, friendID)
	if err != nil {
		return fmt.Errorf("RemoveFriend: %w", err)
	}
	return nil
}
