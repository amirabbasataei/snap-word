-- 003_phone_auth_referral.down.sql
-- Best-effort rollback to the email/password schema. Lossy of phone/OTP/
-- referral data (table is re-truncated first) since no real users exist.

TRUNCATE TABLE users CASCADE;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_no_self_referral_chk;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_format_chk;
DROP INDEX IF EXISTS users_referred_by_idx;
DROP INDEX IF EXISTS users_referral_code_key;
DROP INDEX IF EXISTS users_phone_key;

ALTER TABLE users DROP COLUMN IF EXISTS referred_by;
ALTER TABLE users DROP COLUMN IF EXISTS referral_code;
ALTER TABLE users DROP COLUMN IF EXISTS phone_verified_at;
ALTER TABLE users DROP COLUMN IF EXISTS otp_sent_at;
ALTER TABLE users DROP COLUMN IF EXISTS otp_attempts;
ALTER TABLE users DROP COLUMN IF EXISTS otp_expires_at;
ALTER TABLE users DROP COLUMN IF EXISTS otp_code;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

ALTER TABLE users ADD COLUMN email VARCHAR(255);
ALTER TABLE users ADD COLUMN password_hash TEXT;
UPDATE users SET email = '', password_hash = '';
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN password_hash SET NOT NULL;
ALTER TABLE users ALTER COLUMN username SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS users_email_key ON users(email);
