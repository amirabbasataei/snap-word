-- 001_init.down.sql
-- Drops all tables in reverse dependency order.

DROP INDEX IF EXISTS idx_daily_attempts_date;
DROP INDEX IF EXISTS idx_device_tokens_user;
DROP INDEX IF EXISTS idx_friend_challenges_expires;
DROP INDEX IF EXISTS idx_friend_challenges_challenged;
DROP INDEX IF EXISTS idx_friendships_addressee;
DROP INDEX IF EXISTS idx_match_players_user;
DROP INDEX IF EXISTS idx_matches_created_at;
DROP INDEX IF EXISTS idx_matches_status;

DROP TABLE IF EXISTS weekly_leaderboard_rewards;
DROP TABLE IF EXISTS device_tokens;
DROP TABLE IF EXISTS friend_challenges;
DROP TABLE IF EXISTS friendships;
DROP TABLE IF EXISTS daily_challenge_attempts;
DROP TABLE IF EXISTS daily_challenges;
DROP TABLE IF EXISTS powerup_inventory;
DROP TABLE IF EXISTS player_stats;
DROP TABLE IF EXISTS match_players;
DROP TABLE IF EXISTS matches;
DROP TABLE IF EXISTS users;
