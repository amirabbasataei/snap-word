-- Phase 25 S2: Elo skill rating («جام») for 1v1 human games.
-- Everyone starts at 1000; no backfill. rated_games counts only games that
-- changed the rating (pair-capped games are not counted, see RatingService).
ALTER TABLE player_stats
    ADD COLUMN rating      INT NOT NULL DEFAULT 1000,
    ADD COLUMN rated_games INT NOT NULL DEFAULT 0,
    ADD COLUMN peak_rating INT NOT NULL DEFAULT 1000;

-- All-time board: ORDER BY rating among players with enough rated games.
CREATE INDEX idx_player_stats_rating ON player_stats (rating DESC) WHERE rated_games > 0;

-- One row per player per rated match. The primary key makes applying a
-- match result twice a no-op.
CREATE TABLE rating_history (
    match_id      UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    user_id       UUID NOT NULL REFERENCES users(id),
    opponent_id   UUID NOT NULL REFERENCES users(id),
    rating_before INT NOT NULL,
    rating_after  INT NOT NULL,
    delta         INT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (match_id, user_id)
);

-- Pair-cap lookup (games vs one opponent today) and the profile history.
CREATE INDEX idx_rating_history_user ON rating_history (user_id, created_at);
