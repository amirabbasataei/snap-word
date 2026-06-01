package engine

import "testing"

// Common words (rank ≤ 10000) have rarityBonus = 0.
// Rare words (rank > 10000 or absent from freq file) have rarityBonus = 20.
//   cat      → rank 993   → rarity = 0
//   apple    → rank 2520  → rarity = 0
//   elephant → rank 3726  → rarity = 0
//   igloo    → rank 31765 → rarity = 20  (in file but rank > 10000)
//   walrus   → absent     → rarity = 20  (math.MaxInt)
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
			name: "basic — no speed bonus, no streak, common word",
			// base=30, speed=max(0,(15-15)*2)=0, streak=0, rarity=0 → 30
			word: "cat", responseTimeSec: 15, streak: 0, timeLimitSec: 15,
			want: 30,
		},
		{
			name: "speed bonus applied",
			// base=30, speed=(15-5)*2=20, streak=0, rarity=0 → 50
			word: "cat", responseTimeSec: 5, streak: 0, timeLimitSec: 15,
			want: 50,
		},
		{
			name: "streak bonus at threshold (streak=3)",
			// base=30, speed=0, streak=30*0.5=15, rarity=0 → 45
			word: "cat", responseTimeSec: 15, streak: 3, timeLimitSec: 15,
			want: 45,
		},
		{
			name: "streak below threshold not applied (streak=2)",
			// base=30, speed=0, streak=0, rarity=0 → 30
			word: "cat", responseTimeSec: 15, streak: 2, timeLimitSec: 15,
			want: 30,
		},
		{
			name: "all bonuses — common word, no rarity",
			// base=50, speed=(15-3)*2=24, streak=50*0.5=25, rarity=0 → 99
			word: "apple", responseTimeSec: 3, streak: 5, timeLimitSec: 15,
			want: 99,
		},
		{
			name: "response time exceeds limit — speed clamped to zero",
			// base=30, speed=max(0,(15-20)*2)=0, streak=0, rarity=0 → 30
			word: "cat", responseTimeSec: 20, streak: 0, timeLimitSec: 15,
			want: 30,
		},
		{
			name: "longer common word",
			// base=80, speed=(15-0)*2=30, streak=0, rarity=0 → 110
			word: "elephant", responseTimeSec: 0, streak: 0, timeLimitSec: 15,
			want: 110,
		},
		{
			name: "time attack variant (8s limit)",
			// base=30, speed=(8-3)*2=10, streak=0, rarity=0 → 40
			word: "cat", responseTimeSec: 3, streak: 0, timeLimitSec: 8,
			want: 40,
		},
		{
			name: "rarity bonus — word in freq file but rank > 10000",
			// igloo rank=31765 > 10000 → rarity=20
			// base=50, speed=0, streak=0, rarity=20 → 70
			word: "igloo", responseTimeSec: 15, streak: 0, timeLimitSec: 15,
			want: 70,
		},
		{
			name: "rarity bonus — word in freq file with rank > 10000",
			// walrus rank=18300 > 10000 → rarity=20
			// base=60, speed=0, streak=0, rarity=20 → 80
			word: "walrus", responseTimeSec: 15, streak: 0, timeLimitSec: 15,
			want: 80,
		},
		{
			name: "rarity + all bonuses",
			// igloo rank=31765 → rarity=20, base=50, speed=(15-3)*2=24, streak=50*0.5=25
			// 50+24+25+20 = 119
			word: "igloo", responseTimeSec: 3, streak: 5, timeLimitSec: 15,
			want: 119,
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
