package scheduler

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

// Scheduler runs background jobs on a 1-minute ticker.
type Scheduler struct {
	leaderboardSvc *service.LeaderboardService
	statsRepo      *repository.StatsRepository
	notifSvc       *service.NotificationService
	challengeSvc   *service.ChallengeService
	dailySvc       *service.DailyService
	rdb            *redis.Client
}

// New creates a Scheduler. Call Start to run it.
func New(
	leaderboardSvc *service.LeaderboardService,
	statsRepo *repository.StatsRepository,
	notifSvc *service.NotificationService,
	challengeSvc *service.ChallengeService,
	dailySvc *service.DailyService,
	rdb *redis.Client,
) *Scheduler {
	return &Scheduler{
		leaderboardSvc: leaderboardSvc,
		statsRepo:      statsRepo,
		notifSvc:       notifSvc,
		challengeSvc:   challengeSvc,
		dailySvc:       dailySvc,
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
			s.tick(ctx, t.In(config.IranLocation))
		}
	}
}

func (s *Scheduler) tick(ctx context.Context, now time.Time) {
	// All schedules run on Iran time (UTC+3:30; `now` is already in it).
	// Weekly reset: Saturday 00:00, i.e. the end of Friday — the Iranian week.
	if now.Weekday() == time.Saturday && now.Hour() == 0 && now.Minute() == 0 {
		s.leaderboardSvc.RunWeeklyReset(ctx, config.IranDate(now))
	}

	// Daily challenge reminder: Iran midnight every day
	if now.Hour() == 0 && now.Minute() == 0 {
		s.sendDailyChallengeReminder(ctx, now)
	}

	// Streak at-risk notification: 20:00 Iran time daily (with per-user deduplication)
	if now.Hour() == 20 && now.Minute() == 0 {
		s.checkStreakAtRisk(ctx, now)
	}

	// Expire overdue friend challenges every 5 minutes
	if now.Minute()%5 == 0 {
		s.challengeSvc.ExpireOldChallenges(ctx)
	}

	// Ensure today's and tomorrow's Daily Challenge rows exist, every 5 minutes.
	// Checking (not just running once at midnight) makes this self-healing if the
	// scheduler was down when a day rolled over, and provisioning tomorrow's ahead
	// of time means it's already there when the midnight reminder above fires.
	if now.Minute()%5 == 0 {
		s.ensureDailyChallenges(ctx, now)
		s.payoutYesterday(ctx, now)
	}
}

// payoutYesterday pays the Daily Challenge prizes for the day that just ended
// at Iran midnight. Checked every 5 minutes (not only at 00:00) so it is
// self-healing after downtime; a Redis flag set only on full success stops
// the rescans, and the inbox rows are idempotent regardless.
func (s *Scheduler) payoutYesterday(ctx context.Context, now time.Time) {
	yesterday := config.IranDate(now).AddDate(0, 0, -1)
	key := "payout:daily:" + yesterday.Format("2006-01-02")

	if n, err := s.rdb.Exists(ctx, key).Result(); err != nil || n > 0 {
		return
	}
	if err := s.dailySvc.RunDailyPayout(ctx, yesterday); err != nil {
		slog.Error("scheduler: daily payout failed", "error", err)
		return
	}
	if err := s.rdb.Set(ctx, key, 1, 72*time.Hour).Err(); err != nil {
		slog.Warn("scheduler: daily payout flag failed", "error", err)
	}
}

func (s *Scheduler) ensureDailyChallenges(ctx context.Context, now time.Time) {
	today := config.IranDate(now)
	tomorrow := today.AddDate(0, 0, 1)

	if err := s.dailySvc.EnsureChallenge(ctx, today); err != nil {
		slog.Error("scheduler: ensure today's daily challenge failed", "error", err)
	}
	if err := s.dailySvc.EnsureChallenge(ctx, tomorrow); err != nil {
		slog.Error("scheduler: ensure tomorrow's daily challenge failed", "error", err)
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
		"چالش روزانه زنجیر",
		"چالش امروز آماده است!",
	); err != nil {
		slog.Error("scheduler: daily challenge notification failed", "error", err)
		return
	}
	slog.Info("scheduler: daily challenge notifications sent", "date", dateStr)
}

// checkStreakAtRisk sends a streak-at-risk push to each eligible user.
// Redis key notif:streak_risk:{userID}:{date} (TTL 24h) prevents duplicate sends per user per day.
func (s *Scheduler) checkStreakAtRisk(ctx context.Context, now time.Time) {
	today := config.IranDate(now)
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
			"زنجیرت در خطره!",
			"تا نیمه‌شب یک بازی انجام بده تا رکوردت نپره.",
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
