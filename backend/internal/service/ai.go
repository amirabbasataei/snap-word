package service

import "wordchain/backend/internal/config"

// FallbackAIDifficulty is the AI skill level a player of the given rating is
// paired with when matchmaking falls back to the AI (config.FallbackAILevels).
func FallbackAIDifficulty(rating int) string {
	level := config.FallbackAILevels[0].Difficulty
	for _, l := range config.FallbackAILevels {
		if rating >= l.MinRating {
			level = l.Difficulty
		}
	}
	return level
}
