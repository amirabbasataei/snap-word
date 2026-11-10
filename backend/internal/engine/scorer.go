package engine

import (
	"strings"
	"unicode/utf8"

	"wordchain/backend/internal/config"
)

// LetterCount is the number of letters in word for scoring: runes, not bytes
// (every Persian letter is 2 bytes in UTF-8), and the half-space (ZWNJ,
// U+200C) is not a letter. Mirrors Flutter's GameBloc.letterCount.
func LetterCount(word string) int {
	return utf8.RuneCountInString(word) - strings.Count(word, string(zwnj))
}

// CalculateScore computes the score for a single word submission using the formula:
//
//	base_score   = letters(word) × 10
//	speed_bonus  = max(0, (timeLimitSec - responseTimeSec) × 2)
//	streak_bonus = streak >= 3 ? base_score × 0.5 : 0
//
// Letters are counted with LetterCount (runes, ZWNJ excluded), like the
// Flutter scorer. There is no rarity bonus: no Persian word-frequency list exists.
//
// streak is the count of consecutive successful submissions before this word.
func CalculateScore(word string, responseTimeSec float64, streak int, timeLimitSec float64) int {
	base := LetterCount(word) * 10

	speedBonus := (timeLimitSec - responseTimeSec) * 2
	if speedBonus < 0 {
		speedBonus = 0
	}

	var streakBonus float64
	if streak >= 3 {
		streakBonus = float64(base) * 0.5
	}

	return base + int(speedBonus) + int(streakBonus)
}

// CalculateSoloScore is the score of one word in the on-device modes (solo,
// vs-AI, Daily Challenge): CalculateScore with the long-word multiplier from
// config.LongWordBonusMinLen letters. It mirrors Flutter's
// GameBloc.calculateScore exactly (same float math, same truncation); the
// server uses it to recompute an uploaded Daily score from the word timings.
// Multiplayer (ws.Room) still uses CalculateScore alone. SCORING_PLAN.md S6
// replaces the multiplier.
func CalculateSoloScore(word string, responseTimeSec float64, streak int, timeLimitSec float64) int {
	score := CalculateScore(word, responseTimeSec, streak, timeLimitSec)
	if LetterCount(word) >= config.LongWordBonusMinLen {
		score *= config.LongWordBonusMult
	}
	return score
}
