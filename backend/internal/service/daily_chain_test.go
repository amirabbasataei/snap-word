package service

import (
	"errors"
	"strings"
	"testing"
	"unicode/utf8"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
)

// buildChain walks the real dictionary from startLetter for n words.
func buildChain(t *testing.T, startLetter string, n int) []string {
	t.Helper()
	used := map[string]bool{}
	letter, _ := utf8.DecodeRuneInString(startLetter)
	chain := make([]string, 0, n)
	for len(chain) < n {
		w := engine.SuggestWord(letter, used)
		if w == "" {
			t.Fatalf("dictionary ran out after %d words", len(chain))
		}
		used[w] = true
		chain = append(chain, w)
		letter = engine.LastLetter(w)
	}
	return chain
}

// unlinked returns a word from pool that does not start with prev's last letter.
func unlinked(prev string, pool []string) string {
	last := engine.LastLetter(prev)
	for _, w := range pool {
		if r, _ := utf8.DecodeRuneInString(w); r != last {
			return w
		}
	}
	panic("no unlinked word in pool")
}

func chainMax(chain []string) int {
	total := 0
	for _, w := range chain {
		total += maxTurnScore(w)
	}
	return total
}

func TestValidateDailyChain(t *testing.T) {
	const start = "س"
	chain := buildChain(t, start, 30) // well past the old 20-word limit

	t.Run("long chain with a plausible score is accepted", func(t *testing.T) {
		if err := ValidateDailyChain(start, chain, chainMax(chain)); err != nil {
			t.Fatalf("expected ok, got %v", err)
		}
	})
	t.Run("empty chain with zero score is accepted", func(t *testing.T) {
		if err := ValidateDailyChain(start, nil, 0); err != nil {
			t.Fatalf("expected ok, got %v", err)
		}
	})

	bad := map[string]struct {
		chain []string
		score int
	}{
		"score without words":     {nil, 10},
		"negative score":          {chain[:3], -1},
		"score above the maximum": {chain[:3], chainMax(chain[:3]) + 1},
		"wrong first letter":      {chain[1:4], 10},
		"broken link":             {[]string{chain[0], unlinked(chain[0], chain)}, 10},
		"repeated word":           {[]string{chain[0], chain[1], chain[0]}, 10},
		"not in the dictionary":   {[]string{chain[0] + "ققق"}, 10},
		"too short":               {[]string{"س"}, 10},
		"latin characters":        {[]string{"sabz"}, 10},
		"surrounding whitespace":  {[]string{chain[0] + " "}, 10},
		"over the safety cap":     {make([]string, config.DailyChainSafetyCap+1), 10},
	}
	for name, tc := range bad {
		t.Run(name, func(t *testing.T) {
			err := ValidateDailyChain(start, tc.chain, tc.score)
			if !errors.Is(err, ErrInvalidDailyChain) {
				t.Fatalf("expected ErrInvalidDailyChain, got %v", err)
			}
		})
	}
}

func TestMaxTurnScoreLongWordBonus(t *testing.T) {
	short := strings.Repeat("ا", config.LongWordBonusMinLen-1)
	long := strings.Repeat("ا", config.LongWordBonusMinLen)
	if got, want := maxTurnScore(short), 6*10+30+30; got != want {
		t.Errorf("short word max = %d, want %d", got, want)
	}
	if got, want := maxTurnScore(long), (7*10+30+35)*2; got != want {
		t.Errorf("long word max = %d, want %d", got, want)
	}
}

// traceFor builds a plausible trace for chain: 4 s per word, streak counting
// up from 0, and the score the app would have computed from it.
func traceFor(chain []string) (DailyTrace, int) {
	tr := DailyTrace{TimesMs: make([]int, len(chain)), Streaks: make([]int, len(chain))}
	total := 0
	for i, w := range chain {
		tr.TimesMs[i] = 4000
		tr.Streaks[i] = i
		total += engine.CalculateSoloScore(w, 4, i, config.TurnTimerClassicSec)
	}
	return tr, total
}

func TestValidateDailyScore(t *testing.T) {
	chain := buildChain(t, "س", 12)
	tr, score := traceFor(chain)

	t.Run("exact recomputation is accepted", func(t *testing.T) {
		if err := ValidateDailyScore(chain, score, tr); err != nil {
			t.Fatalf("expected ok, got %v", err)
		}
	})
	t.Run("a mistake resets the streak", func(t *testing.T) {
		// Word 5 follows a lost life: its streak is 0 and counting restarts.
		tr2 := DailyTrace{TimesMs: append([]int(nil), tr.TimesMs...), Streaks: append([]int(nil), tr.Streaks...)}
		total := 0
		for i, w := range chain {
			if i >= 5 {
				tr2.Streaks[i] = i - 5
			}
			total += engine.CalculateSoloScore(w, 4, tr2.Streaks[i], config.TurnTimerClassicSec)
		}
		if err := ValidateDailyScore(chain, total, tr2); err != nil {
			t.Fatalf("expected ok, got %v", err)
		}
		if total == score {
			t.Fatal("test is vacuous: the reset changed nothing")
		}
	})
	t.Run("an Extra Time turn is accepted", func(t *testing.T) {
		tr2 := DailyTrace{TimesMs: append([]int(nil), tr.TimesMs...), Streaks: tr.Streaks}
		tr2.TimesMs[2] = 22000
		total := 0
		for i, w := range chain {
			total += engine.CalculateSoloScore(w, float64(tr2.TimesMs[i])/1000, tr2.Streaks[i], config.TurnTimerClassicSec)
		}
		if err := ValidateDailyScore(chain, total, tr2); err != nil {
			t.Fatalf("expected ok, got %v", err)
		}
	})

	mutate := func(f func(tr *DailyTrace)) DailyTrace {
		c := DailyTrace{TimesMs: append([]int(nil), tr.TimesMs...), Streaks: append([]int(nil), tr.Streaks...)}
		f(&c)
		return c
	}
	bad := map[string]struct {
		score int
		trace DailyTrace
	}{
		"score one too high":         {score + 1, tr},
		"score one too low":          {score - 1, tr},
		"fewer times than words":     {score, DailyTrace{TimesMs: tr.TimesMs[:5], Streaks: tr.Streaks}},
		"fewer streaks than words":   {score, DailyTrace{TimesMs: tr.TimesMs, Streaks: tr.Streaks[:5]}},
		"missing times":              {score, DailyTrace{Streaks: tr.Streaks}},
		"time below the human limit": {score, mutate(func(c *DailyTrace) { c.TimesMs[3] = config.DailyWordMinMs - 1 })},
		"negative time":              {score, mutate(func(c *DailyTrace) { c.TimesMs[3] = -5 })},
		"time above the longest turn": {score, mutate(func(c *DailyTrace) {
			c.TimesMs[3] = (config.TurnTimerClassicSec+config.ExtraTimeBonusSec)*1000 + config.DailyWordSlackMs + 1
		})},
		"first word with a streak": {score, mutate(func(c *DailyTrace) { c.Streaks[0] = 1 })},
		"streak skips ahead":       {score, mutate(func(c *DailyTrace) { c.Streaks[4] = 9 })},
		"negative streak":          {score, mutate(func(c *DailyTrace) { c.Streaks[4] = -1 })},
	}
	for name, tc := range bad {
		t.Run(name, func(t *testing.T) {
			err := ValidateDailyScore(chain, tc.score, tc.trace)
			if !errors.Is(err, ErrInvalidDailyChain) {
				t.Fatalf("expected ErrInvalidDailyChain, got %v", err)
			}
		})
	}

	t.Run("fastest honest trace scores below the old maximum", func(t *testing.T) {
		// The exact score never exceeds the lenient bound older apps get.
		fast := DailyTrace{TimesMs: make([]int, len(chain)), Streaks: tr.Streaks}
		total := 0
		for i, w := range chain {
			fast.TimesMs[i] = config.DailyWordMinMs
			total += engine.CalculateSoloScore(w, float64(config.DailyWordMinMs)/1000, fast.Streaks[i], config.TurnTimerClassicSec)
		}
		if total > chainMax(chain) {
			t.Fatalf("exact %d above the bound %d", total, chainMax(chain))
		}
		if err := ValidateDailyScore(chain, total, fast); err != nil {
			t.Fatalf("expected ok, got %v", err)
		}
	})
}
