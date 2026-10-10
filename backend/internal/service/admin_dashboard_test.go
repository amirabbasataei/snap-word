package service_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
	"wordchain/backend/internal/ws"
)

type fakeDashStore struct {
	counts    repository.DashboardCounts
	from, to  time.Time
	rows      []repository.DashboardDay
	countsErr error
}

func (f *fakeDashStore) DashboardCounts(context.Context, time.Time) (*repository.DashboardCounts, error) {
	if f.countsErr != nil {
		return nil, f.countsErr
	}
	c := f.counts
	return &c, nil
}

func (f *fakeDashStore) DashboardTimeseries(_ context.Context, from, to time.Time) ([]repository.DashboardDay, error) {
	f.from, f.to = from, to
	return f.rows, nil
}

type fakeHub struct{}

func (fakeHub) Snapshot() ws.HubSnapshot {
	return ws.HubSnapshot{Rooms: 3, WaitingRooms: 1, ActiveRooms: 2, ConnectedPlayers: 4}
}

type fakeFCM bool

func (f fakeFCM) Configured() bool { return bool(f) }

func newDashSvc(t *testing.T, store *fakeDashStore) (*service.AdminDashboardService, func(string, string)) {
	t.Helper()
	_, rdb := testutil.NewRedis(t)
	svc := service.NewAdminDashboardService(store, fakeHub{}, rdb, fakeFCM(true))
	push := func(key, v string) { rdb.RPush(context.Background(), key, v) }
	return svc, push
}

func TestDashboardSummaryCombinesSources(t *testing.T) {
	store := &fakeDashStore{counts: repository.DashboardCounts{
		UsersTotal: 12, MatchesTodaySolo: 2, MatchesTodayVersus: 1, MatchesTodayAIOnline: 1, MatchesTodayDaily: 3,
		UnclaimedRewards: 4, UnclaimedRewardCoins: 90,
	}}
	svc, push := newDashSvc(t, store)
	push("queue:classic", "a")
	push("queue:classic", "b")

	got, err := svc.Summary(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if got.Users.Total != 12 || got.MatchesToday.Total != 7 {
		t.Errorf("users=%d matches=%d", got.Users.Total, got.MatchesToday.Total)
	}
	if got.Live.Rooms != 3 || got.Live.ConnectedPlayers != 4 || got.Live.QueueLength != 2 {
		t.Errorf("live = %+v", got.Live)
	}
	if got.UnclaimedRewards.Coins != 90 || !got.FCMConfigured {
		t.Errorf("rewards/fcm = %+v %v", got.UnclaimedRewards, got.FCMConfigured)
	}
}

func TestDashboardSummaryStoreError(t *testing.T) {
	boom := errors.New("db down")
	svc, _ := newDashSvc(t, &fakeDashStore{countsErr: boom})
	if _, err := svc.Summary(context.Background()); !errors.Is(err, boom) {
		t.Fatalf("err = %v", err)
	}
}

func TestDashboardTimeseriesWindowUsesIranDays(t *testing.T) {
	store := &fakeDashStore{rows: []repository.DashboardDay{{Day: time.Date(2026, 10, 10, 0, 0, 0, 0, time.UTC), Signups: 2, CoinsClaimed: 30}}}
	svc, _ := newDashSvc(t, store)
	// 22:00 UTC on Oct 9 is already 01:30 on Oct 10 in Iran.
	svc.SetNow(func() time.Time { return time.Date(2026, 10, 9, 22, 0, 0, 0, time.UTC) })

	pts, err := svc.Timeseries(context.Background(), 7)
	if err != nil {
		t.Fatal(err)
	}
	if got := store.to.Format("2006-01-02"); got != "2026-10-10" {
		t.Errorf("to = %s, want the Iran date 2026-10-10", got)
	}
	if got := store.from.Format("2006-01-02"); got != "2026-10-04" {
		t.Errorf("from = %s", got)
	}
	if len(pts) != 1 || pts[0].Date != "2026-10-10" || pts[0].Signups != 2 || pts[0].CoinsClaimed != 30 {
		t.Errorf("points = %+v", pts)
	}
}

func TestDashboardTimeseriesRejectsBadRange(t *testing.T) {
	svc, _ := newDashSvc(t, &fakeDashStore{})
	for _, days := range []int{0, -1, service.MaxDashboardDays + 1} {
		if _, err := svc.Timeseries(context.Background(), days); !errors.Is(err, service.ErrInvalidDashboardRange) {
			t.Errorf("days=%d err=%v", days, err)
		}
	}
}
