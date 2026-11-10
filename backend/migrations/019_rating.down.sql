DROP TABLE IF EXISTS rating_history;
DROP INDEX IF EXISTS idx_player_stats_rating;
ALTER TABLE player_stats
    DROP COLUMN IF EXISTS peak_rating,
    DROP COLUMN IF EXISTS rated_games,
    DROP COLUMN IF EXISTS rating;
