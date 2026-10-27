package service

import (
	"strings"

	"wordchain/backend/internal/engine"
)

// Warning codes WordWarnings can return; the panel maps them to Persian.
const (
	WarnSuffixOfKnown = "suffix_of_known" // a known word plus plural / comparative / clitic ending
	WarnVerbPrefix    = "verb_prefix"     // می‌… / نمی‌… conjugated form
	WarnEndsInHamza   = "ends_in_hamza"   // the dictionary policy excludes words ending in ء
)

var inflectionSuffixes = []string{"ها", "های", "هایی", "ان", "ات", "تر", "ترین"}

// WordWarnings flags reasons an admin may want to refuse a word under the
// dictionary policy (no inflected forms, conjugations or words ending in ء).
// They are hints only; the decision stays with the reviewer.
func WordWarnings(word string) []string {
	out := []string{}
	const zwnj = "‌"
	plain := strings.ReplaceAll(word, zwnj, "")

	for _, suf := range inflectionSuffixes {
		if strings.HasSuffix(plain, suf) {
			stem := strings.TrimSuffix(plain, suf)
			if len([]rune(stem)) >= 3 && engine.IsValid(stem) {
				out = append(out, WarnSuffixOfKnown)
				break
			}
		}
	}
	if strings.HasPrefix(word, "می"+zwnj) || strings.HasPrefix(word, "نمی"+zwnj) {
		out = append(out, WarnVerbPrefix)
	}
	if strings.HasSuffix(plain, "ء") {
		out = append(out, WarnEndsInHamza)
	}
	return out
}
