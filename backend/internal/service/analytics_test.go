package service_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

type fakeAnalyticsStore struct {
	batches []repository.AnalyticsBatch
	err     error
}

func (f *fakeAnalyticsStore) InsertAnalyticsEvents(_ context.Context, b repository.AnalyticsBatch) (int, error) {
	if f.err != nil {
		return 0, f.err
	}
	f.batches = append(f.batches, b)
	return len(b.Events), nil
}

const (
	anInstall = "aaaaaaaa-0000-4000-8000-000000000001"
	anEvent   = "eeeeeeee-0000-4000-8000-000000000001"
)

func newAnalyticsSvc(t *testing.T) (*service.AnalyticsService, *fakeAnalyticsStore) {
	t.Helper()
	_, rdb := testutil.NewRedis(t)
	store := &fakeAnalyticsStore{}
	return service.NewAnalyticsService(store, rdb), store
}

func nowMs() int64 { return time.Now().UnixMilli() }

func TestAnalyticsIngest_ValidatesPerEventAndKeepsGoodOnes(t *testing.T) {
	svc, store := newAnalyticsSvc(t)
	in := service.AnalyticsBatchInput{
		InstallID: anInstall, Platform: "android", AppVersion: "1.2.3",
		Events: []service.AnalyticsEventInput{
			{ClientEventID: anEvent, Name: "app_open", TS: nowMs()},
			{ClientEventID: "eeeeeeee-0000-4000-8000-000000000002", Name: "not_in_vocabulary", TS: nowMs()},
			{ClientEventID: "not-a-uuid", Name: "app_open", TS: nowMs()},
			{ClientEventID: "eeeeeeee-0000-4000-8000-000000000003", Name: "game_start", TS: nowMs(),
				Screen: "game", Props: map[string]any{"mode": "solo"}},
			{ClientEventID: "eeeeeeee-0000-4000-8000-000000000004", Name: "share", TS: nowMs(),
				Props: map[string]any{"blob": strings.Repeat("x", config.AnalyticsMaxPropsBytes+1)}},
		},
	}
	out, err := svc.Ingest(context.Background(), "user-1", in)
	if err != nil {
		t.Fatal(err)
	}
	if out.Accepted != 2 || out.Rejected != 3 {
		t.Fatalf("result = %+v, want 2 accepted / 3 rejected", out)
	}
	b := store.batches[0]
	if b.UserID != "user-1" || b.InstallID != anInstall || b.Platform != "android" {
		t.Errorf("batch envelope = %+v", b)
	}
	if string(b.Events[1].Props) != `{"mode":"solo"}` || b.Events[1].Screen != "game" {
		t.Errorf("event = %+v", b.Events[1])
	}
}

func TestAnalyticsIngest_RejectsBadEnvelope(t *testing.T) {
	svc, _ := newAnalyticsSvc(t)
	ev := service.AnalyticsEventInput{ClientEventID: anEvent, Name: "app_open", TS: nowMs()}
	tooMany := make([]service.AnalyticsEventInput, config.AnalyticsMaxBatch+1)
	for i := range tooMany {
		tooMany[i] = ev
	}
	for name, in := range map[string]service.AnalyticsBatchInput{
		"bad install": {InstallID: "nope", Events: []service.AnalyticsEventInput{ev}},
		"empty":       {InstallID: anInstall},
		"too many":    {InstallID: anInstall, Events: tooMany},
	} {
		if _, err := svc.Ingest(context.Background(), "", in); !errors.Is(err, service.ErrAnalyticsInvalid) {
			t.Errorf("%s: err = %v", name, err)
		}
	}
}

func TestAnalyticsIngest_ClampsClientClockAndDurations(t *testing.T) {
	svc, store := newAnalyticsSvc(t)
	mk := func(id string, ts int64, props map[string]any) service.AnalyticsEventInput {
		return service.AnalyticsEventInput{ClientEventID: id, Name: "session_end", TS: ts, Props: props}
	}
	in := service.AnalyticsBatchInput{InstallID: anInstall, Events: []service.AnalyticsEventInput{
		mk("eeeeeeee-0000-4000-8000-000000000001", time.Now().Add(48*time.Hour).UnixMilli(), nil),        // future
		mk("eeeeeeee-0000-4000-8000-000000000002", time.Now().Add(-30*24*time.Hour).UnixMilli(), nil),    // too old
		mk("eeeeeeee-0000-4000-8000-000000000003", time.Now().Add(-2*time.Hour).UnixMilli(), map[string]any{"duration_ms": -5.0}),
		mk("eeeeeeee-0000-4000-8000-000000000004", time.Now().Add(-2*time.Hour).UnixMilli(), map[string]any{"duration_ms": "abc"}),
		mk("eeeeeeee-0000-4000-8000-000000000005", time.Now().Add(-2*time.Hour).UnixMilli(), map[string]any{"duration_ms": 1500.0}),
	}}
	if _, err := svc.Ingest(context.Background(), "", in); err != nil {
		t.Fatal(err)
	}
	evs := store.batches[0].Events
	near := func(ts time.Time, want time.Time) bool { d := ts.Sub(want); return d > -time.Minute && d < time.Minute }
	if !near(evs[0].TS, time.Now()) || !near(evs[1].TS, time.Now()) {
		t.Errorf("out-of-range timestamps were not replaced: %v %v", evs[0].TS, evs[1].TS)
	}
	if !near(evs[2].TS, time.Now().Add(-2*time.Hour)) {
		t.Errorf("in-range timestamp was altered: %v", evs[2].TS)
	}
	if evs[2].Props != nil || evs[3].Props != nil {
		t.Errorf("invalid duration_ms must be dropped: %s %s", evs[2].Props, evs[3].Props)
	}
	if string(evs[4].Props) != `{"duration_ms":1500}` {
		t.Errorf("valid duration_ms = %s", evs[4].Props)
	}
}

func TestAnalyticsIngest_StoreErrorSurfaces(t *testing.T) {
	svc, store := newAnalyticsSvc(t)
	store.err = errors.New("db down")
	in := service.AnalyticsBatchInput{InstallID: anInstall, Events: []service.AnalyticsEventInput{{ClientEventID: anEvent, Name: "app_open", TS: nowMs()}}}
	if _, err := svc.Ingest(context.Background(), "", in); err == nil || errors.Is(err, service.ErrAnalyticsInvalid) {
		t.Fatalf("err = %v", err)
	}
}

func TestAnalyticsAllowRequest_LimitsPerInstall(t *testing.T) {
	svc, _ := newAnalyticsSvc(t)
	ctx := context.Background()
	for i := 0; i < config.AnalyticsRatePerInstallPerMin; i++ {
		if err := svc.AllowRequest(ctx, anInstall, "1.2.3.4"); err != nil {
			t.Fatalf("request %d: %v", i, err)
		}
	}
	if err := svc.AllowRequest(ctx, anInstall, "1.2.3.4"); !errors.Is(err, service.ErrAnalyticsRateLimited) {
		t.Fatalf("over limit: %v", err)
	}
	// Another install on the same IP is unaffected.
	if err := svc.AllowRequest(ctx, "bbbbbbbb-0000-4000-8000-000000000002", "1.2.3.4"); err != nil {
		t.Fatalf("other install: %v", err)
	}
}

type fakeMaint struct {
	rolled  []time.Time
	dropped int
}

func (f *fakeMaint) EnsureAnalyticsPartitions(context.Context, time.Time, int) error { return nil }
func (f *fakeMaint) DropOldAnalyticsPartitions(context.Context, time.Time) ([]string, error) {
	f.dropped++
	return nil, nil
}
func (f *fakeMaint) RollupAnalyticsDay(_ context.Context, d time.Time) error {
	f.rolled = append(f.rolled, d)
	return nil
}

func TestAnalyticsMaintenance_DailyPassRunsOncePerDay(t *testing.T) {
	_, rdb := testutil.NewRedis(t)
	store := &fakeMaint{}
	svc := service.NewAnalyticsMaintenanceService(store, rdb)
	now := time.Now()

	if err := svc.RunDailyPass(context.Background(), now); err != nil {
		t.Fatal(err)
	}
	if len(store.rolled) != config.AnalyticsRollupLookbackDays || store.dropped != 1 {
		t.Fatalf("first pass rolled %d days, dropped %d", len(store.rolled), store.dropped)
	}
	if err := svc.RunDailyPass(context.Background(), now); err != nil {
		t.Fatal(err)
	}
	if len(store.rolled) != config.AnalyticsRollupLookbackDays {
		t.Fatalf("second pass in the same day must be a no-op, rolled %d", len(store.rolled))
	}

	store.rolled = nil
	if err := svc.RefreshRecent(context.Background(), now); err != nil || len(store.rolled) != 2 {
		t.Fatalf("RefreshRecent rolled %d, %v", len(store.rolled), err)
	}
}
