package engine

import (
	"testing"
)

func TestSelectAIWord_ReturnsValidWord(t *testing.T) {
	word := SelectAIWord('a', nil, 3, 0, false)
	if word == "" {
		t.Fatal("expected a word starting with 'a', got empty string")
	}
	if word[0] != 'a' {
		t.Fatalf("expected word starting with 'a', got %q", word)
	}
	if len(word) < 3 {
		t.Fatalf("expected len >= 3, got %d for %q", len(word), word)
	}
	if !IsValid(word) {
		t.Fatalf("returned word %q is not in dictionary", word)
	}
}

func TestSelectAIWord_RespectsMinLength(t *testing.T) {
	for _, minLen := range []int{3, 4, 6} {
		word := SelectAIWord('s', nil, minLen, 0, false)
		if word == "" {
			t.Fatalf("minLen=%d: expected a word, got empty string", minLen)
		}
		if len(word) < minLen {
			t.Fatalf("minLen=%d: word %q has length %d", minLen, word, len(word))
		}
	}
}

func TestSelectAIWord_SkipsUsedWords(t *testing.T) {
	// Pre-fill usedWords with every word starting with 'q' that is ≥3 chars.
	used := make(map[string]bool)
	for w := range dictionary {
		if len(w) >= 3 && w[0] == 'q' {
			used[w] = true
		}
	}
	// No eligible word should remain.
	word := SelectAIWord('q', used, 3, 0, false)
	if word != "" {
		t.Fatalf("expected empty string when all 'q' words used, got %q", word)
	}
}

func TestSelectAIWord_TrapPreference(t *testing.T) {
	// With trapPref=1.0 we must always get a trap-ending word (if any exist).
	word := SelectAIWord('s', nil, 3, 1.0, false)
	if word == "" {
		t.Fatal("expected a word with trapPref=1.0, got empty string")
	}
	endByte := word[len(word)-1]
	if !trapLetters[endByte] {
		t.Fatalf("expected trap-ending word with trapPref=1.0, got %q (ends with %c)", word, endByte)
	}
}

func TestSelectAIWord_PreferLongest(t *testing.T) {
	word := SelectAIWord('s', nil, 3, 1.0, true)
	if word == "" {
		t.Fatal("expected a word, got empty string")
	}
	// Verify it ends in a trap letter.
	endByte := word[len(word)-1]
	if !trapLetters[endByte] {
		t.Fatalf("expected trap-ending word, got %q (ends with %c)", word, endByte)
	}
	// Verify it is the longest available trap-ending word starting with 's'.
	var longestTrap string
	for w := range dictionary {
		if len(w) >= 3 && w[0] == 's' && trapLetters[w[len(w)-1]] {
			if len(w) > len(longestTrap) {
				longestTrap = w
			}
		}
	}
	if word != longestTrap {
		t.Fatalf("preferLongest: expected %q, got %q", longestTrap, word)
	}
}

func TestSelectAIWord_NoStartingConstraint(t *testing.T) {
	// letter=0 means no starting-letter constraint (first word of the game).
	word := SelectAIWord(0, nil, 3, 0, false)
	if word == "" {
		t.Fatal("expected a word with no letter constraint, got empty string")
	}
}
