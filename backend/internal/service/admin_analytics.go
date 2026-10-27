package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

// ErrInvalidAnalyticsQuery is returned for a bad window, step list or id.
var ErrInvalidAnalyticsQuery = errors.New("invalid analytics query")

const (
	DefaultAnalyticsDays = 30
	MaxAnalyticsDays     = 90
	MaxFunnelSteps       = 6
	MaxTimelineLimit     = 500
	retentionDays        = 30 // offsets D0..D30
	retentionCacheTTL    = 5 * time.Minute
)

type adminAnalyticsStore interface {
	AnalyticsOverview(ctx context.Context, from, to time.Time) (*repository.AnalyticsOverviewData, error)
	AnalyticsRetention(ctx context.Context, from, to time.Time, byUser bool) ([]repository.RetentionCell, error)
	AnalyticsFunnel(ctx context.Context, steps []string, from, to time.Time) ([]int, error)
	AnalyticsScreens(ctx context.Context, from, to time.Time) ([]repository.ScreenStat, error)
	AnalyticsEventCounts(ctx context.Context, from, to time.Time, names []string) ([]repository.EventCount, error)
	AnalyticsTimeline(ctx context.Context, byUser bool, id string, before time.Time, limit int) ([]repository.TimelineEvent, error)
	AnalyticsInstallsOf(ctx context.Context, byUser bool, id string) ([]repository.AnalyticsInstall, error)
}

// AdminAnalyticsService backs the panel's «تحلیل رفتار» page (read-only).
type AdminAnalyticsService struct {
	store adminAnalyticsStore
	rdb   *redis.Client
	now   func() time.Time
}

func NewAdminAnalyticsService(store adminAnalyticsStore, rdb *redis.Client) *AdminAnalyticsService {
	return &AdminAnalyticsService{store: store, rdb: rdb, now: time.Now}
}

func dayStr(t time.Time) string { return t.Format("2006-01-02") }

// window returns the [from, to] Iran dates covering the last `days` days ending today.
func (s *AdminAnalyticsService) window(days int) (from, to time.Time, err error) {
	if days < 1 || days > MaxAnalyticsDays {
		return time.Time{}, time.Time{}, ErrInvalidAnalyticsQuery
	}
	to = config.IranDate(s.now())
	return to.AddDate(0, 0, -(days - 1)), to, nil
}

type AnalyticsOverviewDay struct {
	Day         string `json:"day"`
	Active      int    `json:"active"`
	ActiveUsers int    `json:"active_users"`
	NewInstalls int    `json:"new_installs"`
	Sessions    int    `json:"sessions"`
}

type AnalyticsOverview struct {
	GeneratedAt      time.Time              `json:"generated_at"`
	DAU              int                    `json:"dau"`
	WAU              int                    `json:"wau"`
	MAU              int                    `json:"mau"`
	Stickiness       float64                `json:"stickiness"` // DAU / MAU
	NewInstallsToday int                    `json:"new_installs_today"`
	NewInstalls7d    int                    `json:"new_installs_7d"`
	AvgSessionMs     int64                  `json:"avg_session_ms"` // last 7 days
	TotalInstalls    int                    `json:"total_installs"`
	LinkedInstalls   int                    `json:"linked_installs"`
	Days             []AnalyticsOverviewDay `json:"days"`
}

func (s *AdminAnalyticsService) Overview(ctx context.Context, days int) (*AnalyticsOverview, error) {
	from, to, err := s.window(days)
	if err != nil {
		return nil, err
	}
	d, err := s.store.AnalyticsOverview(ctx, from, to)
	if err != nil {
		return nil, fmt.Errorf("Overview: %w", err)
	}
	out := &AnalyticsOverview{
		GeneratedAt: s.now().UTC(), WAU: d.WAU, MAU: d.MAU,
		TotalInstalls: d.TotalInstalls, LinkedInstalls: d.LinkedInstall,
		Days: make([]AnalyticsOverviewDay, 0, len(d.Series)),
	}
	var sess7 int
	var ms7 int64
	for i, p := range d.Series {
		out.Days = append(out.Days, AnalyticsOverviewDay{
			Day: dayStr(p.Day), Active: p.Active, ActiveUsers: p.ActiveUsers, NewInstalls: p.NewInstalls, Sessions: p.Sessions,
		})
		if i >= len(d.Series)-7 {
			out.NewInstalls7d += p.NewInstalls
			sess7 += p.Sessions
			ms7 += p.SessionMsSum
		}
		if i == len(d.Series)-1 {
			out.DAU, out.NewInstallsToday = p.Active, p.NewInstalls
		}
	}
	if out.MAU > 0 {
		out.Stickiness = float64(out.DAU) / float64(out.MAU)
	}
	if sess7 > 0 {
		out.AvgSessionMs = ms7 / int64(sess7)
	}
	return out, nil
}

type RetentionCohort struct {
	Cohort   string `json:"cohort"`
	Size     int    `json:"size"`
	Retained []*int `json:"retained"` // index = days after the cohort day; null = not reached yet
}

type RetentionResult struct {
	By      string            `json:"by"`
	Cohorts []RetentionCohort `json:"cohorts"`
}

// Retention builds the cohort matrix. Cohorts are Iran days in [from, to]; by
// is "install" or "user". Cached briefly in Redis — it scans the rollups.
func (s *AdminAnalyticsService) Retention(ctx context.Context, from, to time.Time, by string) (*RetentionResult, error) {
	if (by != "install" && by != "user") || to.Before(from) || to.Sub(from) > MaxAnalyticsDays*24*time.Hour {
		return nil, ErrInvalidAnalyticsQuery
	}
	key := fmt.Sprintf("analytics:retention:%s:%s:%s", by, dayStr(from), dayStr(to))
	if s.rdb != nil {
		if raw, err := s.rdb.Get(ctx, key).Bytes(); err == nil {
			var cached RetentionResult
			if json.Unmarshal(raw, &cached) == nil {
				return &cached, nil
			}
		}
	}

	cells, err := s.store.AnalyticsRetention(ctx, from, to, by == "user")
	if err != nil {
		return nil, fmt.Errorf("Retention: %w", err)
	}
	today := config.IranDate(s.now())
	byCohort := map[string]*RetentionCohort{}
	for _, c := range cells {
		k := dayStr(c.Cohort)
		co := byCohort[k]
		if co == nil {
			reach := int(today.Sub(c.Cohort).Hours() / 24) // largest offset that has happened
			co = &RetentionCohort{Cohort: k, Retained: make([]*int, retentionDays+1)}
			for i := 0; i <= retentionDays && i <= reach; i++ {
				zero := 0
				co.Retained[i] = &zero
			}
			byCohort[k] = co
		}
		if c.Offset < 0 || c.Offset > retentionDays {
			continue
		}
		n := c.Count
		co.Retained[c.Offset] = &n
		if c.Offset == 0 {
			co.Size = c.Count
		}
	}
	res := &RetentionResult{By: by, Cohorts: make([]RetentionCohort, 0, len(byCohort))}
	for _, co := range byCohort {
		res.Cohorts = append(res.Cohorts, *co)
	}
	sort.Slice(res.Cohorts, func(i, j int) bool { return res.Cohorts[i].Cohort < res.Cohorts[j].Cohort })

	if s.rdb != nil {
		if raw, err := json.Marshal(res); err == nil {
			s.rdb.Set(ctx, key, raw, retentionCacheTTL)
		}
	}
	return res, nil
}

type FunnelStep struct {
	Name       string  `json:"name"`
	Count      int     `json:"count"`
	PctOfFirst float64 `json:"pct_of_first"`
	PctOfPrev  float64 `json:"pct_of_prev"`
}

// Funnel counts installs reaching each step in order within the last `days` days.
func (s *AdminAnalyticsService) Funnel(ctx context.Context, steps []string, days int) ([]FunnelStep, error) {
	if len(steps) < 2 || len(steps) > MaxFunnelSteps {
		return nil, ErrInvalidAnalyticsQuery
	}
	for _, n := range steps {
		if !AnalyticsEventNames[n] {
			return nil, ErrInvalidAnalyticsQuery
		}
	}
	from, to, err := s.window(days)
	if err != nil {
		return nil, err
	}
	start := time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, config.IranLocation)
	end := time.Date(to.Year(), to.Month(), to.Day(), 0, 0, 0, 0, config.IranLocation).Add(24 * time.Hour)
	counts, err := s.store.AnalyticsFunnel(ctx, steps, start, end)
	if err != nil {
		return nil, fmt.Errorf("Funnel: %w", err)
	}
	out := make([]FunnelStep, len(steps))
	for i, n := range steps {
		out[i] = FunnelStep{Name: n, Count: counts[i]}
		if counts[0] > 0 {
			out[i].PctOfFirst = float64(counts[i]) / float64(counts[0])
		}
		if i > 0 && counts[i-1] > 0 {
			out[i].PctOfPrev = float64(counts[i]) / float64(counts[i-1])
		}
	}
	return out, nil
}

type ScreenRow struct {
	Screen   string `json:"screen"`
	Views    int    `json:"views"`
	AvgMs    int64  `json:"avg_ms"`
	MedianMs int    `json:"median_ms"` // approximate across days
}

func (s *AdminAnalyticsService) Screens(ctx context.Context, days int) ([]ScreenRow, error) {
	from, to, err := s.window(days)
	if err != nil {
		return nil, err
	}
	rows, err := s.store.AnalyticsScreens(ctx, from, to)
	if err != nil {
		return nil, fmt.Errorf("Screens: %w", err)
	}
	out := make([]ScreenRow, 0, len(rows))
	for _, r := range rows {
		row := ScreenRow{Screen: r.Screen, Views: r.Views, MedianMs: r.MedianMs}
		if r.Views > 0 {
			row.AvgMs = r.TotalMs / int64(r.Views)
		}
		out = append(out, row)
	}
	return out, nil
}

type EventCountRow struct {
	Day     string `json:"day"`
	Name    string `json:"name"`
	Count   int    `json:"count"`
	Uniques int    `json:"uniques"`
}

func (s *AdminAnalyticsService) Events(ctx context.Context, days int, names []string) ([]EventCountRow, error) {
	for _, n := range names {
		if !AnalyticsEventNames[n] {
			return nil, ErrInvalidAnalyticsQuery
		}
	}
	from, to, err := s.window(days)
	if err != nil {
		return nil, err
	}
	rows, err := s.store.AnalyticsEventCounts(ctx, from, to, names)
	if err != nil {
		return nil, fmt.Errorf("Events: %w", err)
	}
	out := make([]EventCountRow, 0, len(rows))
	for _, r := range rows {
		out = append(out, EventCountRow{Day: dayStr(r.Day), Name: r.Name, Count: r.Count, Uniques: r.Uniques})
	}
	return out, nil
}

type TimelineItem struct {
	TS         time.Time       `json:"ts"`
	Name       string          `json:"name"`
	Screen     string          `json:"screen,omitempty"`
	Props      json.RawMessage `json:"props,omitempty"`
	SessionID  string          `json:"session_id,omitempty"`
	InstallID  string          `json:"install_id"`
	Platform   string          `json:"platform,omitempty"`
	AppVersion string          `json:"app_version,omitempty"`
}

type TimelineInstall struct {
	InstallID  string `json:"install_id"`
	UserID     string `json:"user_id,omitempty"`
	FirstSeen  string `json:"first_seen"`
	LastSeen   string `json:"last_seen"`
	Platform   string `json:"platform,omitempty"`
	AppVersion string `json:"app_version,omitempty"`
}

type Timeline struct {
	Installs   []TimelineInstall `json:"installs"`
	Events     []TimelineItem    `json:"events"`
	NextBefore *time.Time        `json:"next_before,omitempty"` // pass as `before` for the next (older) page
}

// Timeline returns a user's (byUser) or install's events newest first.
func (s *AdminAnalyticsService) Timeline(ctx context.Context, byUser bool, id string, before time.Time, limit int) (*Timeline, error) {
	if !uuidRe.MatchString(strings.ToLower(id)) {
		return nil, ErrInvalidAnalyticsQuery
	}
	if limit <= 0 {
		limit = 200
	}
	if limit > MaxTimelineLimit {
		limit = MaxTimelineLimit
	}
	evs, err := s.store.AnalyticsTimeline(ctx, byUser, id, before, limit)
	if err != nil {
		return nil, fmt.Errorf("Timeline: %w", err)
	}
	insts, err := s.store.AnalyticsInstallsOf(ctx, byUser, id)
	if err != nil {
		return nil, fmt.Errorf("Timeline installs: %w", err)
	}
	out := &Timeline{Installs: make([]TimelineInstall, 0, len(insts)), Events: make([]TimelineItem, 0, len(evs))}
	for _, i := range insts {
		out.Installs = append(out.Installs, TimelineInstall{
			InstallID: i.InstallID, UserID: i.UserID, FirstSeen: dayStr(i.FirstSeen), LastSeen: dayStr(i.LastSeen),
			Platform: i.Platform, AppVersion: i.AppVersion,
		})
	}
	for _, e := range evs {
		out.Events = append(out.Events, TimelineItem{
			TS: e.TS.UTC(), Name: e.Name, Screen: e.Screen, Props: e.Props, SessionID: e.SessionID,
			InstallID: e.InstallID, Platform: e.Platform, AppVersion: e.AppVersion,
		})
	}
	if len(evs) == limit {
		t := evs[len(evs)-1].TS.UTC()
		out.NextBefore = &t
	}
	return out, nil
}
