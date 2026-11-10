package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// LeaderboardRepository handles DB operations for weekly leaderboard rewards.
type LeaderboardRepository struct {
	db *sql.DB
}

func NewLeaderboardRepository(db *sql.DB) *LeaderboardRepository {
	return &LeaderboardRepository{db: db}
}

// InsertWeeklyReward records a weekly leaderboard reward.
// Returns true if the row was newly inserted; false on conflict (already rewarded).
func (r *LeaderboardRepository) InsertWeeklyReward(ctx context.Context, weekStart time.Time, userID string, rank, coinsAwarded int) (bool, error) {
	const q = `
		INSERT INTO weekly_leaderboard_rewards (week_start, user_id, rank, coins_awarded)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (week_start, user_id) DO NOTHING`

	result, err := r.db.ExecContext(ctx, q, weekStart, userID, rank, coinsAwarded)
	if err != nil {
		return false, fmt.Errorf("InsertWeeklyReward: %w", err)
	}
	n, _ := result.RowsAffected()
	return n > 0, nil
}

// AddTotalScore adds score to the player's lifetime total (a profile stat;
// the boards rank the rating since Phase 25 S2), creating the player_stats row
// if the player has none yet.
func (r *LeaderboardRepository) AddTotalScore(ctx context.Context, userID string, score int) error {
	const q = `
		INSERT INTO player_stats (user_id, total_score, updated_at)
		VALUES ($1, $2, now())
		ON CONFLICT (user_id) DO UPDATE SET
		    total_score = player_stats.total_score + EXCLUDED.total_score,
		    updated_at  = now()`
	if _, err := r.db.ExecContext(ctx, q, userID, score); err != nil {
		return fmt.Errorf("AddTotalScore: %w", err)
	}
	return nil
}
