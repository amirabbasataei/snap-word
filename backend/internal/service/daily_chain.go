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

// Legacy long-word rule, from before SCORING_PLAN.md S6: a word of 7+
// letters had its whole turn score doubled. Apps installed before S6 shipped
// still score Daily runs this way, so the server accepts a trace that
// matches it (see ValidateDailyScore). It lives here, not in engine/config,
// so nothing new can use it; delete it, with the legacy branch of
// ValidateDailyScore, once old apps are no longer supported.
const (
	legacyLongWordMinLen = 7
	legacyLongWordMult   = 2
)

// legacyTurnScore is the pre-S6 score of one Daily word: today's formula
// without the flat long-word bonus, doubled from 7 letters. (The doubling was
// an integer ×2.0 truncated, which is exact.)
func legacyTurnScore(word string, responseTimeSec float64, streak int, timeLimitSec float64) int {
	letters := engine.LetterCount(word)
	score := engine.CalculateScore(word, responseTimeSec, streak, timeLimitSec) - engine.LongWordBonus(letters)
	if letters >= legacyLongWordMinLen {
		score *= legacyLongWordMult
	}
	return score
}

// maxTurnScore is the highest score one accepted word can earn in the
// Flutter scorer: base + the fullest speed bonus + the streak bonus, then
// either the current flat long-word bonus or the legacy ×2, whichever is
// larger (for a 7+ letter word that is always the ×2). An upload without word
// timings (an app older than SCORING_PLAN.md S5) cannot be recomputed, so
// this bound is all the server can check for it; it therefore accepts runs
// scored by the old formula as well as the new one. Uploads with timings go
// through ValidateDailyScore.
//
// It deliberately still counts the half-space (ZWNJ) as a letter, as the
// scorers did before 2026-11-10: a run uploaded by an older app was scored
// that way, and refusing it would make SyncService drop it for good. Counting
// more letters only loosens an upper bound.
func maxTurnScore(word string) int {
	letters := utf8.RuneCountInString(word)
	base := letters * 10
	score := base + config.TurnTimerClassicSec*2 + base/2
	legacy := score
	if letters >= legacyLongWordMinLen {
		legacy *= legacyLongWordMult
	}
	if current := score + engine.LongWordBonus(letters); current > legacy {
		return current
	}
	return legacy
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

// DailyTrace is the per-word record the app uploads with a Daily run (one
// entry per chain word): how long the player took, and the match streak
// *before* the word. Together with the chain they let the server recompute the
// score instead of trusting it. The server does not see the mistakes that
// reset a streak (a lost life, a shield), so the streaks are uploaded.
type DailyTrace struct {
	TimesMs []int
	Streaks []int
}

// ValidateDailyScore recomputes the score of a Daily chain from its trace with
// the exact formula the app uses (engine.CalculateScore), or the pre-S6 ×2 rule an older app still uses, and rejects a
// mismatch or an implausible trace. It runs after ValidateDailyChain, which
// has already checked the words themselves.
//
// What it can and cannot catch: a score the chain could not have produced is
// refused, and so is a time faster than a human can type; but the timings and
// streaks are still reported by the client, so someone who fakes them all to
// the minimum still gets the highest score the chain allows.
func ValidateDailyScore(chain []string, score int, trace DailyTrace) error {
	n := len(chain)
	if len(trace.TimesMs) != n || len(trace.Streaks) != n {
		return fmt.Errorf("%w: trace has %d times and %d streaks for %d words",
			ErrInvalidDailyChain, len(trace.TimesMs), len(trace.Streaks), n)
	}
	// The longest a turn can run: the timer plus one Extra Time (the app
	// allows one per Daily run; a resumed run gets a fresh allowance).
	maxMs := (config.TurnTimerClassicSec+config.ExtraTimeBonusSec)*1000 + config.DailyWordSlackMs

	total, legacyTotal := 0, 0
	for i, w := range chain {
		ms, streak := trace.TimesMs[i], trace.Streaks[i]
		if ms < config.DailyWordMinMs || ms > maxMs {
			return fmt.Errorf("%w: word %d time %d ms outside %d..%d", ErrInvalidDailyChain, i, ms, config.DailyWordMinMs, maxMs)
		}
		prev := -1
		if i > 0 {
			prev = trace.Streaks[i-1]
		}
		// A streak either continues (+1) or was reset by a mistake (0); the
		// first word has nothing before it.
		if streak < 0 || (streak != 0 && streak != prev+1) {
			return fmt.Errorf("%w: word %d streak %d does not follow %d", ErrInvalidDailyChain, i, streak, prev)
		}
		sec := float64(ms) / 1000.0
		total += engine.CalculateScore(w, sec, streak, config.TurnTimerClassicSec)
		legacyTotal += legacyTurnScore(w, sec, streak, config.TurnTimerClassicSec)
	}
	// An app installed before S6 scored with the ×2 rule. The whole chain
	// must match one formula or the other; a mix is never accepted.
	if total != score && legacyTotal != score {
		return fmt.Errorf("%w: score %d, recomputed %d (legacy rule %d)", ErrInvalidDailyChain, score, total, legacyTotal)
	}
	return nil
}
