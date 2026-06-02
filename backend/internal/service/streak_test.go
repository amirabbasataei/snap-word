package service

import (
	"testing"
	"time"

	"wordchain/backend/internal/repository"
)

func TestStreakMilestoneCoins(t *testing.T) {
	cases := []struct {
		streak    int
		wantCoins int
		wantHit   bool
	}{
		{1, 0, false},
		{2, 0, false},
		{3, 30, true},
		{4, 0, false},
		{6, 30, true},
		{7, 100, true},
		{14, 100, true},
		{21, 100, true},
		{30, 500, true},
		{60, 500, true},
		{90, 500, true},
		{9, 30, true},  // multiple of 3, not 7 or 30
		{0, 0, false},
		{-1, 0, false},
	}
	for _, tc := range cases {
		coins, hit := streakMilestoneCoins(tc.streak)
		if hit != tc.wantHit || coins != tc.wantCoins {
			t.Errorf("streak=%d: got coins=%d hit=%v, want coins=%d hit=%v",
				tc.streak, coins, hit, tc.wantCoins, tc.wantHit)
		}
	}
}

func TestTruncateToDate(t *testing.T) {
	ts := time.Date(2025, 6, 15, 14, 30, 45, 999, time.UTC)
	got := truncateToDate(ts)
	want := time.Date(2025, 6, 15, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestComputeNewStreak(t *testing.T) {
	base := time.Date(2025, 6, 15, 0, 0, 0, 0, time.UTC)
	yesterday := base.AddDate(0, 0, -1)
	twoDaysAgo := base.AddDate(0, 0, -2)

	cases := []struct {
		name        string
		stats       *repository.PlayerStats
		today       time.Time
		wantStreak  int
	}{
		{
			name:       "first game ever",
			stats:      &repository.PlayerStats{},
			today:      base,
			wantStreak: 1,
		},
		{
			name: "already played today",
			stats: &repository.PlayerStats{
				DailyStreak:    3,
				LastPlayedDate: &base,
			},
			today:      base,
			wantStreak: 0,
		},
		{
			name: "consecutive day",
			stats: &repository.PlayerStats{
				DailyStreak:    5,
				LastPlayedDate: &yesterday,
			},
			today:      base,
			wantStreak: 6,
		},
		{
			name: "missed a day",
			stats: &repository.PlayerStats{
				DailyStreak:    5,
				LastPlayedDate: &twoDaysAgo,
			},
			today:      base,
			wantStreak: 1,
		},
	}

	for _, tc := range cases {
		got := computeNewStreak(tc.stats, tc.today)
		if got != tc.wantStreak {
			t.Errorf("%s: got streak=%d, want %d", tc.name, got, tc.wantStreak)
		}
	}
}
