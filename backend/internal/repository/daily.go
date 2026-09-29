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
	ErrNoDailyChallenge = errors.New("no_daily_challenge")
)

type DailyChallengeRow struct {
	ChallengeDate time.Time
	Seed          int64
	StartLetter   string
}

type DailyAttemptRow struct {
	AttemptNumber int
	Score         int
	ChainLength   int
	WordChain     []string
	CompletedAt   time.Time
}

type DailyRepository struct {
	db *sql.DB
}

func NewDailyRepository(db *sql.DB) *DailyRepository {
	return &DailyRepository{db: db}
}

func (r *DailyRepository) GetChallenge(ctx context.Context, date time.Time) (*DailyChallengeRow, error) {
	const q = `SELECT challenge_date, seed, start_letter FROM daily_challenges WHERE challenge_date = $1`
	row := &DailyChallengeRow{}
	err := r.db.QueryRowContext(ctx, q, date).Scan(&row.ChallengeDate, &row.Seed, &row.StartLetter)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNoDailyChallenge
	}
	if err != nil {
		return nil, fmt.Errorf("GetChallenge: %w", err)
	}
	return row, nil
}

// CreateChallengeIfMissing inserts a daily_challenges row for date unless one
// already exists, and reports whether it inserted one.
func (r *DailyRepository) CreateChallengeIfMissing(ctx context.Context, date time.Time, seed int64, startLetter string) (bool, error) {
	const q = `
		INSERT INTO daily_challenges (challenge_date, seed, start_letter)
		VALUES ($1, $2, $3)
		ON CONFLICT (challenge_date) DO NOTHING`

	res, err := r.db.ExecContext(ctx, q, date, seed, startLetter)
	if err != nil {
		return false, fmt.Errorf("CreateChallengeIfMissing: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("CreateChallengeIfMissing: %w", err)
	}
	return n > 0, nil
}

// GetUserAttempts returns attempts ordered by attempt_number ASC.
func (r *DailyRepository) GetUserAttempts(ctx context.Context, userID string, date time.Time) ([]*DailyAttemptRow, error) {
	const q = `
		SELECT attempt_number, score, chain_length, word_chain, completed_at
		FROM daily_challenge_attempts
		WHERE user_id = $1 AND challenge_date = $2
		ORDER BY attempt_number ASC`

	rows, err := r.db.QueryContext(ctx, q, userID, date)
	if err != nil {
		return nil, fmt.Errorf("GetUserAttempts: %w", err)
	}
	defer rows.Close()

	var attempts []*DailyAttemptRow
	for rows.Next() {
		a := &DailyAttemptRow{}
		var wc pq.StringArray
		if err := rows.Scan(&a.AttemptNumber, &a.Score, &a.ChainLength, &wc, &a.CompletedAt); err != nil {
			return nil, fmt.Errorf("GetUserAttempts scan: %w", err)
		}
		a.WordChain = []string(wc)
		attempts = append(attempts, a)
	}
	return attempts, rows.Err()
}

// GetTodayBest returns the highest score submitted by any player for the given date.
func (r *DailyRepository) GetTodayBest(ctx context.Context, date time.Time) (int, error) {
	const q = `SELECT COALESCE(MAX(score), 0) FROM daily_challenge_attempts WHERE challenge_date = $1`
	var best int
	if err := r.db.QueryRowContext(ctx, q, date).Scan(&best); err != nil {
		return 0, fmt.Errorf("GetTodayBest: %w", err)
	}
	return best, nil
}

// GetUserRank returns the user's rank (1 = best) among all players for the date,
// or nil if they have not submitted an attempt.
func (r *DailyRepository) GetUserRank(ctx context.Context, date time.Time, userID string) (*int, error) {
	const q = `
		SELECT rank FROM (
			SELECT user_id, RANK() OVER (ORDER BY MAX(score) DESC) AS rank
			FROM daily_challenge_attempts
			WHERE challenge_date = $1
			GROUP BY user_id
		) ranked
		WHERE user_id = $2`

	var rank int
	err := r.db.QueryRowContext(ctx, q, date, userID).Scan(&rank)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("GetUserRank: %w", err)
	}
	return &rank, nil
}

// InsertAttempt stores a completed daily attempt.
func (r *DailyRepository) InsertAttempt(ctx context.Context, userID string, date time.Time, attemptNumber, score int, wordChain []string) error {
	const q = `
		INSERT INTO daily_challenge_attempts (user_id, challenge_date, attempt_number, score, chain_length, word_chain)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT DO NOTHING`

	if wordChain == nil {
		wordChain = []string{}
	}
	if _, err := r.db.ExecContext(ctx, q, userID, date, attemptNumber, score, len(wordChain), pq.Array(wordChain)); err != nil {
		return fmt.Errorf("InsertAttempt: %w", err)
	}
	return nil
}

// RecordRetry marks the paid retry as purchased; false means it already was.
func (r *DailyRepository) RecordRetry(ctx context.Context, userID string, date time.Time) (bool, error) {
	const q = `INSERT INTO daily_retries (user_id, challenge_date) VALUES ($1, $2) ON CONFLICT DO NOTHING`
	res, err := r.db.ExecContext(ctx, q, userID, date)
	if err != nil {
		return false, fmt.Errorf("RecordRetry: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("RecordRetry: %w", err)
	}
	return n > 0, nil
}

func (r *DailyRepository) DeleteRetry(ctx context.Context, userID string, date time.Time) error {
	const q = `DELETE FROM daily_retries WHERE user_id = $1 AND challenge_date = $2`
	if _, err := r.db.ExecContext(ctx, q, userID, date); err != nil {
		return fmt.Errorf("DeleteRetry: %w", err)
	}
	return nil
}

func (r *DailyRepository) HasRetry(ctx context.Context, userID string, date time.Time) (bool, error) {
	const q = `SELECT EXISTS (SELECT 1 FROM daily_retries WHERE user_id = $1 AND challenge_date = $2)`
	var ok bool
	if err := r.db.QueryRowContext(ctx, q, userID, date).Scan(&ok); err != nil {
		return false, fmt.Errorf("HasRetry: %w", err)
	}
	return ok, nil
}
