package engine

// CalculateScore computes the score for a single word submission using the formula:
//
//	base_score   = len(word) × 10
//	speed_bonus  = max(0, (timeLimitSec - responseTimeSec) × 2)
//	streak_bonus = streak >= 3 ? base_score × 0.5 : 0
//	rarity_bonus = Rank(word) > 10000 ? 20 : 0
//
// streak is the count of consecutive successful submissions before this word.
func CalculateScore(word string, responseTimeSec float64, streak int, timeLimitSec float64) int {
	base := len(word) * 10

	speedBonus := (timeLimitSec - responseTimeSec) * 2
	if speedBonus < 0 {
		speedBonus = 0
	}

	var streakBonus float64
	if streak >= 3 {
		streakBonus = float64(base) * 0.5
	}

	rarityBonus := 0
	if Rank(word) > 10000 {
		rarityBonus = 20
	}

	return base + int(speedBonus) + int(streakBonus) + rarityBonus
}
