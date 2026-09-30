-- Generalises referral_rewards into a claimable prize inbox:
-- kind = referral_reward | streak | weekly_rank | daily_login
CREATE TABLE inbox_rewards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    kind VARCHAR(20) NOT NULL,
    ref TEXT NOT NULL,            -- idempotency key within (user, kind)
    detail TEXT NOT NULL DEFAULT '', -- friend username / streak days / rank
    coins INTEGER NOT NULL,
    claimed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, kind, ref)
);
CREATE INDEX inbox_rewards_user_idx ON inbox_rewards (user_id, created_at DESC);

INSERT INTO inbox_rewards (user_id, kind, ref, detail, coins, claimed_at, created_at)
SELECT rr.referrer_id, 'referral_reward', rr.referred_id::text, COALESCE(u.username, ''),
       rr.coins, rr.claimed_at, rr.created_at
FROM referral_rewards rr JOIN users u ON u.id = rr.referred_id;

DROP TABLE referral_rewards;
