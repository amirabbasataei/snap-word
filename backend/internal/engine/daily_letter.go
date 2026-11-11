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

// dailyLetterMinWordLen keeps the start-letter pool to letters that open
// plenty of full-size words; short words are legal in play (config.MinWordLength)
// but would only widen the pool without making a letter a better opener.
const dailyLetterMinWordLen = 3

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
			if len(runes) < dailyLetterMinWordLen {
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

// DailyStartLetters returns the letters (one per element, sorted) that may open
// a Daily Challenge: those with at least minWordsForDaily dictionary words.
func DailyStartLetters() []string {
	pool := dailyStartLetters()
	out := make([]string, len(pool))
	for i, r := range pool {
		out[i] = string(r)
	}
	return out
}

// IsDailyStartLetter reports whether letter (a single rune) is an eligible
// Daily Challenge start letter.
func IsDailyStartLetter(letter string) bool {
	runes := []rune(letter)
	if len(runes) != 1 {
		return false
	}
	for _, r := range dailyStartLetters() {
		if r == runes[0] {
			return true
		}
	}
	return false
}

var (
	positionPoolOnce sync.Once
	positionCounts   map[int]map[rune]int // link position → letter → words with it there
	positionPools    map[int][]rune       // link position → sorted eligible letters
)

// positionLetterPools counts, for each Daily variant position above 1, how
// many dictionary words (of at least dailyLetterMinWordLen letters) carry each
// letter at that position, once from the embedded dictionary.
func positionLetterPools() (map[int]map[rune]int, map[int][]rune) {
	positionPoolOnce.Do(func() {
		positionCounts = map[int]map[rune]int{}
		positionPools = map[int][]rune{}
		for pos := 2; pos <= config.DailyVariantMax; pos++ {
			counts := map[rune]int{}
			for w := range dictionary {
				if LetterCount(w) < dailyLetterMinWordLen {
					continue
				}
				if r := LetterAt(w, pos); r != 0 {
					counts[r]++
				}
			}
			var pool []rune
			for r, n := range counts {
				if n >= minWordsForDaily {
					pool = append(pool, r)
				}
			}
			sort.Slice(pool, func(i, j int) bool { return pool[i] < pool[j] })
			positionCounts[pos], positionPools[pos] = counts, pool
		}
	})
	return positionCounts, positionPools
}

// DailyVariantStartLetter is the letter the first word of Daily variant pos
// must carry at position pos. It is the day's own letter whenever enough words
// have it there; otherwise (e.g. «آ» is the 2nd letter of a single word) a
// letter drawn deterministically from seed and pos among those that do, so a
// player is never stuck on the first word. Variant 1 is always the day's
// letter.
func DailyVariantStartLetter(dayLetter string, seed int64, pos int) string {
	if pos <= 1 {
		return dayLetter
	}
	counts, pools := positionLetterPools()
	runes := []rune(dayLetter)
	if len(runes) == 1 && counts[pos][runes[0]] >= minWordsForDaily {
		return dayLetter
	}
	pool := pools[pos]
	if len(pool) == 0 {
		return dayLetter
	}
	r := rand.New(rand.NewSource(seed + int64(pos)))
	return string(pool[r.Intn(len(pool))])
}
