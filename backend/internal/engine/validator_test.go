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
			newWord:   "apple",
			usedWords: map[string]bool{},
			wantErr:   nil,
		},
		{
			name:      "valid continuation",
			prevWord:  "apple",
			newWord:   "eagle",
			usedWords: map[string]bool{"apple": true},
			wantErr:   nil,
		},

		// --- Rule 1: normalize ---
		{
			name:      "uppercase input normalised",
			prevWord:  "apple",
			newWord:   "EAGLE",
			usedWords: map[string]bool{"apple": true},
			wantErr:   nil,
		},
		{
			name:      "leading and trailing whitespace trimmed",
			prevWord:  "",
			newWord:   "  apple  ",
			usedWords: map[string]bool{},
			wantErr:   nil,
		},

		// --- Rule 2: invalid characters ---
		{
			name:      "digit in word",
			prevWord:  "",
			newWord:   "app1e",
			usedWords: map[string]bool{},
			wantErr:   ErrInvalidChars,
		},
		{
			name:      "hyphen in word",
			prevWord:  "",
			newWord:   "co-op",
			usedWords: map[string]bool{},
			wantErr:   ErrInvalidChars,
		},
		{
			name:      "apostrophe in word",
			prevWord:  "",
			newWord:   "can't",
			usedWords: map[string]bool{},
			wantErr:   ErrInvalidChars,
		},
		{
			name:      "space inside word",
			prevWord:  "",
			newWord:   "two words",
			usedWords: map[string]bool{},
			wantErr:   ErrInvalidChars,
		},

		// --- Rule 3: minimum length ---
		{
			name:      "two-letter word rejected",
			prevWord:  "",
			newWord:   "go",
			usedWords: map[string]bool{},
			wantErr:   ErrTooShort,
		},
		{
			name:      "single letter rejected",
			prevWord:  "",
			newWord:   "a",
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
			prevWord:  "apple",
			newWord:   "banana",
			usedWords: map[string]bool{"apple": true},
			wantErr:   ErrWrongLetter,
		},
		{
			name:      "no constraint on first word",
			prevWord:  "",
			newWord:   "banana",
			usedWords: map[string]bool{},
			wantErr:   nil,
		},

		// --- Rule 5: no repetition ---
		{
			name:      "word already used",
			prevWord:  "apple",
			newWord:   "eagle",
			usedWords: map[string]bool{"apple": true, "eagle": true},
			wantErr:   ErrAlreadyUsed,
		},

		// --- Rule 6: dictionary ---
		{
			name:      "word not in ENABLE",
			prevWord:  "",
			newWord:   "zzzxxx",
			usedWords: map[string]bool{},
			wantErr:   ErrNotInDict,
		},

		// --- rule ordering ---
		{
			name:     "wrong letter checked before already_used",
			prevWord: "eagle",
			// "apple" starts with 'a' but "eagle" ends with 'e' → Rule 4 fires first
			newWord:   "apple",
			usedWords: map[string]bool{"apple": true, "eagle": true},
			wantErr:   ErrWrongLetter,
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
