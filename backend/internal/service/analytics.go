package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"regexp"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

var (
	ErrAnalyticsInvalid     = errors.New("invalid analytics batch")
	ErrAnalyticsRateLimited = errors.New("analytics rate limited")
)

// AnalyticsEventNames is the fixed event vocabulary. It mirrors the Dart enum
// (client/lib/core/services/analytics_service.dart); an unknown name is
// dropped server-side, so adding an event needs both sides to be updated.
var AnalyticsEventNames = map[string]bool{
	"app_open": true, "session_start": true, "session_end": true, "screen_view": true,
	"signup": true, "login": true, "identify": true,
	"game_start": true, "game_end": true, "continue_used": true, "powerup_used": true,
	"daily_start": true, "daily_end": true,
	"queue_join": true, "queue_leave": true, "match_found": true,
	"ad_watched": true, "purchase_tap": true, "share": true,
	"friend_request": true, "challenge_sent": true,
}

var (
	platformRe = regexp.MustCompile(`^(android|ios|web|other)$`)
	versionRe  = regexp.MustCompile(`^[0-9A-Za-z.+_-]{1,32}$`)
	screenRe   = regexp.MustCompile(`^[A-Za-z0-9_/:.-]{1,64}$`)
)

// AnalyticsEventInput is one event as sent by the client.
type AnalyticsEventInput struct {
	ClientEventID string         `json:"client_event_id"`
	Name          string         `json:"name"`
	TS            int64          `json:"ts"` // client time, Unix milliseconds
	SessionID     string         `json:"session_id"`
	Screen        string         `json:"screen"`
	Props         map[string]any `json:"props"`
}

// AnalyticsBatchInput is the request body of POST /analytics/events.
type AnalyticsBatchInput struct {
	InstallID  string                `json:"install_id"`
	Platform   string                `json:"platform"`
	AppVersion string                `json:"app_version"`
	Events     []AnalyticsEventInput `json:"events"`
}

// AnalyticsIngestResult says how many events were stored and how many were
// dropped as malformed or unknown. Duplicates (retries) count as neither.
type AnalyticsIngestResult struct {
	Accepted int `json:"accepted"`
	Rejected int `json:"rejected"`
}

type analyticsStore interface {
	InsertAnalyticsEvents(ctx context.Context, b repository.AnalyticsBatch) (int, error)
}

// AnalyticsService validates and stores product-analytics events.
type AnalyticsService struct {
	store analyticsStore
	rdb   *redis.Client
	now   func() time.Time
}

func NewAnalyticsService(store analyticsStore, rdb *redis.Client) *AnalyticsService {
	return &AnalyticsService{store: store, rdb: rdb, now: time.Now}
}

// AllowRequest enforces the per-install and per-IP request rate. It fails open
// when Redis is unreachable: losing a few events beats rejecting every client.
func (s *AnalyticsService) AllowRequest(ctx context.Context, installID, ip string) error {
	if s.rdb == nil {
		return nil
	}
	minute := s.now().Unix() / 60
	for _, l := range []struct {
		key   string
		limit int64
	}{
		{fmt.Sprintf("analytics:rl:i:%s:%d", installID, minute), config.AnalyticsRatePerInstallPerMin},
		{fmt.Sprintf("analytics:rl:ip:%s:%d", ip, minute), config.AnalyticsRatePerIPPerMin},
	} {
		n, err := s.rdb.Incr(ctx, l.key).Result()
		if err != nil {
			slog.Warn("analytics: rate limit check failed", "error", err)
			return nil
		}
		if n == 1 {
			s.rdb.Expire(ctx, l.key, 2*time.Minute)
		}
		if n > l.limit {
			return ErrAnalyticsRateLimited
		}
	}
	return nil
}

// Ingest validates a batch and stores the valid events. userID is the account
// from the caller's JWT ("" for a guest) — never taken from the body. The
// batch itself is rejected (ErrAnalyticsInvalid) only when its envelope is
// wrong; bad individual events are counted in Rejected so one unknown name
// from a newer client cannot make a whole queue retry forever.
func (s *AnalyticsService) Ingest(ctx context.Context, userID string, in AnalyticsBatchInput) (*AnalyticsIngestResult, error) {
	if !uuidRe.MatchString(in.InstallID) || len(in.Events) == 0 || len(in.Events) > config.AnalyticsMaxBatch {
		return nil, ErrAnalyticsInvalid
	}
	if in.Platform != "" && !platformRe.MatchString(in.Platform) {
		in.Platform = "other"
	}
	if in.AppVersion != "" && !versionRe.MatchString(in.AppVersion) {
		in.AppVersion = ""
	}

	now := s.now()
	batch := repository.AnalyticsBatch{InstallID: in.InstallID, UserID: userID, Platform: in.Platform, AppVersion: in.AppVersion}
	rejected := 0
	for _, e := range in.Events {
		ev, ok := s.validateEvent(e, now)
		if !ok {
			rejected++
			continue
		}
		batch.Events = append(batch.Events, ev)
	}

	inserted, err := s.store.InsertAnalyticsEvents(ctx, batch)
	if err != nil {
		return nil, fmt.Errorf("Ingest: %w", err)
	}
	// Duplicates are neither accepted nor rejected: the client already got
	// them through once and only needs a 2xx to drop its copy.
	return &AnalyticsIngestResult{Accepted: inserted, Rejected: rejected}, nil
}

func (s *AnalyticsService) validateEvent(e AnalyticsEventInput, now time.Time) (repository.AnalyticsEvent, bool) {
	if !AnalyticsEventNames[e.Name] || !uuidRe.MatchString(e.ClientEventID) {
		return repository.AnalyticsEvent{}, false
	}
	if e.SessionID != "" && !uuidRe.MatchString(e.SessionID) {
		e.SessionID = ""
	}
	if e.Screen != "" && !screenRe.MatchString(e.Screen) {
		e.Screen = ""
	}

	// A wrong device clock must not file events in a far-off partition.
	ts := time.UnixMilli(e.TS).UTC()
	if e.TS <= 0 || ts.After(now.Add(config.AnalyticsMaxFutureSkew)) || ts.Before(now.Add(-config.AnalyticsMaxPastSkew)) {
		ts = now.UTC()
	}

	// duration_ms feeds SQL aggregates: keep it a sane non-negative integer or drop it.
	if d, ok := e.Props["duration_ms"]; ok {
		f, isNum := d.(float64)
		if !isNum || f < 0 || f > float64(24*time.Hour/time.Millisecond) {
			delete(e.Props, "duration_ms")
		} else {
			e.Props["duration_ms"] = int64(f)
		}
	}
	var props []byte
	if len(e.Props) > 0 {
		b, err := json.Marshal(e.Props)
		if err != nil || len(b) > config.AnalyticsMaxPropsBytes {
			return repository.AnalyticsEvent{}, false
		}
		props = b
	}
	return repository.AnalyticsEvent{
		ClientEventID: e.ClientEventID, SessionID: e.SessionID,
		Name: e.Name, Screen: e.Screen, Props: props, TS: ts,
	}, true
}

type analyticsMaintStore interface {
	EnsureAnalyticsPartitions(ctx context.Context, now time.Time, ahead int) error
	DropOldAnalyticsPartitions(ctx context.Context, cutoff time.Time) ([]string, error)
	RollupAnalyticsDay(ctx context.Context, day time.Time) error
}

// AnalyticsMaintenanceService is the scheduler-facing half (partitions, rollups,
// retention). It keeps the event table healthy and the rollups fresh.
type AnalyticsMaintenanceService struct {
	store analyticsMaintStore
	rdb   *redis.Client
}

func NewAnalyticsMaintenanceService(store analyticsMaintStore, rdb *redis.Client) *AnalyticsMaintenanceService {
	return &AnalyticsMaintenanceService{store: store, rdb: rdb}
}

// EnsurePartitions creates the partitions ingest needs now and next month.
func (s *AnalyticsMaintenanceService) EnsurePartitions(ctx context.Context, now time.Time) error {
	return s.store.EnsureAnalyticsPartitions(ctx, now, 1)
}

// RefreshRecent rebuilds today's and yesterday's rollups so the panel is near
// live; cheap enough to run every few minutes.
func (s *AnalyticsMaintenanceService) RefreshRecent(ctx context.Context, now time.Time) error {
	today := config.IranDate(now)
	for _, d := range []time.Time{today.AddDate(0, 0, -1), today} {
		if err := s.store.RollupAnalyticsDay(ctx, d); err != nil {
			return fmt.Errorf("RefreshRecent %s: %w", d.Format("2006-01-02"), err)
		}
	}
	return nil
}

// RunDailyPass runs once per Iran day (Redis flag, like the daily payout): it
// rebuilds the lookback window — offline clients upload events up to a week
// late — and drops raw partitions past the retention window.
func (s *AnalyticsMaintenanceService) RunDailyPass(ctx context.Context, now time.Time) error {
	today := config.IranDate(now)
	flag := "analytics:rollup:" + today.Format("2006-01-02")
	if n, err := s.rdb.Exists(ctx, flag).Result(); err != nil || n > 0 {
		return nil
	}
	for i := config.AnalyticsRollupLookbackDays; i >= 1; i-- {
		if err := s.store.RollupAnalyticsDay(ctx, today.AddDate(0, 0, -i)); err != nil {
			return fmt.Errorf("RunDailyPass: %w", err)
		}
	}
	dropped, err := s.store.DropOldAnalyticsPartitions(ctx, now.UTC().AddDate(0, -config.AnalyticsRawRetentionMonths, 0))
	if err != nil {
		return fmt.Errorf("RunDailyPass: %w", err)
	}
	if len(dropped) > 0 {
		slog.Info("analytics: dropped old event partitions", "partitions", dropped)
	}
	if err := s.rdb.Set(ctx, flag, 1, 72*time.Hour).Err(); err != nil {
		slog.Warn("analytics: daily pass flag failed", "error", err)
	}
	return nil
}
