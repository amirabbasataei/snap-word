package engine

import (
	"errors"
	"testing"
)

func TestValidateMove(t *testing.T) {
	tests := []struct {
		name      string
		prevWord  string
		newWord   string
		usedWords map[string]bool
		wantErr   error
	}{
		// --- happy path ---
		{
			name:      "first word in chain",
			prevWord:  "",
			newWord:   "کتاب",
			usedWords: map[string]bool{},
			wantErr:   nil,
		},
		{
			name:      "valid continuation",
			prevWord:  "کتاب", // ends با ب
			newWord:   "باران", // starts با ب
			usedWords: map[string]bool{"کتاب": true},
			wantErr:   nil,
		},

		// --- Rule 1: normalize ---
		{
			name:      "leading and trailing whitespace trimmed",
			prevWord:  "",
			newWord:   "  کتاب  ",
			usedWords: map[string]bool{},
			wantErr:   nil,
		},

		// --- Rule 2: invalid characters ---
		{
			name:      "digit in word",
			prevWord:  "",
			newWord:   "کتاب۱",
			usedWords: map[string]bool{},
			wantErr:   ErrInvalidChars,
		},
		{
			name:      "hyphen in word",
			prevWord:  "",
			newWord:   "کتاب-درسی",
			usedWords: map[string]bool{},
			wantErr:   ErrInvalidChars,
		},
		{
			name:      "space inside word",
			prevWord:  "",
			newWord:   "کتاب درسی",
			usedWords: map[string]bool{},
			wantErr:   ErrInvalidChars,
		},
		{
			name:      "latin letters rejected",
			prevWord:  "",
			newWord:   "ketab",
			usedWords: map[string]bool{},
			wantErr:   ErrInvalidChars,
		},
		{
			name:      "arabic-only letters rejected (ي not ی)",
			prevWord:  "",
			newWord:   "يا", // ي + ا — Arabic yeh, not the Persian ی used by the dictionary
			usedWords: map[string]bool{},
			wantErr:   ErrInvalidChars,
		},

		// --- Rule 3: minimum length (counted in runes, not bytes) ---
		{
			name:      "two-letter word rejected",
			prevWord:  "",
			newWord:   "او",
			usedWords: map[string]bool{},
			wantErr:   ErrTooShort,
		},
		{
			name:      "single letter rejected",
			prevWord:  "",
			newWord:   "و",
			usedWords: map[string]bool{},
			wantErr:   ErrTooShort,
		},
		{
			name:      "empty string rejected",
			prevWord:  "",
			newWord:   "",
			usedWords: map[string]bool{},
			wantErr:   ErrTooShort,
		},
		{
			name:      "whitespace-only rejected",
			prevWord:  "",
			newWord:   "   ",
			usedWords: map[string]bool{},
			wantErr:   ErrTooShort,
		},

		// --- Rule 4: starting letter ---
		{
			name:      "wrong starting letter",
			prevWord:  "کتاب",  // ends با ب
			newWord:   "نان",   // starts با ن, not ب
			usedWords: map[string]bool{"کتاب": true},
			wantErr:   ErrWrongLetter,
		},
		{
			name:      "no constraint on first word",
			prevWord:  "",
			newWord:   "نان",
			usedWords: map[string]bool{},
			wantErr:   nil,
		},

		// --- Rule 5: no repetition ---
		{
			name:      "word already used",
			prevWord:  "کتاب",
			newWord:   "باران",
			usedWords: map[string]bool{"کتاب": true, "باران": true},
			wantErr:   ErrAlreadyUsed,
		},

		// --- Rule 6: dictionary ---
		{
			name:      "word not in dictionary",
			prevWord:  "",
			newWord:   "زکسلوپ",
			usedWords: map[string]bool{},
			wantErr:   ErrNotInDict,
		},

		// --- rule ordering ---
		{
			name:     "wrong letter checked before already_used",
			prevWord: "باران", // ends با ن
			// "کتاب" starts با ک but "باران" ends با ن → Rule 4 fires first
			newWord:   "کتاب",
			usedWords: map[string]bool{"کتاب": true, "باران": true},
			wantErr:   ErrWrongLetter,
		},

		// --- ZWNJ handling (ported from last-word's dictionary_service.dart) ---
		{
			name:      "trailing ZWNJ on previous word is stripped before letter comparison",
			prevWord:  "کتاب‌", // "کتاب" with a stray trailing ZWNJ
			newWord:   "باران",      // starts با ب, the real last letter of "کتاب"
			usedWords: map[string]bool{"کتاب‌": true},
			wantErr:   nil,
		},
		{
			name:      "compound word with embedded ZWNJ (می‌روم) still yields correct last letter",
			prevWord:  "می‌روم", // "می‌روم"
			newWord:   "مداد",        // starts با م, the last letter of "روم"
			usedWords: map[string]bool{"می‌روم": true},
			wantErr:   nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateMove(tt.prevWord, tt.newWord, tt.usedWords)
			if !errors.Is(err, tt.wantErr) {
				t.Errorf("ValidateMove(%q, %q, ...) error = %v, want %v",
					tt.prevWord, tt.newWord, err, tt.wantErr)
			}
		})
	}
}

func TestLastLetter_StripsZWNJ(t *testing.T) {
	tests := []struct {
		word string
		want rune
	}{
		{"کتاب", 'ب'},
		{"کتاب‌", 'ب'},     // trailing ZWNJ must not be read as the last letter
		{"می‌روم", 'م'},    // "می‌روم" — embedded ZWNJ, real last letter is م (from روم)
		{"نمی‌دانم", 'م'},  // "نمی‌دانم"
		{"", 0},
		{"‌", 0}, // only a ZWNJ, nothing left after stripping
	}

	for _, tt := range tests {
		t.Run(tt.word, func(t *testing.T) {
			if got := lastLetter(tt.word); got != tt.want {
				t.Errorf("lastLetter(%q) = %q, want %q", tt.word, got, tt.want)
			}
		})
	}
}
