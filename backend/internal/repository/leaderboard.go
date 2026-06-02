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
