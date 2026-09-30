-- Inbox message for the inviter: one row per referred user, claimed manually.
CREATE TABLE referral_rewards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES users(id),
    referred_id UUID NOT NULL UNIQUE REFERENCES users(id),
    coins INTEGER NOT NULL,
    claimed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX referral_rewards_referrer_idx ON referral_rewards (referrer_id, created_at DESC);

-- Backfill: referrals linked before this feature existed (50 = config.CoinReferralInviter).
INSERT INTO referral_rewards (referrer_id, referred_id, coins, created_at)
SELECT referred_by, id, 50, created_at FROM users WHERE referred_by IS NOT NULL;
