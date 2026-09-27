package engine

import (
	"math/rand"
	"sort"
	"sync"

	"wordchain/backend/internal/config"
)

// minWordsForDaily is the minimum number of length>=3 dictionary words
// starting with a letter for that letter to be eligible as a Daily Challenge
// start letter — avoids stranding players on a near-empty branch of the tree.
const minWordsForDaily = 10

var (
	dailyLetterPoolOnce sync.Once
	dailyLetterPool     []rune
)

// dailyStartLetters returns the sorted set of runes eligible to open a Daily
// Challenge, computed once from the embedded dictionary.
func dailyStartLetters() []rune {
	dailyLetterPoolOnce.Do(func() {
		counts := make(map[rune]int)
		for w := range dictionary {
			runes := []rune(w)
			if len(runes) < config.MinWordLength {
				continue
			}
			counts[runes[0]]++
		}
		for r, n := range counts {
			if n >= minWordsForDaily {
				dailyLetterPool = append(dailyLetterPool, r)
			}
		}
		sort.Slice(dailyLetterPool, func(i, j int) bool { return dailyLetterPool[i] < dailyLetterPool[j] })
	})
	return dailyLetterPool
}

// PickDailyStartLetter deterministically derives a Daily Challenge start
// letter from seed: the same seed always yields the same letter, so a
// challenge can be regenerated (e.g. after a manual fix) without changing it.
func PickDailyStartLetter(seed int64) string {
	pool := dailyStartLetters()
	if len(pool) == 0 {
		return "ا"
	}
	r := rand.New(rand.NewSource(seed))
	return string(pool[r.Intn(len(pool))])
}
