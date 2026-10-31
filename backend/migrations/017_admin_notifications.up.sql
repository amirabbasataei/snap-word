-- Admin notifications (Phase 23, stage A6).
--
-- device_tokens.permission records what the OS said when the app last
-- registered the token. A token row alone never meant "allowed to notify": FCM
-- hands out a token even when the user refused the permission.
--   granted | denied | not_determined   reported by the client
--   unknown                              rows registered before this column
ALTER TABLE device_tokens ADD COLUMN permission VARCHAR(16) NOT NULL DEFAULT 'unknown';

-- One row per admin send (push, in-app message, or both).
CREATE TABLE notification_campaigns (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title            VARCHAR(120) NOT NULL,
    body             TEXT         NOT NULL,
    route            VARCHAR(32)  NOT NULL DEFAULT '',       -- deep link opened by the push / message
    push             BOOLEAN      NOT NULL,
    inapp            BOOLEAN      NOT NULL,
    audience_type    VARCHAR(16)  NOT NULL,                  -- all | segment | users
    audience         JSONB        NOT NULL DEFAULT '{}',
    created_by       VARCHAR(64)  NOT NULL,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    recipients       INTEGER      NOT NULL DEFAULT 0,        -- accounts matched by the audience
    inapp_delivered  INTEGER      NOT NULL DEFAULT 0,        -- inbox rows created
    push_status      VARCHAR(16)  NOT NULL DEFAULT 'none',   -- none | sending | done | failed | interrupted
    push_users       INTEGER      NOT NULL DEFAULT 0,        -- accounts with a deliverable device
    push_devices     INTEGER      NOT NULL DEFAULT 0,        -- device tokens attempted
    push_sent        INTEGER      NOT NULL DEFAULT 0,        -- accepted by FCM
    push_failed      INTEGER      NOT NULL DEFAULT 0,
    push_removed     INTEGER      NOT NULL DEFAULT 0,        -- dead tokens FCM reported and we deleted
    push_finished_at TIMESTAMPTZ
);
CREATE INDEX notification_campaigns_created_idx ON notification_campaigns (created_at DESC);

-- In-app messages, fanned out one row per recipient so each has its own read state.
CREATE TABLE inbox_messages (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID        NOT NULL REFERENCES notification_campaigns(id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES users(id),
    read_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (campaign_id, user_id)
);
CREATE INDEX inbox_messages_unread_idx ON inbox_messages (user_id, created_at DESC) WHERE read_at IS NULL;
