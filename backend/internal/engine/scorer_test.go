package engine

import "testing"

func TestCalculateScore(t *testing.T) {
	tests := []struct {
		name            string
		word            string
		responseTimeSec float64
		streak          int
		timeLimitSec    float64
		want            int
	}{
		{
			name: "basic — no speed bonus, no streak",
			// سیب = 3 letters (6 bytes) → base=30, speed=0, streak=0 → 30
			word: "سیب", responseTimeSec: 15, streak: 0, timeLimitSec: 15,
			want: 30,
		},
		{
			name: "speed bonus applied",
			// base=30, speed=(15-5)*2=20 → 50
			word: "سیب", responseTimeSec: 5, streak: 0, timeLimitSec: 15,
			want: 50,
		},
		{
			name: "streak bonus at threshold (streak=3)",
			// base=30, streak=30*0.5=15 → 45
			word: "سیب", responseTimeSec: 15, streak: 3, timeLimitSec: 15,
			want: 45,
		},
		{
			name: "streak below threshold not applied (streak=2)",
			word: "سیب", responseTimeSec: 15, streak: 2, timeLimitSec: 15,
			want: 30,
		},
		{
			name: "all bonuses",
			// بازار = 5 letters → base=50, speed=(15-3)*2=24, streak=25 → 99
			word: "بازار", responseTimeSec: 3, streak: 5, timeLimitSec: 15,
			want: 99,
		},
		{
			name: "response time exceeds limit — speed clamped to zero",
			word: "سیب", responseTimeSec: 20, streak: 0, timeLimitSec: 15,
			want: 30,
		},
		{
			name: "short turn limit (8s)",
			// base=30, speed=(8-3)*2=10 → 40
			word: "سیب", responseTimeSec: 3, streak: 0, timeLimitSec: 8,
			want: 40,
		},
		{
			name: "ZWNJ is not a letter (Flutter's letterCount does the same)",
			// می‌روم = م ی ZWNJ ر و م = 5 letters → base=50
			word: "می‌روم", responseTimeSec: 15, streak: 0, timeLimitSec: 15,
			want: 50,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CalculateScore(tt.word, tt.responseTimeSec, tt.streak, tt.timeLimitSec)
			if got != tt.want {
				t.Errorf("CalculateScore(%q, %.1f, %d, %.1f) = %d, want %d",
					tt.word, tt.responseTimeSec, tt.streak, tt.timeLimitSec, got, tt.want)
			}
		})
	}
}

func TestLetterCountSkipsHalfSpace(t *testing.T) {
	cases := map[string]int{
		"سیب":     3,
		"آب‌بازی": 6, // آ ب ‌ ب ا ز ی — the ZWNJ is not a letter
		"می‌روم":  5,
		"":        0,
	}
	for word, want := range cases {
		if got := LetterCount(word); got != want {
			t.Errorf("LetterCount(%q) = %d, want %d", word, got, want)
		}
	}
	// base = 6 letters × 10, not 7 × 10.
	if got := CalculateScore("آب‌بازی", 15, 0, 15); got != 60 {
		t.Errorf("CalculateScore(آب‌بازی) = %d, want 60", got)
	}
}

// scoreVectors are shared with the Flutter test
// (client/test/features/game/score_trace_test.dart): every mode scores with
// CalculateScore, and the server recomputes an uploaded Daily score with it,
// so both sides must produce these exact numbers.
var scoreVectors = []struct {
	name   string
	word   string
	ms     int
	streak int
	want   int
}{
	{"plain", "سلام", 4000, 0, 62},
	{"streak bonus from three", "سلام", 4000, 3, 82},
	{"no streak bonus at two", "سلام", 4000, 2, 62},
	{"slow answer has no speed bonus", "کتاب", 15000, 0, 40},
	{"slower than the limit stays at base", "کتاب", 16000, 0, 40},
	{"fastest answer truncates 29.4", "آب", 300, 5, 59},
	{"seven letters: +15", "دانشگاه", 2500, 4, 145},
	{"nine letters: +45", "دانشجویان", 3000, 0, 159},
	{"ten letters with streak: +60", "کتابخانه‌ها", 4000, 3, 232},
	{"half-space is not a letter", "می‌روم", 1234, 0, 77},
	{"six letters with a half-space get no bonus", "آب‌بازی", 5000, 0, 80},
	{"seven letters counting a half-space: +15", "می‌خواهم", 15000, 0, 85},
}

func TestCalculateScoreVectors(t *testing.T) {
	for _, v := range scoreVectors {
		t.Run(v.name, func(t *testing.T) {
			got := CalculateScore(v.word, float64(v.ms)/1000.0, v.streak, 15)
			if got != v.want {
				t.Fatalf("CalculateScore(%q, %dms, streak %d) = %d, want %d", v.word, v.ms, v.streak, got, v.want)
			}
		})
	}
}

func TestLongWordBonus(t *testing.T) {
	// Smooth, not a cliff: nothing up to 6 letters, then +15 per letter.
	want := map[int]int{0: 0, 3: 0, 6: 0, 7: 15, 8: 30, 9: 45, 12: 90}
	for letters, bonus := range want {
		if got := LongWordBonus(letters); got != bonus {
			t.Errorf("LongWordBonus(%d) = %d, want %d", letters, got, bonus)
		}
	}
}
