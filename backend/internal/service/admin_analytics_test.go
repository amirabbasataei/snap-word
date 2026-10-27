package service_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

type fakeAdminAnalytics struct {
	cells      []repository.RetentionCell
	retentionN int
	funnel     []int
}

func (f *fakeAdminAnalytics) AnalyticsOverview(context.Context, time.Time, time.Time) (*repository.AnalyticsOverviewData, error) {
	return &repository.AnalyticsOverviewData{}, nil
}
func (f *fakeAdminAnalytics) AnalyticsRetention(context.Context, time.Time, time.Time, bool) ([]repository.RetentionCell, error) {
	f.retentionN++
	return f.cells, nil
}
func (f *fakeAdminAnalytics) AnalyticsFunnel(_ context.Context, steps []string, _, _ time.Time) ([]int, error) {
	return f.funnel[:len(steps)], nil
}
func (f *fakeAdminAnalytics) AnalyticsScreens(context.Context, time.Time, time.Time) ([]repository.ScreenStat, error) {
	return []repository.ScreenStat{{Screen: "home", Views: 4, TotalMs: 20000, MedianMs: 4000}}, nil
}
func (f *fakeAdminAnalytics) AnalyticsEventCounts(context.Context, time.Time, time.Time, []string) ([]repository.EventCount, error) {
	return nil, nil
}
func (f *fakeAdminAnalytics) AnalyticsTimeline(_ context.Context, _ bool, _ string, _ time.Time, limit int) ([]repository.TimelineEvent, error) {
	out := make([]repository.TimelineEvent, limit)
	for i := range out {
		out[i] = repository.TimelineEvent{TS: time.Unix(int64(1000-i), 0), Name: "app_open"}
	}
	return out, nil
}
func (f *fakeAdminAnalytics) AnalyticsInstallsOf(context.Context, bool, string) ([]repository.AnalyticsInstall, error) {
	return nil, nil
}

func TestAdminAnalytics_RetentionMatrixAndCache(t *testing.T) {
	_, rdb := testutil.NewRedis(t)
	today := config.IranDate(time.Now())
	cohort := today.AddDate(0, 0, -2)
	store := &fakeAdminAnalytics{cells: []repository.RetentionCell{
		{Cohort: cohort, Offset: 0, Count: 10}, {Cohort: cohort, Offset: 1, Count: 4},
	}}
	svc := service.NewAdminAnalyticsService(store, rdb)

	res, err := svc.Retention(context.Background(), cohort, today, "install")
	if err != nil {
		t.Fatal(err)
	}
	c := res.Cohorts[0]
	if c.Size != 10 || *c.Retained[0] != 10 || *c.Retained[1] != 4 {
		t.Fatalf("cohort = %+v", c)
	}
	if c.Retained[2] == nil || *c.Retained[2] != 0 { // reached (2 days ago) but nobody came back: 0, not null
		t.Errorf("D2 should be a real zero, got %v", c.Retained[2])
	}
	if c.Retained[3] != nil { // the future is null
		t.Errorf("D3 should be null, got %d", *c.Retained[3])
	}
	if _, err := svc.Retention(context.Background(), cohort, today, "install"); err != nil || store.retentionN != 1 {
		t.Errorf("second call should hit the cache; store calls = %d, err = %v", store.retentionN, err)
	}
	if _, err := svc.Retention(context.Background(), cohort, today, "weird"); !errors.Is(err, service.ErrInvalidAnalyticsQuery) {
		t.Errorf("bad `by`: %v", err)
	}
}

func TestAdminAnalytics_FunnelValidationAndRatios(t *testing.T) {
	svc := service.NewAdminAnalyticsService(&fakeAdminAnalytics{funnel: []int{200, 100, 25}}, nil)
	ctx := context.Background()

	out, err := svc.Funnel(ctx, []string{"app_open", "game_start", "signup"}, 30)
	if err != nil {
		t.Fatal(err)
	}
	if out[1].PctOfFirst != 0.5 || out[2].PctOfFirst != 0.125 || out[2].PctOfPrev != 0.25 {
		t.Errorf("ratios = %+v", out)
	}
	for name, steps := range map[string][]string{
		"one step": {"app_open"}, "unknown": {"app_open", "bogus"},
		"too many": {"app_open", "app_open", "app_open", "app_open", "app_open", "app_open", "app_open"},
	} {
		if _, err := svc.Funnel(ctx, steps, 30); !errors.Is(err, service.ErrInvalidAnalyticsQuery) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if _, err := svc.Funnel(ctx, []string{"app_open", "signup"}, 91); !errors.Is(err, service.ErrInvalidAnalyticsQuery) {
		t.Errorf("days=91: %v", err)
	}
}

func TestAdminAnalytics_ScreensAverageAndTimelinePaging(t *testing.T) {
	svc := service.NewAdminAnalyticsService(&fakeAdminAnalytics{}, nil)
	ctx := context.Background()

	scr, err := svc.Screens(ctx, 7)
	if err != nil || scr[0].AvgMs != 5000 || scr[0].MedianMs != 4000 {
		t.Errorf("screens = %+v, %v", scr, err)
	}

	id := "aaaaaaaa-0000-4000-8000-000000000001"
	tl, err := svc.Timeline(ctx, true, id, time.Time{}, 3)
	if err != nil || len(tl.Events) != 3 || tl.NextBefore == nil || !tl.NextBefore.Equal(time.Unix(998, 0).UTC()) {
		t.Errorf("timeline = %+v, %v", tl, err)
	}
	if _, err := svc.Timeline(ctx, true, "not-a-uuid", time.Time{}, 3); !errors.Is(err, service.ErrInvalidAnalyticsQuery) {
		t.Errorf("bad id: %v", err)
	}
}
