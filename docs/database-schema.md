# database-schema

> Moved verbatim out of CLAUDE.md on 2026-11-10 to keep that file under the size limit. CLAUDE.md keeps a short summary and links here.

## 🗄️ Database Schema

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(32) UNIQUE,               -- NULL until signup completes (first verify-otp)
    phone VARCHAR(11) UNIQUE NOT NULL,         -- normalized 09XXXXXXXXX (Iran mobile)
    otp_code CHAR(4),
    otp_expires_at TIMESTAMPTZ,
    otp_attempts SMALLINT NOT NULL DEFAULT 0,
    otp_sent_at TIMESTAMPTZ,                   -- last send, for the resend cooldown
    phone_verified_at TIMESTAMPTZ,             -- NULL = signup not yet completed
    referral_code VARCHAR(6) UNIQUE,           -- NULL until signup completes
    referred_by UUID REFERENCES users(id),     -- NULL if no referrer linked
    coins INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mode VARCHAR(20) NOT NULL,        -- classic, daily
    status VARCHAR(20) NOT NULL,      -- pending, active, finished, abandoned
    winner_id UUID REFERENCES users(id),
    game_state JSONB,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE match_players (
    match_id UUID REFERENCES matches(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    score INTEGER DEFAULT 0,
    is_ai BOOLEAN DEFAULT false,
    continue_used BOOLEAN DEFAULT false,
    joined_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (match_id, user_id)
);

CREATE TABLE player_stats (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    total_matches INTEGER DEFAULT 0,
    wins INTEGER DEFAULT 0,
    longest_word TEXT,
    best_match_streak INTEGER DEFAULT 0,
    daily_streak INTEGER DEFAULT 0,
    longest_daily_streak INTEGER DEFAULT 0,
    last_played_date DATE,
    total_score BIGINT NOT NULL DEFAULT 0,      -- 008: lifetime 1v1 word points (profile stat since S2)
    xp BIGINT NOT NULL DEFAULT 0,               -- 009
    rating INT NOT NULL DEFAULT 1000,           -- 019: Elo «جام»
    rated_games INT NOT NULL DEFAULT 0,         -- 019: games that moved the rating
    peak_rating INT NOT NULL DEFAULT 1000,      -- 019
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 019: one row per player per rated 1v1 match; the PK makes a re-apply a no-op.
CREATE TABLE rating_history (
    match_id UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    opponent_id UUID NOT NULL REFERENCES users(id),
    rating_before INT NOT NULL,
    rating_after INT NOT NULL,
    delta INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (match_id, user_id)
);  -- + index (user_id, created_at): pair cap and profile history

CREATE TABLE powerup_inventory (
    user_id UUID REFERENCES users(id),
    powerup_type VARCHAR(20) NOT NULL,
    quantity INTEGER DEFAULT 0,
    PRIMARY KEY (user_id, powerup_type)
);

CREATE TABLE daily_challenges (
    challenge_date DATE PRIMARY KEY,
    seed BIGINT NOT NULL,
    start_letter CHAR(1) NOT NULL
);

CREATE TABLE daily_challenge_attempts (
    user_id UUID REFERENCES users(id),
    challenge_date DATE REFERENCES daily_challenges(challenge_date),
    attempt_number INTEGER NOT NULL DEFAULT 1,  -- 1 = free (the only one ranked and paid a prize), 2 = paid retry (personal best only)
    score INTEGER NOT NULL,
    chain_length INTEGER NOT NULL,
    word_chain TEXT[] NOT NULL DEFAULT '{}',
    completed_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, challenge_date, attempt_number)
);

CREATE TABLE friendships (
    requester_id UUID REFERENCES users(id),
    addressee_id UUID REFERENCES users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending, accepted, declined
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (requester_id, addressee_id)
);

CREATE TABLE friend_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenger_id UUID REFERENCES users(id),
    challenged_id UUID REFERENCES users(id),
    mode VARCHAR(20) NOT NULL,
    match_id UUID REFERENCES matches(id),
    status VARCHAR(20) DEFAULT 'pending',  -- pending, accepted, declined, expired
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL        -- created_at + 24h
);

CREATE TABLE device_tokens (
    user_id UUID REFERENCES users(id),
    token TEXT NOT NULL,
    platform VARCHAR(10) NOT NULL,  -- ios, android
    updated_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, token)
);

CREATE TABLE weekly_leaderboard_rewards (
    week_start DATE NOT NULL,
    user_id UUID REFERENCES users(id),
    rank INTEGER NOT NULL,
    coins_awarded INTEGER NOT NULL,
    awarded_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (week_start, user_id)
);
```

---
