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
//	long_bonus   = max(0, letters − LongWordBonusFrom) × LongWordBonusPerLetter
//
// Letters are counted with LetterCount (runes, ZWNJ excluded), like the
// Flutter scorer. There is no rarity bonus: no Persian word-frequency list exists.
//
// streak is the count of consecutive successful submissions before this word.
// Every mode scores with this one function: multiplayer (ws.Room) and the
// Daily recompute (service.ValidateDailyScore). It mirrors Flutter's
// GameBloc.calculateScore exactly (same float math, same truncation).
func CalculateScore(word string, responseTimeSec float64, streak int, timeLimitSec float64) int {
	letters := LetterCount(word)
	base := letters * 10

	speedBonus := (timeLimitSec - responseTimeSec) * 2
	if speedBonus < 0 {
		speedBonus = 0
	}

	var streakBonus float64
	if streak >= 3 {
		streakBonus = float64(base) * 0.5
	}

	return base + int(speedBonus) + int(streakBonus) + LongWordBonus(letters)
}

// LongWordBonus is the flat bonus a word of the given letter count earns:
// nothing up to config.LongWordBonusFrom letters, then
// config.LongWordBonusPerLetter for every letter beyond it.
func LongWordBonus(letters int) int {
	if letters <= config.LongWordBonusFrom {
		return 0
	}
	return (letters - config.LongWordBonusFrom) * config.LongWordBonusPerLetter
}
