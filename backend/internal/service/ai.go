package service

import "wordchain/backend/internal/config"

// ValidateDifficulty reports whether difficulty is one of the known AI skill levels.
func ValidateDifficulty(difficulty string) bool {
	_, ok := config.AIDifficulties[difficulty]
	return ok
}
