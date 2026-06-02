package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

var ErrChallengeNotFound = errors.New("challenge not found")

type FriendChallenge struct {
	ID           string
	ChallengerID string
	ChallengedID string
	Mode         string
	MatchID      *string
	RoomID       *string
	Status       string
	CreatedAt    time.Time
	ExpiresAt    time.Time
}

// ChallengeRepository handles friend challenge DB operations.
type ChallengeRepository struct {
	db *sql.DB
}

func NewChallengeRepository(db *sql.DB) *ChallengeRepository {
	return &ChallengeRepository{db: db}
}

// CreateChallenge inserts a new pending challenge with a 24-hour expiry.
func (r *ChallengeRepository) CreateChallenge(ctx context.Context, challengerID, challengedID, mode string) (*FriendChallenge, error) {
	const q = `
		INSERT INTO friend_challenges (challenger_id, challenged_id, mode, expires_at)
		VALUES ($1, $2, $3, now() + interval '24 hours')
		RETURNING id, challenger_id, challenged_id, mode, match_id, room_id, status, created_at, expires_at`

	return r.scanRow(r.db.QueryRowContext(ctx, q, challengerID, challengedID, mode))
}

// GetChallenge retrieves a single challenge by ID.
func (r *ChallengeRepository) GetChallenge(ctx context.Context, challengeID string) (*FriendChallenge, error) {
	const q = `
		SELECT id, challenger_id, challenged_id, mode, match_id, room_id, status, created_at, expires_at
		FROM friend_challenges WHERE id = $1`

	ch, err := r.scanRow(r.db.QueryRowContext(ctx, q, challengeID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrChallengeNotFound
	}
	return ch, err
}

// RespondToChallenge updates the status of a pending challenge and optionally sets the room_id.
func (r *ChallengeRepository) RespondToChallenge(ctx context.Context, challengeID, status string, roomID *string) error {
	const q = `
		UPDATE friend_challenges
		SET status = $1, room_id = COALESCE($2, room_id)
		WHERE id = $3 AND status = 'pending'`

	res, err := r.db.ExecContext(ctx, q, status, roomID, challengeID)
	if err != nil {
		return fmt.Errorf("RespondToChallenge: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrChallengeNotFound
	}
	return nil
}

// GetPendingChallenges returns non-expired pending challenges where userID is the challenged player.
func (r *ChallengeRepository) GetPendingChallenges(ctx context.Context, userID string) ([]*FriendChallenge, error) {
	const q = `
		SELECT id, challenger_id, challenged_id, mode, match_id, room_id, status, created_at, expires_at
		FROM friend_challenges
		WHERE challenged_id = $1 AND status = 'pending' AND expires_at > now()
		ORDER BY created_at DESC`

	rows, err := r.db.QueryContext(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("GetPendingChallenges: %w", err)
	}
	defer rows.Close()

	var challenges []*FriendChallenge
	for rows.Next() {
		ch, err := r.scanRows(rows)
		if err != nil {
			return nil, fmt.Errorf("GetPendingChallenges scan: %w", err)
		}
		challenges = append(challenges, ch)
	}
	return challenges, rows.Err()
}

// ExpireOldChallenges marks overdue pending challenges as expired and returns them
// so callers can send notifications to challengers.
func (r *ChallengeRepository) ExpireOldChallenges(ctx context.Context) ([]*FriendChallenge, error) {
	const q = `
		UPDATE friend_challenges SET status = 'expired'
		WHERE status = 'pending' AND expires_at <= now()
		RETURNING id, challenger_id, challenged_id, mode, match_id, room_id, status, created_at, expires_at`

	rows, err := r.db.QueryContext(ctx, q)
	if err != nil {
		return nil, fmt.Errorf("ExpireOldChallenges: %w", err)
	}
	defer rows.Close()

	var expired []*FriendChallenge
	for rows.Next() {
		ch, err := r.scanRows(rows)
		if err != nil {
			return nil, fmt.Errorf("ExpireOldChallenges scan: %w", err)
		}
		expired = append(expired, ch)
	}
	return expired, rows.Err()
}

func (r *ChallengeRepository) scanRow(row *sql.Row) (*FriendChallenge, error) {
	ch := &FriendChallenge{}
	var matchID, roomID sql.NullString
	err := row.Scan(&ch.ID, &ch.ChallengerID, &ch.ChallengedID, &ch.Mode,
		&matchID, &roomID, &ch.Status, &ch.CreatedAt, &ch.ExpiresAt)
	if err != nil {
		return nil, err
	}
	if matchID.Valid {
		ch.MatchID = &matchID.String
	}
	if roomID.Valid {
		ch.RoomID = &roomID.String
	}
	return ch, nil
}

func (r *ChallengeRepository) scanRows(rows *sql.Rows) (*FriendChallenge, error) {
	ch := &FriendChallenge{}
	var matchID, roomID sql.NullString
	err := rows.Scan(&ch.ID, &ch.ChallengerID, &ch.ChallengedID, &ch.Mode,
		&matchID, &roomID, &ch.Status, &ch.CreatedAt, &ch.ExpiresAt)
	if err != nil {
		return nil, err
	}
	if matchID.Valid {
		ch.MatchID = &matchID.String
	}
	if roomID.Valid {
		ch.RoomID = &roomID.String
	}
	return ch, nil
}
