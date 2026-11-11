-- Daily Challenge variants: the letter position that links two words
-- (1 = classic first letter, 2 = second letter, 3 = third letter). Each
-- variant is its own daily, so the attempt and retry keys gain the variant.
-- Every existing row is a classic run (variant 1).
ALTER TABLE daily_challenge_attempts
    ADD COLUMN variant SMALLINT NOT NULL DEFAULT 1 CHECK (variant BETWEEN 1 AND 3);
ALTER TABLE daily_challenge_attempts DROP CONSTRAINT daily_challenge_attempts_pkey;
ALTER TABLE daily_challenge_attempts
    ADD PRIMARY KEY (user_id, challenge_date, variant, attempt_number);

DROP INDEX IF EXISTS idx_daily_attempts_date;
CREATE INDEX idx_daily_attempts_date ON daily_challenge_attempts (challenge_date, variant);

ALTER TABLE daily_retries
    ADD COLUMN variant SMALLINT NOT NULL DEFAULT 1 CHECK (variant BETWEEN 1 AND 3);
ALTER TABLE daily_retries DROP CONSTRAINT daily_retries_pkey;
ALTER TABLE daily_retries ADD PRIMARY KEY (user_id, challenge_date, variant);
