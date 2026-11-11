package service

import (
	"bufio"
	"errors"
	"os"
	"sort"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
)

// buildChainAt walks the real dictionary for n words linked on letter
// position pos (the next word's pos-th letter = the previous word's last
// letter), the first word carrying start at pos. Words are taken in sorted
// order so the chain is stable.
func buildChainAt(t *testing.T, start string, pos, n int) []string {
	t.Helper()
	f, err := os.Open("../engine/data/fa.txt")
	if err != nil {
		t.Fatalf("open dictionary: %v", err)
	}
	defer f.Close()
	var words []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if w := sc.Text(); engine.LetterCount(w) >= 3 {
			words = append(words, w)
		}
	}
	sort.Strings(words)

	used := map[string]bool{}
	letter := []rune(start)[0]
	chain := make([]string, 0, n)
	for len(chain) < n {
		next := ""
		for _, w := range words {
			if !used[w] && engine.LetterAt(w, pos) == letter {
				next = w
				break
			}
		}
		if next == "" {
			t.Fatalf("dictionary ran out after %d words at position %d", len(chain), pos)
		}
		used[next] = true
		chain = append(chain, next)
		letter = engine.LastLetter(next)
	}
	return chain
}

func chainMaxAt(chain []string, variant int) int {
	total := 0
	for _, w := range chain {
		total += maxTurnScore(w, config.DailyTurnTimerSec(variant))
	}
	return total
}

func TestValidateDailyChainVariants(t *testing.T) {
	for _, variant := range []int{2, 3} {
		chain := buildChainAt(t, "ن", variant, 25)

		if err := ValidateDailyChain("ن", variant, chain, chainMaxAt(chain, variant)); err != nil {
			t.Fatalf("variant %d: a valid chain was rejected: %v", variant, err)
		}
		// The same chain is not a classic chain (and not the other variant's).
		other := 5 - variant
		if err := ValidateDailyChain("ن", other, chain, 0); !errors.Is(err, ErrInvalidDailyChain) {
			t.Fatalf("variant %d chain accepted as variant %d", variant, other)
		}
		if err := ValidateDailyChain("ن", 1, chain, 0); !errors.Is(err, ErrInvalidDailyChain) {
			t.Fatalf("variant %d chain accepted as classic", variant)
		}
		// The first word must carry the day's letter at the variant's position.
		if err := ValidateDailyChain("م", variant, chain, 0); !errors.Is(err, ErrInvalidDailyChain) {
			t.Fatalf("variant %d: wrong start letter accepted", variant)
		}
		// The longer timer raises the bound, the classic one would not.
		if chainMaxAt(chain, variant) <= chainMaxAt(chain, 1) {
			t.Fatalf("variant %d bound not above the classic bound", variant)
		}
		if err := ValidateDailyChain("ن", variant, chain, chainMaxAt(chain, variant)+1); !errors.Is(err, ErrInvalidDailyChain) {
			t.Fatalf("variant %d: score above the bound accepted", variant)
		}
	}
	if err := ValidateDailyChain("ن", 4, nil, 0); !errors.Is(err, ErrInvalidDailyChain) {
		t.Fatal("unknown variant accepted")
	}
}

func TestValidateDailyScoreVariantTimer(t *testing.T) {
	const variant = 3
	timer := config.DailyTurnTimerSec(variant)
	chain := buildChainAt(t, "ر", variant, 8)

	tr := DailyTrace{TimesMs: make([]int, len(chain)), Streaks: make([]int, len(chain))}
	total, classic := 0, 0
	for i, w := range chain {
		tr.TimesMs[i] = 4000
		tr.Streaks[i] = i
		total += engine.CalculateScore(w, 4, i, float64(timer))
		classic += engine.CalculateScore(w, 4, i, config.TurnTimerClassicSec)
	}
	if err := ValidateDailyScore(variant, chain, total, tr); err != nil {
		t.Fatalf("score with the variant's timer rejected: %v", err)
	}
	if err := ValidateDailyScore(variant, chain, classic, tr); !errors.Is(err, ErrInvalidDailyChain) {
		t.Fatal("score with the classic timer accepted for variant 3")
	}

	// A turn may run up to the variant's timer + Extra Time.
	slow := DailyTrace{TimesMs: append([]int(nil), tr.TimesMs...), Streaks: tr.Streaks}
	slow.TimesMs[0] = (timer + config.ExtraTimeBonusSec) * 1000
	slowTotal := total - engine.CalculateScore(chain[0], 4, 0, float64(timer)) +
		engine.CalculateScore(chain[0], float64(slow.TimesMs[0])/1000, 0, float64(timer))
	if err := ValidateDailyScore(variant, chain, slowTotal, slow); err != nil {
		t.Fatalf("a turn within the variant's longer timer rejected: %v", err)
	}
	if err := ValidateDailyScore(1, chain, slowTotal, slow); !errors.Is(err, ErrInvalidDailyChain) {
		t.Fatal("a 33 s turn accepted for the classic variant")
	}
}

func TestValidateDailyScoreNoLegacyForVariants(t *testing.T) {
	const variant = 2
	chain := buildChainAt(t, "ر", variant, 10)
	tr := DailyTrace{TimesMs: make([]int, len(chain)), Streaks: make([]int, len(chain))}
	legacy, hasLong := 0, false
	for i, w := range chain {
		tr.TimesMs[i] = 4000
		tr.Streaks[i] = i
		legacy += legacyTurnScore(w, 4, i, float64(config.DailyTurnTimerSec(variant)))
		hasLong = hasLong || engine.LetterCount(w) >= legacyLongWordMinLen
	}
	if !hasLong {
		t.Skip("chain has no 7+ letter word; legacy and current scores coincide")
	}
	if err := ValidateDailyScore(variant, chain, legacy, tr); !errors.Is(err, ErrInvalidDailyChain) {
		t.Fatal("the pre-S6 ×2 score accepted for a variant old apps cannot play")
	}
}

func TestDailyRewardRef(t *testing.T) {
	d := time.Date(2026, 11, 10, 0, 0, 0, 0, config.IranLocation)
	if got := DailyRewardRef(d, 1); got != "2026-11-10" {
		t.Fatalf("classic ref = %q", got)
	}
	if got := DailyRewardRef(d, 3); got != "2026-11-10/v3" {
		t.Fatalf("variant 3 ref = %q", got)
	}
}

func TestDailyVariantFromRef(t *testing.T) {
	d := time.Date(2026, 11, 10, 0, 0, 0, 0, config.IranLocation)
	for v := 1; v <= config.DailyVariantMax; v++ {
		if got := DailyVariantFromRef(DailyRewardRef(d, v)); got != v {
			t.Errorf("round trip variant %d = %d", v, got)
		}
	}
	for _, ref := range []string{"", "2026-11-10/v9", "2026-11-10/vx", "abc"} {
		if got := DailyVariantFromRef(ref); got != config.DailyVariantClassic {
			t.Errorf("DailyVariantFromRef(%q) = %d, want classic", ref, got)
		}
	}
}
