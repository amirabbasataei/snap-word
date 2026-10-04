-- Lifetime XP driving the profile level. Fed by GameService.AddXP at the end of
-- every game (solo, AI, daily, multiplayer); counts from the day this ships.
ALTER TABLE player_stats ADD COLUMN xp BIGINT NOT NULL DEFAULT 0;
