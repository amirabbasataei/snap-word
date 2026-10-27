package engine

import (
	_ "embed"
	"strings"
	"sync/atomic"
	"unicode/utf8"
)

//go:embed data/fa.txt
var dictionaryTxt string

// dictionary is the immutable base list loaded from fa.txt. Runtime changes
// (admin-approved additions, removals, AI blocks) live in the overlay.
var dictionary map[string]struct{}

// Override is the desired state of one word relative to fa.txt.
type Override struct {
	Word      string
	Present   bool // false = removed from the dictionary
	AIBlocked bool // valid for players, never chosen by the AI
}

// overlay is an immutable snapshot, replaced wholesale by ApplyOverrides so
// readers (every WS move, every AI turn) never lock.
type overlay struct {
	added     map[string]struct{} // present words, whether or not fa.txt has them
	removed   map[string]struct{}
	aiBlocked map[string]struct{}
}

var overlayPtr atomic.Pointer[overlay]

func init() {
	lines := strings.Split(dictionaryTxt, "\n")
	dictionary = make(map[string]struct{}, len(lines))
	for _, line := range lines {
		w := strings.TrimSpace(line)
		if w != "" {
			dictionary[w] = struct{}{}
		}
	}
	overlayPtr.Store(&overlay{})
}

// ApplyOverrides folds changes into the live dictionary. Later entries for the
// same word win. Safe for concurrent use with every reader.
func ApplyOverrides(changes []Override) {
	if len(changes) == 0 {
		return
	}
	old := overlayPtr.Load()
	next := &overlay{
		added:     cloneSet(old.added),
		removed:   cloneSet(old.removed),
		aiBlocked: cloneSet(old.aiBlocked),
	}
	for _, c := range changes {
		if c.Present {
			next.added[c.Word] = struct{}{}
			delete(next.removed, c.Word)
		} else {
			next.removed[c.Word] = struct{}{}
			delete(next.added, c.Word)
		}
		if c.AIBlocked {
			next.aiBlocked[c.Word] = struct{}{}
		} else {
			delete(next.aiBlocked, c.Word)
		}
	}
	overlayPtr.Store(next)
}

func cloneSet(m map[string]struct{}) map[string]struct{} {
	out := make(map[string]struct{}, len(m)+4)
	for k := range m {
		out[k] = struct{}{}
	}
	return out
}

// IsValid reports whether word exists in the Persian dictionary (fa.txt plus
// the admin overlay). Expects a pre-normalised (trimmed) input.
func IsValid(word string) bool {
	o := overlayPtr.Load()
	if _, gone := o.removed[word]; gone {
		return false
	}
	if _, ok := o.added[word]; ok {
		return true
	}
	_, ok := dictionary[word]
	return ok
}

// IsAIBlocked reports whether the AI must never play word.
func IsAIBlocked(word string) bool {
	_, ok := overlayPtr.Load().aiBlocked[word]
	return ok
}

// InBase reports whether fa.txt itself contains word, ignoring the overlay.
func InBase(word string) bool {
	_, ok := dictionary[word]
	return ok
}

// eachWord calls fn for every currently valid word until fn returns false.
func eachWord(fn func(w string) bool) {
	o := overlayPtr.Load()
	for w := range dictionary {
		if _, gone := o.removed[w]; gone {
			continue
		}
		if !fn(w) {
			return
		}
	}
	for w := range o.added {
		if _, dup := dictionary[w]; dup {
			continue
		}
		if !fn(w) {
			return
		}
	}
}

// SuggestWord returns a valid word of at least 3 letters that starts with letter
// and is not present in usedWords. Returns "" if none found.
func SuggestWord(letter rune, usedWords map[string]bool) string {
	found := ""
	eachWord(func(w string) bool {
		if utf8.RuneCountInString(w) >= 3 && firstLetter(w) == letter && !usedWords[w] {
			found = w
			return false
		}
		return true
	})
	return found
}
