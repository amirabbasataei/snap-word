-- Lifetime score for the all-time leaderboard; fed by LeaderboardService.AddScore
-- (same games as the weekly board). Counts from the day this ships.
ALTER TABLE player_stats ADD COLUMN total_score BIGINT NOT NULL DEFAULT 0;
CREATE INDEX idx_player_stats_total_score ON player_stats (total_score DESC) WHERE total_score > 0;
