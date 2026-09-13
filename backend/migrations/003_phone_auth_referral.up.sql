-- 003_phone_auth_referral.up.sql
-- Replaces email/password auth with phone number + OTP auth, and adds the
-- referral-code system. No real users exist yet, so this reshapes `users`
-- directly instead of migrating data.

TRUNCATE TABLE users CASCADE;

ALTER TABLE users DROP COLUMN IF EXISTS email;
ALTER TABLE users DROP COLUMN IF EXISTS password_hash;

-- username/referral_code are now populated lazily at first successful
-- verify-otp (signup completion), not at row creation, so they must allow NULL.
ALTER TABLE users ALTER COLUMN username DROP NOT NULL;

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(11) NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS otp_code CHAR(4);
ALTER TABLE users ADD COLUMN IF NOT EXISTS otp_expires_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS otp_attempts SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS otp_sent_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_code VARCHAR(6);
ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by UUID REFERENCES users(id);

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_format_chk;
ALTER TABLE users ADD CONSTRAINT users_phone_format_chk CHECK (phone ~ '^09[0-9]{9}$');

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_no_self_referral_chk;
ALTER TABLE users ADD CONSTRAINT users_no_self_referral_chk CHECK (referred_by IS NULL OR referred_by <> id);

DROP INDEX IF EXISTS users_email_key;
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_key ON users(phone);
CREATE UNIQUE INDEX IF NOT EXISTS users_referral_code_key ON users(referral_code) WHERE referral_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS users_referred_by_idx ON users(referred_by);
