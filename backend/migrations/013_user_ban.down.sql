DROP INDEX IF EXISTS idx_users_banned;
ALTER TABLE users DROP COLUMN ban_reason;
ALTER TABLE users DROP COLUMN banned_at;
