-- Phase 24: player word suggestions (add a missing word / flag an unreal or
-- inappropriate one) and the runtime dictionary overlay they feed.

-- One row per (word, kind); reporters are counted from word_suggestion_reports.
CREATE TABLE word_suggestions (
    id               BIGSERIAL PRIMARY KEY,
    word             TEXT        NOT NULL,
    kind             VARCHAR(8)  NOT NULL CHECK (kind IN ('add', 'remove')),
    status           VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    outcome          VARCHAR(10) NOT NULL DEFAULT '',   -- approved: add | remove | ai_block
    reporters        INTEGER     NOT NULL DEFAULT 0,    -- distinct reporters, kept for sorting
    review_note      TEXT        NOT NULL DEFAULT '',
    reviewed_by      TEXT        NOT NULL DEFAULT '',   -- admin username / "script"
    reviewed_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_reported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (word, kind)
);
CREATE INDEX word_suggestions_queue_idx ON word_suggestions (status, kind, reporters DESC, last_reported_at DESC);

-- reporter_key is "u:<user id>" for a signed-in player and "i:<install id>"
-- for a guest, so a player counts once per word.
CREATE TABLE word_suggestion_reports (
    suggestion_id BIGINT      NOT NULL REFERENCES word_suggestions(id) ON DELETE CASCADE,
    reporter_key  TEXT        NOT NULL,
    user_id       UUID        REFERENCES users(id),
    install_id    UUID,
    reason        VARCHAR(16) NOT NULL DEFAULT '',      -- removal reports: not_a_word | inappropriate
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (suggestion_id, reporter_key)
);
CREATE INDEX word_suggestion_reports_user_idx ON word_suggestion_reports (user_id, created_at DESC) WHERE user_id IS NOT NULL;

-- The dictionary delta on top of fa.txt. One row per changed word holding its
-- desired state; seq increases on every change so clients can ask for
-- "everything since N".
CREATE SEQUENCE dictionary_overrides_seq;
CREATE TABLE dictionary_overrides (
    word       TEXT        PRIMARY KEY,
    present    BOOLEAN     NOT NULL,                    -- false = removed from the dictionary
    ai_blocked BOOLEAN     NOT NULL DEFAULT false,      -- valid for players, never played by the AI
    seq        BIGINT      NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX dictionary_overrides_seq_idx ON dictionary_overrides (seq);
