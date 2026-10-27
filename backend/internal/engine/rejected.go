package engine

import (
	_ "embed"
	"strings"
)

// rejected_words.txt holds the words deliberately kept out of fa.txt during the
// curation reviews (conjugations, colloquial spellings, foreign names, …). A
// player suggesting one of them is told it was already reviewed instead of
// costing an admin another look.
//
//go:embed data/rejected_words.txt
var rejectedTxt string

var rejected map[string]struct{}

func init() {
	lines := strings.Split(rejectedTxt, "\n")
	rejected = make(map[string]struct{}, len(lines))
	for _, line := range lines {
		if w := strings.TrimSpace(line); w != "" {
			rejected[w] = struct{}{}
		}
	}
}

// IsKnownRejected reports whether word was reviewed and turned down during
// dictionary curation.
func IsKnownRejected(word string) bool {
	_, ok := rejected[word]
	return ok
}
