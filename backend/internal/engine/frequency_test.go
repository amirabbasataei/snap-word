package engine

import (
	"math"
	"testing"
)

func TestRank_KnownWords(t *testing.T) {
	tests := []struct {
		word     string
		wantMax  bool // true = expect math.MaxInt (not in file), false = expect a real rank
		wantRank int  // only checked when wantMax == false
	}{
		// Words present in word_freq_ranks.txt with known ranks
		{"you", false, 1},
		{"the", false, 2},
		{"and", false, 3},
		{"cat", false, 993},
		{"apple", false, 2520},
		{"elephant", false, 3726},
		{"igloo", false, 31765}, // in file, rank > 10000
		{"walrus", false, 18300}, // in file, rank > 10000
		// Words absent from word_freq_ranks.txt → math.MaxInt
		{"notawordatall", true, 0},
	}

	for _, tt := range tests {
		t.Run(tt.word, func(t *testing.T) {
			got := Rank(tt.word)
			if tt.wantMax {
				if got != math.MaxInt {
					t.Errorf("Rank(%q) = %d, want math.MaxInt", tt.word, got)
				}
			} else {
				if got != tt.wantRank {
					t.Errorf("Rank(%q) = %d, want %d", tt.word, got, tt.wantRank)
				}
			}
		})
	}
}

func TestFreqRanksMapLoaded(t *testing.T) {
	if freqRanks == nil {
		t.Fatal("freqRanks map is nil — frequency.go init() did not run")
	}
	if len(freqRanks) == 0 {
		t.Fatal("freqRanks map is empty — word_freq_ranks.txt was not parsed")
	}
}
