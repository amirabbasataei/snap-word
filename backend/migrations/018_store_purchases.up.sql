-- Store purchases (Cafe Bazaar in-app billing).
--
-- One row per purchase token a player redeemed. The unique (store, token) is
-- what makes crediting idempotent: a retried verify call, or a client that
-- re-sends a token it never consumed, can never pay coins twice. A token is
-- bound to the first account that redeems it.
--   kind = coins   consumable pack; `coins` is what was credited once
--   kind = premium subscription; the token stays the same across renewals, so
--                  the row is updated (premium_until only moves forward)
CREATE TABLE store_purchases (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store          VARCHAR(16)  NOT NULL,
    purchase_token TEXT         NOT NULL,
    user_id        UUID         NOT NULL REFERENCES users(id),
    product_id     VARCHAR(32)  NOT NULL,
    kind           VARCHAR(16)  NOT NULL,
    coins          INTEGER      NOT NULL DEFAULT 0,
    premium_until  TIMESTAMPTZ,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (store, purchase_token)
);
CREATE INDEX store_purchases_user_idx ON store_purchases (user_id, created_at DESC);
