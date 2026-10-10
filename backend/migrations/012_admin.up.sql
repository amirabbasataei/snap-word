-- Admin panel accounts and audit trail (Phase 23, stage A1). Admins are
-- separate from players: they sign in with a username + password and hold a
-- server-side session in Redis, never a player JWT.
CREATE TABLE admin_users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username      VARCHAR(32) UNIQUE NOT NULL,
    password_hash TEXT        NOT NULL,
    role          TEXT        NOT NULL CHECK (role IN ('owner', 'operator', 'viewer')),
    totp_secret   TEXT,
    disabled_at   TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- admin_id is NULL for actions that have no admin row: the X-Admin-Key script
-- (actor = 'script') and failed logins (actor = the attempted username).
CREATE TABLE admin_audit_log (
    id          BIGSERIAL PRIMARY KEY,
    admin_id    UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    actor       TEXT NOT NULL,
    action      TEXT NOT NULL,
    target_type TEXT,
    target_id   TEXT,
    payload     JSONB,
    ip          INET,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_admin_audit_log_created_at ON admin_audit_log (created_at DESC);
