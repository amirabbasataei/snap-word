package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/ws"
)

// ErrInvalidDashboardRange is returned for a time-series window outside 1..MaxDashboardDays.
var ErrInvalidDashboardRange = errors.New("invalid dashboard range")

const (
	DefaultDashboardDays = 30
	MaxDashboardDays     = 90
)

type dashboardStore interface {
	DashboardCounts(ctx context.Context, now time.Time) (*repository.DashboardCounts, error)
	DashboardTimeseries(ctx context.Context, from, to time.Time) ([]repository.DashboardDay, error)
}

type hubStats interface {
	Snapshot() ws.HubSnapshot
}

type fcmStatus interface {
	Configured() bool
}

// DashboardSummary is the read-only headline snapshot shown on the panel home.
type DashboardSummary struct {
	GeneratedAt time.Time `json:"generated_at"`
	Users       struct {
		Total      int `json:"total"`
		NewToday   int `json:"new_today"`
		New7d      int `json:"new_7d"`
		PremiumNow int `json:"premium_active"`
	} `json:"users"`
	CoinsInCirculation int64 `json:"coins_in_circulation"`
	MatchesToday       struct {
		Solo   int `json:"solo"`
		Versus int `json:"versus"`
		AI     int `json:"ai_online"`
		Daily  int `json:"daily"`
		Total  int `json:"total"`
	} `json:"matches_today"`
	DailyParticipantsToday int `json:"daily_participants_today"`
	UnclaimedRewards       struct {
		Count int   `json:"count"`
		Coins int64 `json:"coins"`
	} `json:"unclaimed_rewards"`
	Live struct {
		Rooms            int `json:"rooms"`
		WaitingRooms     int `json:"waiting_rooms"`
		ActiveRooms      int `json:"active_rooms"`
		ConnectedPlayers int `json:"connected_players"`
		QueueLength      int `json:"queue_length"`
	} `json:"live"`
	FCMConfigured bool `json:"fcm_configured"`
}

// DashboardDayPoint is one Iran-time day of the time series.
type DashboardDayPoint struct {
	Date          string `json:"date"` // YYYY-MM-DD, Iran calendar day
	Signups       int    `json:"signups"`
	MatchesSolo   int    `json:"matches_solo"`
	MatchesVersus int    `json:"matches_versus"`
	MatchesAI     int    `json:"matches_ai_online"`
	MatchesDaily  int    `json:"matches_daily"`
	DailyAttempts int    `json:"daily_attempts"`
	CoinsClaimed  int64  `json:"coins_claimed"`
}

// AdminDashboardService assembles the dashboard from the database, the
// in-memory hub and the matchmaking queues.
type AdminDashboardService struct {
	store dashboardStore
	hub   hubStats
	rdb   *redis.Client
	fcm   fcmStatus
	now   func() time.Time
}

func NewAdminDashboardService(store dashboardStore, hub hubStats, rdb *redis.Client, fcm fcmStatus) *AdminDashboardService {
	return &AdminDashboardService{store: store, hub: hub, rdb: rdb, fcm: fcm, now: time.Now}
}

// Summary returns the headline numbers. A Redis failure only blanks the queue
// length; the rest is still useful.
func (s *AdminDashboardService) Summary(ctx context.Context) (*DashboardSummary, error) {
	now := s.now()
	c, err := s.store.DashboardCounts(ctx, now)
	if err != nil {
		return nil, fmt.Errorf("Summary: %w", err)
	}

	out := &DashboardSummary{GeneratedAt: now.UTC()}
	out.Users.Total = c.UsersTotal
	out.Users.NewToday = c.UsersNewToday
	out.Users.New7d = c.UsersNew7d
	out.Users.PremiumNow = c.PremiumActive
	out.CoinsInCirculation = c.CoinsInCirculation
	out.MatchesToday.Solo = c.MatchesTodaySolo
	out.MatchesToday.Versus = c.MatchesTodayVersus
	out.MatchesToday.AI = c.MatchesTodayAIOnline
	out.MatchesToday.Daily = c.MatchesTodayDaily
	out.MatchesToday.Total = c.MatchesTodaySolo + c.MatchesTodayVersus + c.MatchesTodayAIOnline + c.MatchesTodayDaily
	out.DailyParticipantsToday = c.DailyParticipantsToday
	out.UnclaimedRewards.Count = c.UnclaimedRewards
	out.UnclaimedRewards.Coins = c.UnclaimedRewardCoins

	snap := s.hub.Snapshot()
	out.Live.Rooms = snap.Rooms
	out.Live.WaitingRooms = snap.WaitingRooms
	out.Live.ActiveRooms = snap.ActiveRooms
	out.Live.ConnectedPlayers = snap.ConnectedPlayers
	for _, mode := range queueModes {
		n, err := s.rdb.LLen(ctx, queueKeyPrefix+mode).Result()
		if err != nil {
			return nil, fmt.Errorf("Summary queue length: %w", err)
		}
		out.Live.QueueLength += int(n)
	}
	out.FCMConfigured = s.fcm.Configured()
	return out, nil
}

// Timeseries returns one point per Iran-time day for the last `days` days,
// ending today. Days with no activity are present with zeros.
func (s *AdminDashboardService) Timeseries(ctx context.Context, days int) ([]DashboardDayPoint, error) {
	if days < 1 || days > MaxDashboardDays {
		return nil, ErrInvalidDashboardRange
	}
	to := config.IranDate(s.now())
	from := to.AddDate(0, 0, -(days - 1))
	rows, err := s.store.DashboardTimeseries(ctx, from, to)
	if err != nil {
		return nil, fmt.Errorf("Timeseries: %w", err)
	}
	out := make([]DashboardDayPoint, len(rows))
	for i, r := range rows {
		out[i] = DashboardDayPoint{
			Date:          r.Day.Format("2006-01-02"),
			Signups:       r.Signups,
			MatchesSolo:   r.MatchesSolo,
			MatchesVersus: r.MatchesVersus,
			MatchesAI:     r.MatchesAI,
			MatchesDaily:  r.MatchesDaily,
			DailyAttempts: r.DailyAttempts,
			CoinsClaimed:  r.CoinsClaimed,
		}
	}
	return out, nil
}
