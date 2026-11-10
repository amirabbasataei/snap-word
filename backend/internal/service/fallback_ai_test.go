package service_test

import (
	"context"
	"errors"
	"testing"

	"wordchain/backend/internal/service"
)

func TestFallbackAIDifficultyByRating(t *testing.T) {
	cases := []struct {
		rating int
		want   string
	}{
		{0, "easy"}, {850, "easy"}, {999, "easy"},
		{1000, "medium"}, {1199, "medium"},
		{1200, "hard"}, {1850, "hard"},
	}
	for _, c := range cases {
		if got := service.FallbackAIDifficulty(c.rating); got != c.want {
			t.Errorf("rating %d: got %s, want %s", c.rating, got, c.want)
		}
	}
}

type stubRatings struct {
	m   map[string]int
	err error
}

func (s stubRatings) RatingsOf(_ context.Context, ids []string) (map[string]int, error) {
	if s.err != nil {
		return nil, s.err
	}
	return s.m, nil
}

// The queue no longer carries a client difficulty: the level is read from the
// player's rating when the fallback fires.
func TestMatchmakingFallbackLevelFromRating(t *testing.T) {
	ctx := context.Background()
	m := service.NewMatchmakingForTest(stubRatings{m: map[string]int{"low": 900, "mid": 1100, "high": 1300}})
	for id, want := range map[string]string{"low": "easy", "mid": "medium", "high": "hard", "unknown": "medium"} {
		if got := m.FallbackDifficulty(ctx, id); got != want {
			t.Errorf("%s: got %s, want %s", id, got, want)
		}
	}
	// A failed lookup falls back to the starting rating (1000 → medium).
	failing := service.NewMatchmakingForTest(stubRatings{err: errors.New("db down")})
	if got := failing.FallbackDifficulty(ctx, "x"); got != "medium" {
		t.Errorf("lookup error: got %s, want medium", got)
	}
	if got := service.NewMatchmakingForTest(nil).FallbackDifficulty(ctx, "x"); got != "medium" {
		t.Errorf("no lookup: got %s, want medium", got)
	}
}
