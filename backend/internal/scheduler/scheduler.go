package scheduler

import (
	"context"
	"log/slog"
	"time"

	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

// Scheduler runs background jobs on a 1-minute ticker.
type Scheduler struct {
	leaderboardSvc *service.LeaderboardService
	statsRepo      *repository.StatsRepository
	notifSvc       *service.NotificationService
}

// New creates a Scheduler. Call Start to run it.
func New(
	leaderboardSvc *service.LeaderboardService,
	statsRepo *repository.StatsRepository,
	notifSvc *service.NotificationService,
) *Scheduler {
	return &Scheduler{
		leaderboardSvc: leaderboardSvc,
		statsRepo:      statsRepo,
		notifSvc:       notifSvc,
	}
}

// Start runs the scheduler goroutine until ctx is cancelled.
func (s *Scheduler) Start(ctx context.Context) {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	slog.Info("scheduler: started")
	for {
		select {
		case <-ctx.Done():
			slog.Info("scheduler: stopped")
			return
		case t := <-ticker.C:
			s.tick(ctx, t.UTC())
		}
	}
}

func (s *Scheduler) tick(ctx context.Context, now time.Time) {
	// Weekly reset: Sunday 00:00 UTC
	if now.Weekday() == time.Sunday && now.Hour() == 0 && now.Minute() == 0 {
		weekStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
		s.leaderboardSvc.RunWeeklyReset(ctx, weekStart)
	}

	// Streak at-risk notification: 20:00 UTC daily
	if now.Hour() == 20 && now.Minute() == 0 {
		s.checkStreakAtRisk(ctx, now)
	}
}

func (s *Scheduler) checkStreakAtRisk(ctx context.Context, now time.Time) {
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	userIDs, err := s.statsRepo.GetUsersWithStreakAtRisk(ctx, today)
	if err != nil {
		slog.Error("scheduler: GetUsersWithStreakAtRisk failed", "error", err)
		return
	}
	for _, uid := range userIDs {
		if err := s.notifSvc.SendToUser(ctx, uid,
			"Your streak is at risk!",
			"Play a game before midnight to keep your daily streak alive.",
		); err != nil {
			slog.Warn("scheduler: streak-at-risk notification failed", "userID", uid, "error", err)
		}
	}
	if len(userIDs) > 0 {
		slog.Info("scheduler: streak-at-risk notifications sent", "count", len(userIDs))
	}
}
