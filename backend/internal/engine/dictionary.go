package engine

import (
	_ "embed"
	"strings"
)

//go:embed data/enable.txt
var enableTxt string

var dictionary map[string]struct{}

func init() {
	lines := strings.Split(enableTxt, "\n")
	dictionary = make(map[string]struct{}, len(lines))
	for _, line := range lines {
		w := strings.TrimSpace(line)
		if w != "" {
			dictionary[w] = struct{}{}
		}
	}
}

// IsValid reports whether word exists in the ENABLE wordlist.
// Expects a pre-normalised (lowercase, trimmed) input.
func IsValid(word string) bool {
	_, ok := dictionary[word]
	return ok
}

// SuggestWord returns a valid word of at least 3 letters that starts with letter
// and is not present in usedWords. Returns "" if none found.
func SuggestWord(letter byte, usedWords map[string]bool) string {
	for w := range dictionary {
		if len(w) >= 3 && w[0] == letter && !usedWords[w] {
			return w
		}
	}
	return ""
}
