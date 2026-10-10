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

// AllTimeRow is one row of the all-time ranking.
type AllTimeRow struct {
	UserID   string
	Username string
	Score    int64
}

// AddTotalScore adds score to the player's lifetime total, creating the
// player_stats row if the player has none yet.
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

// GetAllTimeTop returns the top n players by lifetime score. The AI system user
// is excluded, ties break by earliest account for a stable order.
func (r *LeaderboardRepository) GetAllTimeTop(ctx context.Context, n int, excludeUserID string) ([]AllTimeRow, error) {
	const q = `
		SELECT ps.user_id, COALESCE(u.username, ''), ps.total_score
		FROM player_stats ps
		JOIN users u ON u.id = ps.user_id
		WHERE ps.total_score > 0 AND ps.user_id <> $2 AND u.banned_at IS NULL
		ORDER BY ps.total_score DESC, u.created_at ASC
		LIMIT $1`
	rows, err := r.db.QueryContext(ctx, q, n, excludeUserID)
	if err != nil {
		return nil, fmt.Errorf("GetAllTimeTop: %w", err)
	}
	defer rows.Close()

	var out []AllTimeRow
	for rows.Next() {
		var row AllTimeRow
		if err := rows.Scan(&row.UserID, &row.Username, &row.Score); err != nil {
			return nil, fmt.Errorf("GetAllTimeTop scan: %w", err)
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

// GetAllTimeRank returns the player's 1-indexed rank and lifetime score.
// Returns 0, 0 when the player has no score yet.
func (r *LeaderboardRepository) GetAllTimeRank(ctx context.Context, userID, excludeUserID string) (int64, int64, error) {
	const q = `
		SELECT total_score,
		       1 + (SELECT COUNT(*) FROM player_stats
		            WHERE total_score > ps.total_score AND user_id <> $2
		              AND user_id NOT IN (SELECT id FROM users WHERE banned_at IS NOT NULL))
		FROM player_stats ps
		WHERE ps.user_id = $1 AND ps.total_score > 0`
	var score, rank int64
	err := r.db.QueryRowContext(ctx, q, userID, excludeUserID).Scan(&score, &rank)
	if err == sql.ErrNoRows {
		return 0, 0, nil
	}
	if err != nil {
		return 0, 0, fmt.Errorf("GetAllTimeRank: %w", err)
	}
	return rank, score, nil
}
