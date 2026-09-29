-- Records a paid daily-challenge retry so the server can authorise attempt #2.
CREATE TABLE daily_retries (
    user_id UUID NOT NULL REFERENCES users(id),
    challenge_date DATE NOT NULL REFERENCES daily_challenges(challenge_date),
    purchased_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, challenge_date)
);
