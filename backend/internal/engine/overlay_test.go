package engine

import "testing"

func resetOverlay(t *testing.T) {
	t.Helper()
	overlayPtr.Store(&overlay{})
	t.Cleanup(func() { overlayPtr.Store(&overlay{}) })
}

func TestApplyOverridesAddRemove(t *testing.T) {
	resetOverlay(t)
	const fresh = "کلمهآزمایشی"
	if IsValid(fresh) {
		t.Fatalf("%q should not be in fa.txt", fresh)
	}
	ApplyOverrides([]Override{{Word: fresh, Present: true}})
	if !IsValid(fresh) {
		t.Fatal("added word should be valid")
	}
	if ValidateMove("", fresh, nil) != nil {
		t.Fatal("ValidateMove should accept an overlay word")
	}

	var base string
	for w := range dictionary {
		base = w
		break
	}
	ApplyOverrides([]Override{{Word: base, Present: false}})
	if IsValid(base) {
		t.Fatalf("removed base word %q still valid", base)
	}
	if !InBase(base) {
		t.Fatal("InBase must ignore the overlay")
	}

	// Re-adding wins over the earlier removal.
	ApplyOverrides([]Override{{Word: base, Present: true}})
	if !IsValid(base) {
		t.Fatal("re-added word should be valid again")
	}
}

func TestApplyOverridesLaterEntryWins(t *testing.T) {
	resetOverlay(t)
	ApplyOverrides([]Override{{Word: "تستی", Present: true}, {Word: "تستی", Present: false}})
	if IsValid("تستی") {
		t.Fatal("last entry (removed) should win")
	}
}

func TestAIBlockedWordIsValidButNeverPicked(t *testing.T) {
	resetOverlay(t)
	// Block every word starting with one letter except none: pick a letter, block all.
	const letter = 'ژ' // a rare start, few words
	var blocked []Override
	eachWord(func(w string) bool {
		if firstLetter(w) == letter {
			blocked = append(blocked, Override{Word: w, Present: true, AIBlocked: true})
		}
		return true
	})
	if len(blocked) == 0 {
		t.Fatal("no words start with the test letter")
	}
	ApplyOverrides(blocked)
	for _, b := range blocked {
		if !IsValid(b.Word) {
			t.Fatalf("ai-blocked %q must stay valid for players", b.Word)
		}
	}
	if got := SelectAIWord(letter, nil, 3, 0, false); got != "" {
		t.Fatalf("AI picked blocked word %q", got)
	}
	if SuggestWord(letter, nil) == "" {
		t.Fatal("hints for players may still use ai-blocked words")
	}

	// Un-blocking restores the AI's choice.
	unblock := make([]Override, len(blocked))
	for i, b := range blocked {
		unblock[i] = Override{Word: b.Word, Present: true}
	}
	ApplyOverrides(unblock)
	if SelectAIWord(letter, nil, 3, 0, false) == "" {
		t.Fatal("AI should pick again after unblock")
	}
}

func TestOverlayWordsAreIterated(t *testing.T) {
	resetOverlay(t)
	const w = "ژآزمایشگاهیک"
	ApplyOverrides([]Override{{Word: w, Present: true}})
	got := false
	eachWord(func(x string) bool {
		if x == w {
			got = true
		}
		return true
	})
	if !got {
		t.Fatal("overlay-only word missing from eachWord")
	}
}

func TestKnownRejected(t *testing.T) {
	if len(rejected) < 3000 {
		t.Fatalf("rejected list looks truncated: %d", len(rejected))
	}
	if !IsKnownRejected("آبجویی") {
		t.Fatal("first rejected word not found")
	}
}
