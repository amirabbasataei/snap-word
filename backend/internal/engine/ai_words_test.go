package engine

import (
	"testing"
	"unicode/utf8"

	"wordchain/backend/internal/config"
)

// trapLetterWithWords returns a starting letter that has at least one
// trap-ending word of ≥ minLen letters in fa.txt.
func trapLetterWithWords(t *testing.T, minLen int) rune {
	t.Helper()
	for w := range dictionary {
		if utf8.RuneCountInString(w) >= minLen && config.AITrapLetters[LastLetter(w)] {
			return firstLetter(w)
		}
	}
	t.Fatal("fa.txt has no trap-ending words")
	return 0
}

func TestSelectAIWord_ReturnsValidWord(t *testing.T) {
	word := SelectAIWord('س', nil, 3, 0, false)
	if word == "" {
		t.Fatal("expected a word starting with 'س', got empty string")
	}
	if firstLetter(word) != 'س' {
		t.Fatalf("expected word starting with 'س', got %q", word)
	}
	if !IsValid(word) {
		t.Fatalf("returned word %q is not in dictionary", word)
	}
}

// Regression: the previous byte-based version compared a word's first byte
// to the previous word's last byte, which never matches for Persian, so the
// multiplayer AI conceded on every reply.
func TestSelectAIWord_ChainsFromPersianWord(t *testing.T) {
	letter := LastLetter("کتاب") // ب
	word := SelectAIWord(letter, map[string]bool{"کتاب": true}, 3, 0, false)
	if word == "" || firstLetter(word) != 'ب' {
		t.Fatalf("expected a word starting with 'ب', got %q", word)
	}
	if err := ValidateMove("کتاب", word, map[string]bool{"کتاب": true}); err != nil {
		t.Fatalf("AI word %q fails ValidateMove: %v", word, err)
	}
}

func TestSelectAIWord_RespectsMinLengthInLetters(t *testing.T) {
	for _, minLen := range []int{3, 4, 6} {
		word := SelectAIWord('م', nil, minLen, 0, false)
		if word == "" {
			t.Fatalf("minLen=%d: expected a word, got empty string", minLen)
		}
		if n := utf8.RuneCountInString(word); n < minLen {
			t.Fatalf("minLen=%d: word %q has %d letters", minLen, word, n)
		}
	}
}

func TestSelectAIWord_SkipsUsedWords(t *testing.T) {
	used := make(map[string]bool)
	for w := range dictionary {
		if utf8.RuneCountInString(w) >= 3 && firstLetter(w) == 'ژ' {
			used[w] = true
		}
	}
	if word := SelectAIWord('ژ', used, 3, 0, false); word != "" {
		t.Fatalf("expected empty string when all 'ژ' words used, got %q", word)
	}
}

func TestSelectAIWord_TrapPreference(t *testing.T) {
	letter := trapLetterWithWords(t, 3)
	word := SelectAIWord(letter, nil, 3, 1.0, false)
	if !config.AITrapLetters[LastLetter(word)] {
		t.Fatalf("expected trap-ending word with trapPref=1.0, got %q", word)
	}
}

func TestSelectAIWord_PreferLongest(t *testing.T) {
	letter := trapLetterWithWords(t, 3)
	word := SelectAIWord(letter, nil, 3, 1.0, true)

	var trapWords []string
	for w := range dictionary {
		if utf8.RuneCountInString(w) >= 3 && firstLetter(w) == letter && config.AITrapLetters[LastLetter(w)] {
			trapWords = append(trapWords, w)
		}
	}
	if want := longestIn(trapWords); word != want {
		t.Fatalf("preferLongest: expected %q, got %q", want, word)
	}
}

func TestSelectAIWord_NoStartingConstraint(t *testing.T) {
	if word := SelectAIWord(0, nil, 3, 0, false); word == "" {
		t.Fatal("expected a word with no letter constraint, got empty string")
	}
}

func TestAITrapLettersAreRareStarts(t *testing.T) {
	counts := map[rune]int{}
	for w := range dictionary {
		if utf8.RuneCountInString(w) >= 3 {
			counts[firstLetter(w)]++
		}
	}
	for r := range config.AITrapLetters {
		if counts[r] == 0 {
			t.Errorf("trap letter %q starts no words — AI would never be able to use it fairly", r)
		}
		if counts[r] > 100 {
			t.Errorf("trap letter %q starts %d words — not a trap; re-derive from fa.txt", r, counts[r])
		}
	}
}
