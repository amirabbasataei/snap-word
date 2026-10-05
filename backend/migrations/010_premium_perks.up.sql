-- Premium subscription state and the chosen premium avatar. premium_until is
-- set server-side only (store billing verification / ops); a NULL or past
-- value means not premium. avatar_id is a key of config.AvatarIDs and is only
-- honoured while premium is active.
ALTER TABLE users ADD COLUMN premium_until TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN avatar_id VARCHAR(24);
