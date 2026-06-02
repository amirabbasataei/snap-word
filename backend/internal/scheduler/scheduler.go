package scheduler

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

// Scheduler runs background jobs on a 1-minute ticker.
type Scheduler struct {
	leaderboardSvc *service.LeaderboardService
	statsRepo      *repository.StatsRepository
	notifSvc       *service.NotificationService
	challengeSvc   *service.ChallengeService
	rdb            *redis.Client
}

// New creates a Scheduler. Call Start to run it.
func New(
	leaderboardSvc *service.LeaderboardService,
	statsRepo *repository.StatsRepository,
	notifSvc *service.NotificationService,
	challengeSvc *service.ChallengeService,
	rdb *redis.Client,
) *Scheduler {
	return &Scheduler{
		leaderboardSvc: leaderboardSvc,
		statsRepo:      statsRepo,
		notifSvc:       notifSvc,
		challengeSvc:   challengeSvc,
		rdb:            rdb,
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

	// Daily challenge reminder: midnight UTC every day
	if now.Hour() == 0 && now.Minute() == 0 {
		s.sendDailyChallengeReminder(ctx, now)
	}

	// Streak at-risk notification: 20:00 UTC daily (with per-user deduplication)
	if now.Hour() == 20 && now.Minute() == 0 {
		s.checkStreakAtRisk(ctx, now)
	}

	// Expire overdue friend challenges every 5 minutes
	if now.Minute()%5 == 0 {
		s.challengeSvc.ExpireOldChallenges(ctx)
	}
}

// sendDailyChallengeReminder broadcasts the daily challenge push to all registered devices.
// A Redis key prevents duplicate sends within a 25-hour window.
func (s *Scheduler) sendDailyChallengeReminder(ctx context.Context, now time.Time) {
	dateStr := now.Format("2006-01-02")
	dedupKey := fmt.Sprintf("notif:daily_challenge:%s", dateStr)

	set, err := s.rdb.SetNX(ctx, dedupKey, 1, 25*time.Hour).Result()
	if err != nil {
		slog.Error("scheduler: daily challenge dedup check failed", "error", err)
		return
	}
	if !set {
		return // Already sent today.
	}

	if err := s.notifSvc.SendToAll(ctx,
		"Daily Word Chain Challenge",
		"Today's Word Chain challenge is ready.",
	); err != nil {
		slog.Error("scheduler: daily challenge notification failed", "error", err)
		return
	}
	slog.Info("scheduler: daily challenge notifications sent", "date", dateStr)
}

// checkStreakAtRisk sends a streak-at-risk push to each eligible user.
// Redis key notif:streak_risk:{userID}:{date} (TTL 24h) prevents duplicate sends per user per day.
func (s *Scheduler) checkStreakAtRisk(ctx context.Context, now time.Time) {
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	dateStr := today.Format("2006-01-02")

	userIDs, err := s.statsRepo.GetUsersWithStreakAtRisk(ctx, today)
	if err != nil {
		slog.Error("scheduler: GetUsersWithStreakAtRisk failed", "error", err)
		return
	}

	sent := 0
	for _, uid := range userIDs {
		dedupKey := fmt.Sprintf("notif:streak_risk:%s:%s", uid, dateStr)
		set, err := s.rdb.SetNX(ctx, dedupKey, 1, 24*time.Hour).Result()
		if err != nil {
			slog.Warn("scheduler: streak-at-risk dedup check failed", "userID", uid, "error", err)
			continue
		}
		if !set {
			continue // Already notified this user today.
		}
		if err := s.notifSvc.SendToUser(ctx, uid,
			"Your streak is at risk!",
			"Play a game before midnight to keep your daily streak alive.",
		); err != nil {
			slog.Warn("scheduler: streak-at-risk notification failed", "userID", uid, "error", err)
		} else {
			sent++
		}
	}

	if sent > 0 {
		slog.Info("scheduler: streak-at-risk notifications sent", "count", sent)
	}
}
