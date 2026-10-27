package repository_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/testutil"
)

const (
	installA = "aaaaaaaa-0000-4000-8000-000000000001"
	installB = "bbbbbbbb-0000-4000-8000-000000000002"
	userU    = "cccccccc-0000-4000-8000-000000000003"
)

func evID(n int) string { return fmt.Sprintf("eeeeeeee-0000-4000-8000-%012d", n) }

func ev(n int, name string, ts time.Time) repository.AnalyticsEvent {
	return repository.AnalyticsEvent{ClientEventID: evID(n), Name: name, TS: ts}
}

// noon of the given Iran day, expressed in UTC.
func irNoon(day time.Time) time.Time {
	return time.Date(day.Year(), day.Month(), day.Day(), 12, 0, 0, 0, config.IranLocation).UTC()
}

func TestAnalytics_InsertIsIdempotentAndLinksInstall(t *testing.T) {
	db := testutil.NewPostgres(t)
	repo := repository.NewAnalyticsRepository(db)
	ctx := context.Background()
	now := time.Now().UTC()

	batch := repository.AnalyticsBatch{InstallID: installA, Platform: "android", AppVersion: "1.0.0",
		Events: []repository.AnalyticsEvent{ev(1, "app_open", now), ev(2, "game_start", now)}}
	n, err := repo.InsertAnalyticsEvents(ctx, batch)
	if err != nil || n != 2 {
		t.Fatalf("first insert = %d, %v", n, err)
	}
	// A retry of the same batch (lost response) inserts nothing.
	if n, err = repo.InsertAnalyticsEvents(ctx, batch); err != nil || n != 0 {
		t.Fatalf("retry = %d, %v; want 0", n, err)
	}

	// A later batch with a user id links the install to the account.
	batch.UserID = userU
	batch.Events = []repository.AnalyticsEvent{ev(3, "login", now)}
	if _, err := repo.InsertAnalyticsEvents(ctx, batch); err != nil {
		t.Fatal(err)
	}
	var linked string
	if err := db.QueryRow(`SELECT user_id::text FROM analytics_installs WHERE install_id = $1`, installA).Scan(&linked); err != nil || linked != userU {
		t.Fatalf("install link = %q, %v", linked, err)
	}
	// A guest batch afterwards must not unlink it.
	batch.UserID = ""
	batch.Events = []repository.AnalyticsEvent{ev(4, "app_open", now)}
	repo.InsertAnalyticsEvents(ctx, batch)
	db.QueryRow(`SELECT user_id::text FROM analytics_installs WHERE install_id = $1`, installA).Scan(&linked)
	if linked != userU {
		t.Fatalf("guest batch unlinked the install: %q", linked)
	}
}

func TestAnalytics_FirstSeenMovesEarlierForOfflineBatches(t *testing.T) {
	db := testutil.NewPostgres(t)
	repo := repository.NewAnalyticsRepository(db)
	ctx := context.Background()
	today := config.IranDate(time.Now())

	mk := func(n int, d time.Time) repository.AnalyticsBatch {
		return repository.AnalyticsBatch{InstallID: installA, Events: []repository.AnalyticsEvent{ev(n, "app_open", irNoon(d))}}
	}
	repo.InsertAnalyticsEvents(ctx, mk(1, today))
	repo.InsertAnalyticsEvents(ctx, mk(2, today.AddDate(0, 0, -3)))
	var first, last time.Time
	db.QueryRow(`SELECT first_seen, last_seen FROM analytics_installs WHERE install_id=$1`, installA).Scan(&first, &last)
	if !first.UTC().Equal(today.AddDate(0, 0, -3)) || !last.UTC().Equal(today) {
		t.Fatalf("first/last = %v / %v", first, last)
	}
}

func TestAnalytics_PartitionsEnsureAndDrop(t *testing.T) {
	db := testutil.NewPostgres(t)
	repo := repository.NewAnalyticsRepository(db)
	ctx := context.Background()
	now := time.Now().UTC()

	if err := repo.EnsureAnalyticsPartitions(ctx, now, 2); err != nil { // idempotent over the migration's set
		t.Fatal(err)
	}
	far := now.AddDate(0, 3, 0)
	if _, err := repo.InsertAnalyticsEvents(ctx, repository.AnalyticsBatch{InstallID: installA,
		Events: []repository.AnalyticsEvent{ev(1, "app_open", far)}}); err == nil {
		t.Fatal("insert beyond the ensured partitions should fail")
	}

	// Drop everything that ended before next month: last month's partition goes, this month's stays.
	dropped, err := repo.DropOldAnalyticsPartitions(ctx, time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC))
	if err != nil || len(dropped) != 1 {
		t.Fatalf("dropped = %v, %v", dropped, err)
	}
	if _, err := repo.InsertAnalyticsEvents(ctx, repository.AnalyticsBatch{InstallID: installA,
		Events: []repository.AnalyticsEvent{ev(2, "app_open", now)}}); err != nil {
		t.Fatalf("current month must still accept events: %v", err)
	}
}

func TestAnalytics_RollupAndAdminQueries(t *testing.T) {
	db := testutil.NewPostgres(t)
	repo := repository.NewAnalyticsRepository(db)
	admin := repository.NewAdminRepository(db)
	ctx := context.Background()
	today := config.IranDate(time.Now())
	d1 := today.AddDate(0, 0, -1)

	// A: seen yesterday (screen 10s, session 60s), back today, signed in -> funnel completes.
	// B: seen yesterday only.
	n := 0
	next := func() int { n++; return n }
	insert := func(install, user string, es ...repository.AnalyticsEvent) {
		if _, err := repo.InsertAnalyticsEvents(ctx, repository.AnalyticsBatch{InstallID: install, UserID: user, Events: es}); err != nil {
			t.Fatal(err)
		}
	}
	withProps := func(name, screen, props string, ts time.Time) repository.AnalyticsEvent {
		e := ev(next(), name, ts)
		e.Screen, e.Props = screen, []byte(props)
		return e
	}
	y := irNoon(d1)
	insert(installA, "", ev(next(), "app_open", y), ev(next(), "game_start", y.Add(time.Minute)),
		withProps("screen_view", "home", `{"duration_ms":10000}`, y), withProps("session_end", "", `{"duration_ms":60000}`, y.Add(time.Hour)))
	insert(installB, "", ev(next(), "app_open", y))
	td := irNoon(today)
	insert(installA, userU, ev(next(), "app_open", td), ev(next(), "signup", td.Add(time.Minute)),
		withProps("screen_view", "home", `{"duration_ms":30000}`, td))

	for _, d := range []time.Time{d1, today} {
		if err := repo.RollupAnalyticsDay(ctx, d); err != nil {
			t.Fatal(err)
		}
	}
	// Re-running a day replaces its rows instead of doubling them.
	if err := repo.RollupAnalyticsDay(ctx, d1); err != nil {
		t.Fatal(err)
	}

	ov, err := admin.AnalyticsOverview(ctx, d1, today)
	if err != nil {
		t.Fatal(err)
	}
	if got := ov.Series[0]; got.Active != 2 || got.NewInstalls != 2 || got.Sessions != 1 || got.SessionMsSum != 60000 {
		t.Errorf("yesterday = %+v", got)
	}
	if got := ov.Series[1]; got.Active != 1 || got.ActiveUsers != 1 || got.NewInstalls != 0 {
		t.Errorf("today = %+v", got)
	}
	if ov.WAU != 2 || ov.MAU != 2 || ov.TotalInstalls != 2 || ov.LinkedInstall != 1 {
		t.Errorf("totals = %+v", ov)
	}

	// Retention by install: cohort yesterday has 2 members, 1 returned today (D1).
	cells, err := admin.AnalyticsRetention(ctx, d1, d1, false)
	if err != nil {
		t.Fatal(err)
	}
	got := map[int]int{}
	for _, c := range cells {
		got[c.Offset] = c.Count
	}
	if got[0] != 2 || got[1] != 1 {
		t.Errorf("install retention = %v", got)
	}
	// By user: the user's cohort is today (first signed-in day), size 1.
	cells, err = admin.AnalyticsRetention(ctx, today, today, true)
	if err != nil || len(cells) != 1 || cells[0].Offset != 0 || cells[0].Count != 1 {
		t.Errorf("user retention = %+v, %v", cells, err)
	}

	// Funnel: both installs opened, only A started a game, then A signed up (after the game start? no: signup is later).
	start := time.Date(d1.Year(), d1.Month(), d1.Day(), 0, 0, 0, 0, config.IranLocation)
	end := start.Add(48 * time.Hour)
	steps, err := admin.AnalyticsFunnel(ctx, []string{"app_open", "game_start", "signup"}, start, end)
	if err != nil || steps[0] != 2 || steps[1] != 1 || steps[2] != 1 {
		t.Errorf("funnel = %v, %v", steps, err)
	}
	// Order matters: signup before game_start never counts.
	steps, _ = admin.AnalyticsFunnel(ctx, []string{"signup", "game_start"}, start, end)
	if steps[0] != 1 || steps[1] != 0 {
		t.Errorf("reverse funnel = %v", steps)
	}

	scr, err := admin.AnalyticsScreens(ctx, d1, today)
	if err != nil || len(scr) != 1 || scr[0].Views != 2 || scr[0].TotalMs != 40000 {
		t.Errorf("screens = %+v, %v", scr, err)
	}
	counts, err := admin.AnalyticsEventCounts(ctx, d1, today, []string{"app_open"})
	if err != nil || len(counts) != 2 {
		t.Errorf("event counts = %+v, %v", counts, err)
	}

	// The user's timeline spans the guest events from the same install.
	tl, err := admin.AnalyticsTimeline(ctx, true, userU, time.Time{}, 100)
	if err != nil || len(tl) != 7 {
		t.Errorf("user timeline = %d events, %v", len(tl), err)
	}
	if len(tl) > 1 && tl[0].TS.Before(tl[1].TS) {
		t.Error("timeline must be newest first")
	}
	inst, _ := admin.AnalyticsInstallsOf(ctx, true, userU)
	if len(inst) != 1 || inst[0].InstallID != installA {
		t.Errorf("installs of user = %+v", inst)
	}
}
