-- Drops the harder variants' runs and retries (they cannot fit the old keys).
DELETE FROM daily_retries WHERE variant <> 1;
ALTER TABLE daily_retries DROP CONSTRAINT daily_retries_pkey;
ALTER TABLE daily_retries DROP COLUMN variant;
ALTER TABLE daily_retries ADD PRIMARY KEY (user_id, challenge_date);

DELETE FROM daily_challenge_attempts WHERE variant <> 1;
ALTER TABLE daily_challenge_attempts DROP CONSTRAINT daily_challenge_attempts_pkey;
DROP INDEX IF EXISTS idx_daily_attempts_date;
ALTER TABLE daily_challenge_attempts DROP COLUMN variant;
ALTER TABLE daily_challenge_attempts
    ADD PRIMARY KEY (user_id, challenge_date, attempt_number);
CREATE INDEX idx_daily_attempts_date ON daily_challenge_attempts (challenge_date);
