-- Account bans (Phase 23, stage A4). banned_at IS NOT NULL ⇒ the account cannot
-- sign in, refresh, call the API, join the WebSocket or queue, and is hidden
-- from the leaderboards. Set and cleared only from the admin panel.
ALTER TABLE users ADD COLUMN banned_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN ban_reason TEXT;
CREATE INDEX idx_users_banned ON users (banned_at) WHERE banned_at IS NOT NULL;
