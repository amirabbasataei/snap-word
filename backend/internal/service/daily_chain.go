package service

import (
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
)

// ErrInvalidDailyChain: an uploaded Daily Challenge chain breaks the word
// rules or claims a score the chain cannot have produced.
var ErrInvalidDailyChain = errors.New("invalid_daily_chain")

// maxTurnScore is the highest score one accepted word can earn in the
// Flutter scorer: base + the fullest speed bonus + the streak bonus, times the
// long-word multiplier. The server never sees per-word timings, so this
// bound — not an exact recomputation — is what it can check.
func maxTurnScore(word string) int {
	letters := utf8.RuneCountInString(word)
	base := letters * 10
	score := base + config.TurnTimerClassicSec*2 + base/2
	if letters >= config.LongWordBonusMinLen {
		score *= config.LongWordBonusMult
	}
	return score
}

// ValidateDailyChain checks a Daily Challenge upload the way the client
// played it: the first word starts with the day's start letter, every word
// links to the previous one, none repeats, all pass engine.ValidateMove
// (characters, length, dictionary), the chain stays under the safety cap, and
// the score is not above what these words could earn.
func ValidateDailyChain(startLetter string, chain []string, score int) error {
	if score < 0 {
		return fmt.Errorf("%w: negative score", ErrInvalidDailyChain)
	}
	if len(chain) > config.DailyChainSafetyCap {
		return fmt.Errorf("%w: %d words exceeds the cap", ErrInvalidDailyChain, len(chain))
	}
	if len(chain) == 0 {
		if score != 0 {
			return fmt.Errorf("%w: score without words", ErrInvalidDailyChain)
		}
		return nil
	}
	if !strings.HasPrefix(chain[0], startLetter) {
		return fmt.Errorf("%w: first word does not start with %q", ErrInvalidDailyChain, startLetter)
	}

	used := make(map[string]bool, len(chain))
	prev := ""
	maxScore := 0
	for i, w := range chain {
		if w != strings.TrimSpace(w) {
			return fmt.Errorf("%w: word %d has surrounding whitespace", ErrInvalidDailyChain, i)
		}
		if err := engine.ValidateMove(prev, w, used); err != nil {
			return fmt.Errorf("%w: word %d: %v", ErrInvalidDailyChain, i, err)
		}
		used[w] = true
		prev = w
		maxScore += maxTurnScore(w)
	}
	if score > maxScore {
		return fmt.Errorf("%w: score %d above the maximum %d for this chain", ErrInvalidDailyChain, score, maxScore)
	}
	return nil
}
