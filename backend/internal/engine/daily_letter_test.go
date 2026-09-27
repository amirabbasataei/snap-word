package engine

import "testing"

func TestPickDailyStartLetterDeterministic(t *testing.T) {
	for _, seed := range []int64{0, 1, 20260919, -42} {
		first := PickDailyStartLetter(seed)
		second := PickDailyStartLetter(seed)
		if first != second {
			t.Errorf("seed=%d: got %q then %q, want same letter both times", seed, first, second)
		}
	}
}

func TestPickDailyStartLetterHasEnoughWords(t *testing.T) {
	seed := int64(20260919)
	letter := []rune(PickDailyStartLetter(seed))[0]

	count := 0
	for w := range dictionary {
		runes := []rune(w)
		if len(runes) >= 3 && runes[0] == letter {
			count++
		}
	}
	if count < minWordsForDaily {
		t.Errorf("letter %q has only %d eligible words, want at least %d", string(letter), count, minWordsForDaily)
	}
}

func TestPickDailyStartLetterVariesAcrossSeeds(t *testing.T) {
	seen := make(map[string]bool)
	for seed := int64(0); seed < 50; seed++ {
		seen[PickDailyStartLetter(seed)] = true
	}
	if len(seen) < 2 {
		t.Errorf("got only %d distinct letters across 50 seeds, want more variety", len(seen))
	}
}
