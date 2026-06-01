package engine

import (
	_ "embed"
	"math"
	"strconv"
	"strings"
)

//go:embed data/word_freq_ranks.txt
var freqTxt string

var freqRanks map[string]int

func init() {
	lines := strings.Split(freqTxt, "\n")
	freqRanks = make(map[string]int, len(lines))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		rank, err := strconv.Atoi(strings.TrimSpace(parts[1]))
		if err != nil {
			continue
		}
		freqRanks[strings.TrimSpace(parts[0])] = rank
	}
}

// Rank returns the frequency rank of word.
// Returns math.MaxInt when the word is absent from word_freq_ranks.txt,
// which ensures it qualifies for the rarity bonus (rank > 10000).
func Rank(word string) int {
	if r, ok := freqRanks[word]; ok {
		return r
	}
	return math.MaxInt
}
