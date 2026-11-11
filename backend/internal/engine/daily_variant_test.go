package engine

import (
	"errors"
	"testing"
)

func TestLetterAt(t *testing.T) {
	tests := []struct {
		word string
		pos  int
		want rune
	}{
		{"باران", 1, 'ب'},
		{"باران", 2, 'ا'},
		{"باران", 3, 'ر'},
		{"باران", 5, 'ن'},
		{"باران", 6, 0},
		{"آب", 3, 0},
		{"باران", 0, 0},
		// The half-space is not a letter: «می‌روم» is م ی ر و م.
		{"می‌روم", 3, 'ر'},
		{" باران ", 1, 'ب'},
	}
	for _, tc := range tests {
		if got := LetterAt(tc.word, tc.pos); got != tc.want {
			t.Errorf("LetterAt(%q, %d) = %q, want %q", tc.word, tc.pos, got, tc.want)
		}
	}
}

func TestValidateMoveAt(t *testing.T) {
	tests := []struct {
		name string
		prev string
		word string
		pos  int
		used map[string]bool
		want error
	}{
		// The two examples of the feature request.
		{"2nd letter: باران → انتظار", "باران", "انتظار", 2, nil, nil},
		{"2nd letter: انتظار → ارشاد", "انتظار", "ارشاد", 2, nil, nil},
		{"3rd letter: باران → بانی", "باران", "بانی", 3, nil, nil},
		{"3rd letter: بانی → اعیاد", "بانی", "اعیاد", 3, nil, nil},
		{"first word has no link", "", "ارشاد", 3, nil, nil},
		{"2nd letter is not the link", "باران", "نان", 2, nil, ErrWrongLetter},
		{"word shorter than the position", "کتاب", "آب", 3, nil, ErrWrongLetter},
		{"repeat", "باران", "انتظار", 2, map[string]bool{"انتظار": true}, ErrAlreadyUsed},
		{"not in dictionary", "باران", "انژژژ", 2, nil, ErrNotInDict},
		{"too short beats the link", "باران", "ن", 2, nil, ErrTooShort},
		{"latin letters", "باران", "abc", 2, nil, ErrInvalidChars},
		{"position 1 is the classic rule", "کتاب", "باران", 1, nil, nil},
		{"position 1 rejects a 2nd-letter link", "باران", "انتظار", 1, nil, ErrWrongLetter},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			used := tc.used
			if used == nil {
				used = map[string]bool{}
			}
			if err := ValidateMoveAt(tc.prev, tc.word, used, tc.pos); !errors.Is(err, tc.want) {
				t.Fatalf("ValidateMoveAt(%q, %q, %d) = %v, want %v", tc.prev, tc.word, tc.pos, err, tc.want)
			}
		})
	}
}

func TestDailyVariantStartLetter(t *testing.T) {
	if got := DailyVariantStartLetter("س", 42, 1); got != "س" {
		t.Fatalf("classic keeps the day's letter, got %q", got)
	}
	if got := DailyVariantStartLetter("س", 42, 2); got != "س" {
		t.Fatalf("a letter common at position 2 is kept, got %q", got)
	}
	// «آ» is the second letter of a single dictionary word: the variant gets
	// another letter, the same one every time for the same seed.
	got := DailyVariantStartLetter("آ", 42, 2)
	if got == "آ" || got == "" {
		t.Fatalf("«آ» must be replaced at position 2, got %q", got)
	}
	if again := DailyVariantStartLetter("آ", 42, 2); again != got {
		t.Fatalf("not deterministic: %q then %q", got, again)
	}
	counts, _ := positionLetterPools()
	if n := counts[2][[]rune(got)[0]]; n < minWordsForDaily {
		t.Fatalf("replacement %q has only %d words at position 2", got, n)
	}
	// Every eligible day letter must leave at least minWordsForDaily first
	// words in every variant.
	for _, l := range DailyStartLetters() {
		for pos := 2; pos <= 3; pos++ {
			r := []rune(DailyVariantStartLetter(l, 7, pos))[0]
			if counts[pos][r] < minWordsForDaily {
				t.Errorf("day letter %q, position %d: %q has %d words", l, pos, string(r), counts[pos][r])
			}
		}
	}
}
