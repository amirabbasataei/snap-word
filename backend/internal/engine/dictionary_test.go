package engine

import (
	"testing"
	"unicode/utf8"
)

func TestIsValid(t *testing.T) {
	tests := []struct {
		word string
		want bool
	}{
		{"کتاب", true},
		{"باران", true},
		{"سلام", true},
		{"دوست", true},
		{"سیب", true},
		{"خانه", true},
		// not in dictionary
		{"زکسلوپ", false},
		{"ژژژژژژ", false},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.word, func(t *testing.T) {
			if got := IsValid(tt.word); got != tt.want {
				t.Errorf("IsValid(%q) = %v, want %v", tt.word, got, tt.want)
			}
		})
	}
}

func TestDictionaryLoaded(t *testing.T) {
	if len(dictionary) == 0 {
		t.Fatal("dictionary is empty — fa.txt was not embedded correctly")
	}
}

func TestSuggestWordPrefersLongerWords(t *testing.T) {
	// «آ» opens both two-letter words (آب) and longer ones: a hint must be
	// at least three letters while any are left.
	for i := 0; i < 50; i++ {
		w := SuggestWord('آ', nil)
		if utf8.RuneCountInString(w) < 3 {
			t.Fatalf("SuggestWord returned %q while longer words exist", w)
		}
	}
}

func TestSuggestWordFallsBackToTwoLetterWords(t *testing.T) {
	// Exclude every word of three or more letters starting with «ژ»: only the
	// short ones (ژن, ژل) remain, and a hint must still be offered.
	used := map[string]bool{}
	eachWord(func(w string) bool {
		if firstLetter(w) == 'ژ' && utf8.RuneCountInString(w) >= 3 {
			used[w] = true
		}
		return true
	})
	w := SuggestWord('ژ', used)
	if w != "ژن" && w != "ژل" {
		t.Fatalf("SuggestWord = %q, want a two-letter fallback", w)
	}
	used["ژن"], used["ژل"] = true, true
	if w := SuggestWord('ژ', used); w != "" {
		t.Fatalf("SuggestWord = %q, want none", w)
	}
}
