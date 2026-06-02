package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

// StreakService updates daily play streaks and awards milestone coins.
type StreakService struct {
	statsRepo *repository.StatsRepository
	userRepo  *repository.UserRepository
	notifSvc  *NotificationService
}

func NewStreakService(
	statsRepo *repository.StatsRepository,
	userRepo *repository.UserRepository,
	notifSvc *NotificationService,
) *StreakService {
	return &StreakService{statsRepo: statsRepo, userRepo: userRepo, notifSvc: notifSvc}
}

// RecordGamePlayed updates the daily streak for a user.
// date is the UTC time the game ended — used instead of time.Now() so that
// offline games synced later are counted against the correct calendar day.
func (s *StreakService) RecordGamePlayed(ctx context.Context, userID string, date time.Time) error {
	today := truncateToDate(date.UTC())

	stats, err := s.statsRepo.GetStats(ctx, userID)
	if err != nil && !errors.Is(err, repository.ErrStatsNotFound) {
		return fmt.Errorf("RecordGamePlayed GetStats: %w", err)
	}
	if errors.Is(err, repository.ErrStatsNotFound) {
		stats = &repository.PlayerStats{UserID: userID}
	}

	newStreak := computeNewStreak(stats, today)
	if newStreak == 0 {
		// Already played today — streak unchanged.
		return nil
	}

	newLongest := stats.LongestDailyStreak
	if newStreak > newLongest {
		newLongest = newStreak
	}

	if err := s.statsRepo.UpdateStreak(ctx, userID, newStreak, newLongest, today); err != nil {
		return fmt.Errorf("RecordGamePlayed UpdateStreak: %w", err)
	}

	s.awardMilestone(ctx, userID, newStreak)
	return nil
}

// computeNewStreak returns the new streak value, or 0 if already played today.
func computeNewStreak(stats *repository.PlayerStats, today time.Time) int {
	if stats.LastPlayedDate == nil {
		return 1 // first game ever
	}
	last := truncateToDate(*stats.LastPlayedDate)
	diff := today.Sub(last)
	switch {
	case diff < 24*time.Hour:
		return 0 // same day — no change
	case diff < 48*time.Hour:
		return stats.DailyStreak + 1 // consecutive day
	default:
		return 1 // missed at least one day
	}
}

func (s *StreakService) awardMilestone(ctx context.Context, userID string, streak int) {
	coins, hit := streakMilestoneCoins(streak)
	if !hit {
		return
	}
	if err := s.userRepo.AwardCoins(ctx, userID, coins); err != nil {
		slog.Error("streak milestone: AwardCoins failed", "userID", userID, "streak", streak, "error", err)
		return
	}
	_ = s.notifSvc.SendToUser(ctx, userID,
		fmt.Sprintf("%d-day streak!", streak),
		fmt.Sprintf("You've earned %d coins.", coins),
	)
	slog.Info("streak milestone awarded", "userID", userID, "streak", streak, "coins", coins)
}

// streakMilestoneCoins returns the coin reward for the given streak count.
// Priority: multiples of 30 → 500 coins; multiples of 7 → 100 coins; multiples of 3 → 30 coins.
func streakMilestoneCoins(streak int) (coins int, hit bool) {
	if streak <= 0 {
		return 0, false
	}
	switch {
	case streak%30 == 0:
		return config.CoinDailyStreak30, true
	case streak%7 == 0:
		return config.CoinDailyStreak7, true
	case streak%3 == 0:
		return config.CoinDailyStreak3, true
	}
	return 0, false
}

// truncateToDate returns midnight UTC of t.
func truncateToDate(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}
