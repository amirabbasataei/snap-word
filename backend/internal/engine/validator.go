package engine

import (
	"errors"
	"strings"
	"unicode"
	"unicode/utf8"
)

var (
	ErrTooShort     = errors.New("too_short")
	ErrWrongLetter  = errors.New("wrong_letter")
	ErrAlreadyUsed  = errors.New("already_used")
	ErrNotInDict    = errors.New("not_in_dictionary")
	ErrInvalidChars = errors.New("invalid_characters")
)

// zwnj is the zero-width non-joiner (U+200C). Some Persian keyboards insert
// it inside compound words (e.g. "می‌روم"). It carries no letter value, so
// it must be stripped before reading off a word's last letter, but it is
// still a legal character to appear *within* a word.
const zwnj = '‌'

// isPersianLetter reports whether r is a Persian letter (including hamza
// forms ء آ أ ؤ ئ and the four Persian-specific letters پ چ ژ گ / ک).
func isPersianLetter(r rune) bool {
	switch {
	case r >= 0x0621 && r <= 0x0624: // ء آ أ ؤ
		return true
	case r >= 0x0626 && r <= 0x0628: // ئ ا ب
		return true
	case r >= 0x062A && r <= 0x063A: // ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ
		return true
	case r >= 0x0641 && r <= 0x0642: // ف ق
		return true
	case r >= 0x0644 && r <= 0x0648: // ل م ن ه و
		return true
	case r == 0x067E, r == 0x0686, r == 0x0698, r == 0x06A9, r == 0x06AF, r == 0x06CC: // پ چ ژ ک گ ی
		return true
	default:
		return false
	}
}

// lastLetter returns the last meaningful letter of word as a rune, stripping
// any ZWNJ first so it is never mistaken for a letter. Returns 0 for an
// empty (post-strip) word.
func lastLetter(word string) rune {
	cleaned := strings.ReplaceAll(strings.TrimRightFunc(word, unicode.IsSpace), string(zwnj), "")
	if cleaned == "" {
		return 0
	}
	r, _ := utf8.DecodeLastRuneInString(cleaned)
	return r
}

// firstLetter returns the first rune of word, or 0 if word is empty.
func firstLetter(word string) rune {
	r, _ := utf8.DecodeRuneInString(word)
	return r
}

// ValidateMove checks newWord against all six word-validation rules from the game spec.
// prevWord is the last accepted word in the chain ("" for the first move).
// usedWords contains all previously accepted words in the chain.
func ValidateMove(prevWord, newWord string, usedWords map[string]bool) error {
	// Rule 1: normalize
	newWord = strings.TrimSpace(newWord)

	// Rule 2: Persian letters (+ ZWNJ) only — reject digits, spaces, hyphens, etc.
	for _, r := range newWord {
		if !isPersianLetter(r) && r != zwnj {
			return ErrInvalidChars
		}
	}

	// Rule 3: minimum length (in runes, not bytes — Persian letters are multi-byte)
	if utf8.RuneCountInString(newWord) < 3 {
		return ErrTooShort
	}

	// Rule 4: starting letter (skipped for the very first word)
	if prevWord != "" {
		if firstLetter(newWord) != lastLetter(prevWord) {
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
