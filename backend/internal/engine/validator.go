package engine

import (
	"errors"
	"strings"
)

var (
	ErrTooShort     = errors.New("too_short")
	ErrWrongLetter  = errors.New("wrong_letter")
	ErrAlreadyUsed  = errors.New("already_used")
	ErrNotInDict    = errors.New("not_in_dictionary")
	ErrInvalidChars = errors.New("invalid_characters")
)

// ValidateMove checks newWord against all six word-validation rules from the game spec.
// prevWord is the last accepted word in the chain ("" for the first move).
// usedWords contains all previously accepted words in the chain.
func ValidateMove(prevWord, newWord string, usedWords map[string]bool) error {
	// Rule 1: normalize
	newWord = strings.ToLower(strings.TrimSpace(newWord))

	// Rule 2: [a-z] only — reject digits, spaces, hyphens, apostrophes, etc.
	for _, r := range newWord {
		if r < 'a' || r > 'z' {
			return ErrInvalidChars
		}
	}

	// Rule 3: minimum length
	if len(newWord) < 3 {
		return ErrTooShort
	}

	// Rule 4: starting letter (skipped for the very first word)
	if prevWord != "" {
		if newWord[0] != prevWord[len(prevWord)-1] {
			return ErrWrongLetter
		}
	}

	// Rule 5: no repetition
	if usedWords[newWord] {
		return ErrAlreadyUsed
	}

	// Rule 6: dictionary check
	if !IsValid(newWord) {
		return ErrNotInDict
	}

	return nil
}
