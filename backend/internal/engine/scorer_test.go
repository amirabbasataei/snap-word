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
			name: "ZWNJ counts as one rune, matching Flutter's String.length",
			// می‌روم = م ی ZWNJ ر و م = 6 runes → base=60
			word: "می‌روم", responseTimeSec: 15, streak: 0, timeLimitSec: 15,
			want: 60,
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
