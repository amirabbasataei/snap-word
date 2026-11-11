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

// GetUserAttempts returns the user's attempts at one variant of the day,
// ordered by attempt_number ASC.
func (r *DailyRepository) GetUserAttempts(ctx context.Context, userID string, date time.Time, variant int) ([]*DailyAttemptRow, error) {
	const q = `
		SELECT attempt_number, score, chain_length, word_chain, completed_at
		FROM daily_challenge_attempts
		WHERE user_id = $1 AND challenge_date = $2 AND variant = $3
		ORDER BY attempt_number ASC`

	rows, err := r.db.QueryContext(ctx, q, userID, date, variant)
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

// FreeAttempt is the attempt number of a player's free Daily Challenge run.
// Rankings, the board and the prizes use only this attempt (Phase 25 S5): a
// paid retry (attempt 2) records a personal best but cannot buy a better rank.
const FreeAttempt = 1

// GetTodayBest returns the highest free-attempt score of one variant for the
// given date (the top of that variant's board).
func (r *DailyRepository) GetTodayBest(ctx context.Context, date time.Time, variant int) (int, error) {
	const q = `SELECT COALESCE(MAX(score), 0) FROM daily_challenge_attempts WHERE challenge_date = $1 AND attempt_number = $2 AND variant = $3`
	var best int
	if err := r.db.QueryRowContext(ctx, q, date, FreeAttempt, variant).Scan(&best); err != nil {
		return 0, fmt.Errorf("GetTodayBest: %w", err)
	}
	return best, nil
}

// GetUserRank returns the user's rank (1 = best) among all players of one
// variant for the date by their free attempt, or nil if they have no free
// attempt at it yet.
func (r *DailyRepository) GetUserRank(ctx context.Context, date time.Time, variant int, userID string) (*int, error) {
	const q = `
		SELECT rank FROM (
			SELECT user_id, RANK() OVER (ORDER BY score DESC) AS rank
			FROM daily_challenge_attempts
			WHERE challenge_date = $1 AND attempt_number = $2 AND variant = $4
		) ranked
		WHERE user_id = $3`

	var rank int
	err := r.db.QueryRowContext(ctx, q, date, FreeAttempt, userID, variant).Scan(&rank)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("GetUserRank: %w", err)
	}
	return &rank, nil
}

// InsertAttempt stores a completed daily attempt at one variant.
func (r *DailyRepository) InsertAttempt(ctx context.Context, userID string, date time.Time, variant, attemptNumber, score int, wordChain []string) error {
	const q = `
		INSERT INTO daily_challenge_attempts (user_id, challenge_date, variant, attempt_number, score, chain_length, word_chain)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT DO NOTHING`

	if wordChain == nil {
		wordChain = []string{}
	}
	if _, err := r.db.ExecContext(ctx, q, userID, date, variant, attemptNumber, score, len(wordChain), pq.Array(wordChain)); err != nil {
		return fmt.Errorf("InsertAttempt: %w", err)
	}
	return nil
}

// RecordRetry marks the paid retry of one variant as purchased; false means
// it already was.
func (r *DailyRepository) RecordRetry(ctx context.Context, userID string, date time.Time, variant int) (bool, error) {
	const q = `INSERT INTO daily_retries (user_id, challenge_date, variant) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`
	res, err := r.db.ExecContext(ctx, q, userID, date, variant)
	if err != nil {
		return false, fmt.Errorf("RecordRetry: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("RecordRetry: %w", err)
	}
	return n > 0, nil
}

func (r *DailyRepository) DeleteRetry(ctx context.Context, userID string, date time.Time, variant int) error {
	const q = `DELETE FROM daily_retries WHERE user_id = $1 AND challenge_date = $2 AND variant = $3`
	if _, err := r.db.ExecContext(ctx, q, userID, date, variant); err != nil {
		return fmt.Errorf("DeleteRetry: %w", err)
	}
	return nil
}

func (r *DailyRepository) HasRetry(ctx context.Context, userID string, date time.Time, variant int) (bool, error) {
	const q = `SELECT EXISTS (SELECT 1 FROM daily_retries WHERE user_id = $1 AND challenge_date = $2 AND variant = $3)`
	var ok bool
	if err := r.db.QueryRowContext(ctx, q, userID, date, variant).Scan(&ok); err != nil {
		return false, fmt.Errorf("HasRetry: %w", err)
	}
	return ok, nil
}

// DailyBoardRow is one player's free-attempt result for a challenge date.
type DailyBoardRow struct {
	Rank        int
	UserID      string
	Username    string
	Score       int
	ChainLength int
}

// GetDailyLeaderboard ranks the players of one variant by their free attempt
// for the date (ties share a rank). A paid retry is not on the board and earns
// no prize.
func (r *DailyRepository) GetDailyLeaderboard(ctx context.Context, date time.Time, variant, limit int) ([]*DailyBoardRow, error) {
	const q = `
		SELECT rank, user_id, username, score, chain_length FROM (
			SELECT a.user_id, COALESCE(u.username, '') AS username,
			       a.score, a.chain_length,
			       RANK() OVER (ORDER BY a.score DESC) AS rank
			FROM daily_challenge_attempts a JOIN users u ON u.id = a.user_id
			WHERE a.challenge_date = $1 AND a.attempt_number = $3 AND a.variant = $4
		) t ORDER BY rank, username LIMIT $2`

	rows, err := r.db.QueryContext(ctx, q, date, limit, FreeAttempt, variant)
	if err != nil {
		return nil, fmt.Errorf("GetDailyLeaderboard: %w", err)
	}
	defer rows.Close()

	var out []*DailyBoardRow
	for rows.Next() {
		var b DailyBoardRow
		if err := rows.Scan(&b.Rank, &b.UserID, &b.Username, &b.Score, &b.ChainLength); err != nil {
			return nil, fmt.Errorf("GetDailyLeaderboard scan: %w", err)
		}
		out = append(out, &b)
	}
	return out, rows.Err()
}

// PlayedVariants returns the variants the user has a free attempt at for the
// date, ascending (the type picker marks them as played).
func (r *DailyRepository) PlayedVariants(ctx context.Context, userID string, date time.Time) ([]int, error) {
	const q = `
		SELECT DISTINCT variant FROM daily_challenge_attempts
		WHERE user_id = $1 AND challenge_date = $2 AND attempt_number = $3
		ORDER BY variant`
	rows, err := r.db.QueryContext(ctx, q, userID, date, FreeAttempt)
	if err != nil {
		return nil, fmt.Errorf("PlayedVariants: %w", err)
	}
	defer rows.Close()
	out := []int{}
	for rows.Next() {
		var v int
		if err := rows.Scan(&v); err != nil {
			return nil, fmt.Errorf("PlayedVariants scan: %w", err)
		}
		out = append(out, v)
	}
	return out, rows.Err()
}
