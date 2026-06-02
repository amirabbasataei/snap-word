package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

var ErrStatsNotFound = errors.New("stats not found")

type PlayerStats struct {
	UserID             string
	TotalMatches       int
	Wins               int
	LongestWord        *string
	BestMatchStreak    int
	DailyStreak        int
	LongestDailyStreak int
	LastPlayedDate     *time.Time
	UpdatedAt          time.Time
}

type StatsRepository struct {
	db *sql.DB
}

func NewStatsRepository(db *sql.DB) *StatsRepository {
	return &StatsRepository{db: db}
}

func (r *StatsRepository) GetStats(ctx context.Context, userID string) (*PlayerStats, error) {
	const q = `
		SELECT user_id, total_matches, wins, longest_word, best_match_streak,
		       daily_streak, longest_daily_streak, last_played_date, updated_at
		FROM player_stats WHERE user_id = $1`

	s := &PlayerStats{}
	var longestWord sql.NullString
	var lastPlayedDate sql.NullTime

	err := r.db.QueryRowContext(ctx, q, userID).Scan(
		&s.UserID, &s.TotalMatches, &s.Wins, &longestWord,
		&s.BestMatchStreak, &s.DailyStreak, &s.LongestDailyStreak,
		&lastPlayedDate, &s.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrStatsNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetStats: %w", err)
	}

	if longestWord.Valid {
		s.LongestWord = &longestWord.String
	}
	if lastPlayedDate.Valid {
		s.LastPlayedDate = &lastPlayedDate.Time
	}
	return s, nil
}

// UpsertStats inserts or updates player_stats using MAX semantics for streak fields
// and longest-word length comparison.
func (r *StatsRepository) UpsertStats(ctx context.Context, stats *PlayerStats) error {
	const q = `
		INSERT INTO player_stats
		    (user_id, total_matches, wins, longest_word, best_match_streak,
		     daily_streak, longest_daily_streak, last_played_date, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now())
		ON CONFLICT (user_id) DO UPDATE SET
		    total_matches       = EXCLUDED.total_matches,
		    wins                = EXCLUDED.wins,
		    longest_word        = CASE
		        WHEN EXCLUDED.longest_word IS NOT NULL
		             AND (player_stats.longest_word IS NULL
		                  OR LENGTH(EXCLUDED.longest_word) > LENGTH(player_stats.longest_word))
		        THEN EXCLUDED.longest_word
		        ELSE player_stats.longest_word
		    END,
		    best_match_streak   = GREATEST(player_stats.best_match_streak, EXCLUDED.best_match_streak),
		    daily_streak        = EXCLUDED.daily_streak,
		    longest_daily_streak = GREATEST(player_stats.longest_daily_streak, EXCLUDED.longest_daily_streak),
		    last_played_date    = EXCLUDED.last_played_date,
		    updated_at          = now()`

	_, err := r.db.ExecContext(ctx, q,
		stats.UserID, stats.TotalMatches, stats.Wins, stats.LongestWord,
		stats.BestMatchStreak, stats.DailyStreak, stats.LongestDailyStreak,
		stats.LastPlayedDate,
	)
	if err != nil {
		return fmt.Errorf("UpsertStats: %w", err)
	}
	return nil
}

// UpdateStreak sets the daily streak fields without touching other columns.
func (r *StatsRepository) UpdateStreak(ctx context.Context, userID string, dailyStreak, longestDailyStreak int, lastPlayedDate time.Time) error {
	const q = `
		INSERT INTO player_stats (user_id, daily_streak, longest_daily_streak, last_played_date, updated_at)
		VALUES ($1, $2, $3, $4, now())
		ON CONFLICT (user_id) DO UPDATE SET
		    daily_streak         = EXCLUDED.daily_streak,
		    longest_daily_streak = GREATEST(player_stats.longest_daily_streak, EXCLUDED.longest_daily_streak),
		    last_played_date     = EXCLUDED.last_played_date,
		    updated_at           = now()`

	_, err := r.db.ExecContext(ctx, q, userID, dailyStreak, longestDailyStreak, lastPlayedDate)
	if err != nil {
		return fmt.Errorf("UpdateStreak: %w", err)
	}
	return nil
}

// GetUsersWithStreakAtRisk returns user IDs where daily_streak ≥ 3 and
// last_played_date equals yesterday (i.e., they haven't played today yet).
func (r *StatsRepository) GetUsersWithStreakAtRisk(ctx context.Context, today time.Time) ([]string, error) {
	yesterday := today.AddDate(0, 0, -1)
	const q = `SELECT user_id FROM player_stats WHERE daily_streak >= 3 AND last_played_date = $1`

	rows, err := r.db.QueryContext(ctx, q, yesterday)
	if err != nil {
		return nil, fmt.Errorf("GetUsersWithStreakAtRisk: %w", err)
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("GetUsersWithStreakAtRisk scan: %w", err)
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// IncrementMatchStats atomically increments total_matches and updates longest_word / last_played_date.
// All other fields are left unchanged by this operation.
func (r *StatsRepository) IncrementMatchStats(ctx context.Context, userID, longestWord string, playedAt time.Time) error {
	const q = `
		INSERT INTO player_stats (user_id, total_matches, last_played_date, longest_word, updated_at)
		VALUES ($1, 1, $2, $3, now())
		ON CONFLICT (user_id) DO UPDATE SET
		    total_matches    = player_stats.total_matches + 1,
		    last_played_date = EXCLUDED.last_played_date,
		    longest_word     = CASE
		        WHEN EXCLUDED.longest_word <> '' AND (
		             player_stats.longest_word IS NULL
		             OR LENGTH(EXCLUDED.longest_word) > LENGTH(player_stats.longest_word))
		        THEN EXCLUDED.longest_word
		        ELSE player_stats.longest_word
		    END,
		    updated_at = now()`

	_, err := r.db.ExecContext(ctx, q, userID, playedAt, longestWord)
	if err != nil {
		return fmt.Errorf("IncrementMatchStats: %w", err)
	}
	return nil
}
