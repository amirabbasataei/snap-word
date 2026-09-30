CREATE TABLE referral_rewards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES users(id),
    referred_id UUID NOT NULL UNIQUE REFERENCES users(id),
    coins INTEGER NOT NULL,
    claimed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO referral_rewards (id, referrer_id, referred_id, coins, claimed_at, created_at)
SELECT id, user_id, ref::uuid, coins, claimed_at, created_at FROM inbox_rewards WHERE kind = 'referral_reward';
DROP TABLE inbox_rewards;
