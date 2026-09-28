package engine

import (
	"math/rand"
	"unicode/utf8"

	"wordchain/backend/internal/config"
)

// SelectAIWord picks a valid word for the AI based on difficulty constraints.
//
//   - letter: required starting letter (0 = first word, no constraint)
//   - usedWords: words already played — must be excluded
//   - minLen: minimum word length, in letters (runes), not bytes
//   - trapPref: probability [0,1] of preferring a word ending in a trap letter
//   - preferLongest: when trap preference fires, choose the longest trap word
//
// Returns "" when no eligible word exists.
func SelectAIWord(letter rune, usedWords map[string]bool, minLen int, trapPref float64, preferLongest bool) string {
	var candidates, trapCandidates []string

	for w := range dictionary {
		if utf8.RuneCountInString(w) < minLen {
			continue
		}
		if letter != 0 && firstLetter(w) != letter {
			continue
		}
		if usedWords[w] {
			continue
		}
		candidates = append(candidates, w)
		if config.AITrapLetters[LastLetter(w)] {
			trapCandidates = append(trapCandidates, w)
		}
	}

	if len(trapCandidates) > 0 && trapPref > 0 && rand.Float64() < trapPref {
		if preferLongest {
			return longestIn(trapCandidates)
		}
		return trapCandidates[rand.Intn(len(trapCandidates))]
	}

	if len(candidates) == 0 {
		return ""
	}
	return candidates[rand.Intn(len(candidates))]
}

// longestIn returns the word with the most letters. Ties go to the
// lexicographically smaller word so the choice is deterministic despite
// Go's randomized map iteration order.
func longestIn(words []string) string {
	var best string
	bestLen := 0
	for _, w := range words {
		n := utf8.RuneCountInString(w)
		if n > bestLen || (n == bestLen && w < best) {
			best, bestLen = w, n
		}
	}
	return best
}
