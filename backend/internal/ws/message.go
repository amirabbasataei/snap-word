package ws

import (
	"errors"
	"strings"
	"unicode"
	"unicode/utf8"

	"wordchain/backend/internal/config"
)

var (
	// ErrEmptyMessage: nothing left of a free-text message after cleaning.
	ErrEmptyMessage = errors.New("empty message")
	// ErrMessageTooLong: more than config.CustomMessageMaxRunes letters.
	ErrMessageTooLong = errors.New("message too long")
)

// CleanCustomMessage normalises a subscriber's free text: control and
// format characters (bidi overrides, zero-width joiners — except the ZWNJ,
// which Persian needs) are dropped, any run of whitespace becomes one space.
func CleanCustomMessage(raw string) (string, error) {
	var b strings.Builder
	space := false
	for _, r := range raw {
		switch {
		case r == '‌': // half-space
			b.WriteRune(r)
			space = false
		case unicode.IsSpace(r):
			space = b.Len() > 0
		case unicode.IsControl(r) || unicode.Is(unicode.Cf, r):
		default:
			if space {
				b.WriteByte(' ')
				space = false
			}
			b.WriteRune(r)
		}
	}
	text := strings.TrimSpace(b.String())
	if text == "" {
		return "", ErrEmptyMessage
	}
	if utf8.RuneCountInString(text) > config.CustomMessageMaxRunes {
		return "", ErrMessageTooLong
	}
	return text, nil
}
