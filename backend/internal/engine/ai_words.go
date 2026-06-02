package engine

import "math/rand"

// trapLetters are letters that offer few valid follow-ups for the opponent.
var trapLetters = map[byte]bool{
	'q': true, 'x': true, 'z': true, 'j': true, 'v': true,
}

// SelectAIWord picks a valid word for the AI based on difficulty constraints.
//
//   - letter: required starting byte (0 = first word, no constraint)
//   - usedWords: words already played — must be excluded
//   - minLen: minimum word length
//   - trapPref: probability [0,1] of preferring a word ending in a trap letter
//   - preferLongest: when trap preference fires, choose the longest trap word
//
// Returns "" when no eligible word exists.
func SelectAIWord(letter byte, usedWords map[string]bool, minLen int, trapPref float64, preferLongest bool) string {
	var candidates, trapCandidates []string

	for w := range dictionary {
		if len(w) < minLen {
			continue
		}
		if letter != 0 && w[0] != letter {
			continue
		}
		if usedWords[w] {
			continue
		}
		candidates = append(candidates, w)
		if trapLetters[w[len(w)-1]] {
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

func longestIn(words []string) string {
	var best string
	for _, w := range words {
		if len(w) > len(best) {
			best = w
		}
	}
	return best
}
