-- 001_init.up.sql
-- Full initial schema for WordChain.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username      VARCHAR(32)  UNIQUE NOT NULL,
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT         NOT NULL,
    coins         INTEGER      NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE matches (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    mode       VARCHAR(20) NOT NULL,  -- classic | time_attack | daily
    status     VARCHAR(20) NOT NULL,  -- pending | active | finished | abandoned
    winner_id  UUID        REFERENCES users(id),
    game_state JSONB,
    started_at TIMESTAMPTZ,
    ended_at   TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE match_players (
    match_id      UUID     NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    user_id       UUID     NOT NULL REFERENCES users(id),
    score         INTEGER  NOT NULL DEFAULT 0,
    is_ai         BOOLEAN  NOT NULL DEFAULT false,
    continue_used BOOLEAN  NOT NULL DEFAULT false,
    joined_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (match_id, user_id)
);

CREATE TABLE player_stats (
    user_id              UUID        PRIMARY KEY REFERENCES users(id),
    total_matches        INTEGER     NOT NULL DEFAULT 0,
    wins                 INTEGER     NOT NULL DEFAULT 0,
    longest_word         TEXT,
    best_match_streak    INTEGER     NOT NULL DEFAULT 0,
    daily_streak         INTEGER     NOT NULL DEFAULT 0,
    longest_daily_streak INTEGER     NOT NULL DEFAULT 0,
    last_played_date     DATE,
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE powerup_inventory (
    user_id      UUID        NOT NULL REFERENCES users(id),
    powerup_type VARCHAR(20) NOT NULL,  -- hint | freeze | extra_time | shield
    quantity     INTEGER     NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, powerup_type)
);

CREATE TABLE daily_challenges (
    challenge_date DATE       PRIMARY KEY,
    seed           BIGINT     NOT NULL,
    start_letter   CHAR(1)    NOT NULL
);

CREATE TABLE daily_challenge_attempts (
    user_id        UUID        NOT NULL REFERENCES users(id),
    challenge_date DATE        NOT NULL REFERENCES daily_challenges(challenge_date),
    attempt_number INTEGER     NOT NULL DEFAULT 1,  -- 1 = free, 2 = paid retry
    score          INTEGER     NOT NULL,
    chain_length   INTEGER     NOT NULL,
    word_chain     TEXT[]      NOT NULL DEFAULT '{}',
    completed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, challenge_date, attempt_number)
);

CREATE TABLE friendships (
    requester_id UUID        NOT NULL REFERENCES users(id),
    addressee_id UUID        NOT NULL REFERENCES users(id),
    status       VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending | accepted | declined
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (requester_id, addressee_id)
);

CREATE TABLE friend_challenges (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    challenger_id UUID        NOT NULL REFERENCES users(id),
    challenged_id UUID        NOT NULL REFERENCES users(id),
    mode          VARCHAR(20) NOT NULL,
    match_id      UUID        REFERENCES matches(id),
    status        VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending | accepted | declined | expired
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL  -- created_at + 24h
);

CREATE TABLE device_tokens (
    user_id    UUID        NOT NULL REFERENCES users(id),
    token      TEXT        NOT NULL,
    platform   VARCHAR(10) NOT NULL,  -- ios | android
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, token)
);

CREATE TABLE weekly_leaderboard_rewards (
    week_start    DATE        NOT NULL,
    user_id       UUID        NOT NULL REFERENCES users(id),
    rank          INTEGER     NOT NULL,
    coins_awarded INTEGER     NOT NULL,
    awarded_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (week_start, user_id)
);

-- Indexes for common query patterns
CREATE INDEX idx_matches_status     ON matches(status);
CREATE INDEX idx_matches_created_at ON matches(created_at DESC);
CREATE INDEX idx_match_players_user ON match_players(user_id);
CREATE INDEX idx_friendships_addressee ON friendships(addressee_id, status);
CREATE INDEX idx_friend_challenges_challenged ON friend_challenges(challenged_id, status);
CREATE INDEX idx_friend_challenges_expires ON friend_challenges(expires_at) WHERE status = 'pending';
CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);
CREATE INDEX idx_daily_attempts_date ON daily_challenge_attempts(challenge_date);
