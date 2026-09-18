-- 004_ai_system_user.up.sql
-- Seeds a fixed, well-known users row for the matchmaking AI-fallback
-- opponent (internal/service/matchmaking.go, config.SystemAIUserID). A
-- single shared identity is used for all difficulties — match_players.is_ai
-- flags AI rows, and finalizeToDB (internal/ws/room.go) never records this
-- user in player_stats or the weekly leaderboard. Needed because
-- match_players.user_id is a NOT NULL FK into users(id); the synthetic
-- "ai:<difficulty>:<room8>" string previously used there was neither a
-- valid UUID nor backed by a real users row.

INSERT INTO users (id, username, phone, phone_verified_at, coins)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    NULL,
    '09000000000',
    now(),
    0
)
ON CONFLICT (id) DO NOTHING;
