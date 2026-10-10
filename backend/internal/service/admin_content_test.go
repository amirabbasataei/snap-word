package service_test

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

// fakeContent implements the store, daily reader, boards and banned lookup.
type fakeContent struct {
	challenges map[string]*repository.DailyChallengeRow
	players    map[string]int
	rewards    repository.AdminDailyRewards
	board      []*repository.DailyBoardRow
	banned     map[string]struct{}
	setCalls   int
	lastSet    struct {
		date   time.Time
		seed   int64
		letter string
	}
	weekly []service.LeaderboardEntry
}

func newFakeContent() *fakeContent {
	return &fakeContent{
		challenges: map[string]*repository.DailyChallengeRow{},
		players:    map[string]int{},
		banned:     map[string]struct{}{},
	}
}

func (f *fakeContent) add(date time.Time, letter string) {
	f.challenges[date.Format("2006-01-02")] = &repository.DailyChallengeRow{ChallengeDate: date, Seed: date.Unix(), StartLetter: letter}
}

func (f *fakeContent) ListTauntsAdmin(context.Context) ([]repository.AdminTaunt, error) {
	return []repository.AdminTaunt{{ID: "a_b", Text: "x", SortOrder: 1}}, nil
}
func (f *fakeContent) ListAvatarsAdmin(context.Context) ([]repository.AdminAvatar, error) {
	return []repository.AdminAvatar{{ID: "lion", Users: 3, ActiveUsers: 1}}, nil
}
func (f *fakeContent) AvatarUsage(_ context.Context, id string) (int, int, error) {
	if id != "lion" {
		return 0, 0, repository.ErrCatalogItemNotFound
	}
	return 3, 1, nil
}
func (f *fakeContent) ListDaily(_ context.Context, from, to time.Time) ([]repository.AdminDailyRow, error) {
	var out []repository.AdminDailyRow
	for _, c := range f.challenges {
		if !c.ChallengeDate.Before(from) && !c.ChallengeDate.After(to) {
			n := f.players[c.ChallengeDate.Format("2006-01-02")]
			out = append(out, repository.AdminDailyRow{Date: c.ChallengeDate, Seed: c.Seed, StartLetter: c.StartLetter, Players: n, Attempts: n})
		}
	}
	return out, nil
}
func (f *fakeContent) DailyStats(_ context.Context, date time.Time) (repository.AdminDailyStats, error) {
	n := f.players[date.Format("2006-01-02")]
	return repository.AdminDailyStats{Players: n, Attempts: n}, nil
}
func (f *fakeContent) DailyAttempts(context.Context, time.Time, int) ([]repository.AdminDayAttempt, error) {
	return nil, nil
}
func (f *fakeContent) DailyRewards(context.Context, time.Time) (repository.AdminDailyRewards, error) {
	return f.rewards, nil
}
func (f *fakeContent) SetDailyStartLetter(_ context.Context, date time.Time, seed int64, letter string, today time.Time) error {
	if !date.After(today) {
		return repository.ErrDailyLocked
	}
	f.setCalls++
	f.lastSet.date, f.lastSet.seed, f.lastSet.letter = date, seed, letter
	f.add(date, letter)
	return nil
}
func (f *fakeContent) WeeklyRewards(context.Context, int) ([]repository.AdminWeeklyReward, error) {
	d1 := time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC)
	d0 := time.Date(2026, 9, 26, 0, 0, 0, 0, time.UTC)
	return []repository.AdminWeeklyReward{
		{WeekStart: d1, Rank: 1, UserID: "u1", Username: "a", Coins: 500},
		{WeekStart: d1, Rank: 2, UserID: "u2", Username: "b", Coins: 300, Banned: true},
		{WeekStart: d0, Rank: 1, UserID: "u3", Username: "c", Coins: 500},
	}, nil
}
func (f *fakeContent) GetChallenge(_ context.Context, date time.Time) (*repository.DailyChallengeRow, error) {
	if c, ok := f.challenges[date.Format("2006-01-02")]; ok {
		return c, nil
	}
	return nil, repository.ErrNoDailyChallenge
}
func (f *fakeContent) GetDailyLeaderboard(context.Context, time.Time, int) ([]*repository.DailyBoardRow, error) {
	return f.board, nil
}
func (f *fakeContent) GetTopN(_ context.Context, n int) ([]service.LeaderboardEntry, error) {
	return f.weekly, nil
}
func (f *fakeContent) GetAllTimeTop(_ context.Context, n int) ([]service.LeaderboardEntry, error) {
	return f.weekly, nil
}
func (f *fakeContent) BannedIDs(_ context.Context, ids []string) (map[string]struct{}, error) {
	return f.banned, nil
}

type contentEnv struct {
	svc   *service.AdminContentService
	rdb   *redis.Client
	fake  *fakeContent
	audit *testutil.FakeAdminStore
	today time.Time
}

func newContentEnv(t *testing.T) *contentEnv {
	t.Helper()
	_, rdb := testutil.NewRedis(t)
	f := newFakeContent()
	audit := testutil.NewFakeAdminStore()
	svc, err := service.NewAdminContentService(f, f, f, f, rdb, service.NewAuditService(audit), &config.Config{GameEpochDate: "2025-01-01"})
	if err != nil {
		t.Fatal(err)
	}
	return &contentEnv{rdb: rdb, svc: svc, fake: f, audit: audit, today: config.IranDate(time.Now())}
}

func (e *contentEnv) day(offset int) time.Time { return e.today.AddDate(0, 0, offset) }
func ymd(d time.Time) string                   { return d.Format("2006-01-02") }

var operator = service.AuditActor{AdminID: "adm-1", Name: "opera", IP: "10.0.0.1"}

func TestSetStartLetter_FutureOnly(t *testing.T) {
	e := newContentEnv(t)
	ctx := context.Background()
	letters := engine.DailyStartLetters()
	if len(letters) < 2 {
		t.Fatalf("dictionary yields %d eligible letters", len(letters))
	}
	for _, off := range []int{-3, -1, 0} {
		e.fake.add(e.day(off), letters[0])
		_, err := e.svc.SetStartLetter(ctx, operator, ymd(e.day(off)), letters[1], "تست دلیل")
		if !errors.Is(err, service.ErrDailyNotEditable) {
			t.Errorf("offset %d: got %v, want ErrDailyNotEditable", off, err)
		}
	}
	if e.fake.setCalls != 0 || len(e.audit.Audits) != 0 {
		t.Fatalf("locked days must not write: calls=%d audits=%d", e.fake.setCalls, len(e.audit.Audits))
	}

	// Tomorrow exists already (scheduler row): update + audit with before/after.
	e.fake.add(e.day(1), letters[0])
	res, err := e.svc.SetStartLetter(ctx, operator, ymd(e.day(1)), letters[1], "  تغییر دستی  ")
	if err != nil {
		t.Fatal(err)
	}
	if res.Previous != letters[0] || res.StartLetter != letters[1] || res.Created {
		t.Errorf("result %+v", res)
	}
	if len(e.audit.Audits) != 1 {
		t.Fatalf("audits = %d", len(e.audit.Audits))
	}
	a := e.audit.Audits[0]
	p, _ := a.Payload.(map[string]any)
	if a.Action != "daily.start_letter" || a.TargetType != "daily" || a.TargetID != ymd(e.day(1)) ||
		a.Actor != "opera" || p["before"] != letters[0] || p["after"] != letters[1] || p["reason"] != "تغییر دستی" {
		t.Errorf("audit %+v", a)
	}
}

func TestSetStartLetter_CreatesMissingFutureRowWithDefaultSeed(t *testing.T) {
	e := newContentEnv(t)
	letters := engine.DailyStartLetters()
	date := e.day(5)
	res, err := e.svc.SetStartLetter(context.Background(), operator, ymd(date), letters[0], "برنامه‌ریزی")
	if err != nil {
		t.Fatal(err)
	}
	if !res.Created || res.Previous != engine.PickDailyStartLetter(date.Unix()) {
		t.Errorf("result %+v", res)
	}
	if e.fake.lastSet.seed != date.Unix() {
		t.Errorf("seed = %d, want date.Unix() = %d (as EnsureChallenge)", e.fake.lastSet.seed, date.Unix())
	}
}

func TestSetStartLetter_Validation(t *testing.T) {
	e := newContentEnv(t)
	ctx := context.Background()
	good := engine.DailyStartLetters()[0]
	cases := []struct {
		name, date, letter, reason string
		want                       error
	}{
		{"no reason", ymd(e.day(1)), good, "", service.ErrReasonRequired},
		{"short reason", ymd(e.day(1)), good, "ab", service.ErrReasonRequired},
		{"bad date", "1405-01-01x", good, "دلیل", service.ErrInvalidDate},
		{"too far", ymd(e.day(service.AdminDailyMaxFutureDays + 1)), good, "دلیل", service.ErrInvalidDate},
		{"empty letter", ymd(e.day(1)), "", "دلیل", service.ErrInvalidLetter},
		{"two letters", ymd(e.day(1)), good + good, "دلیل", service.ErrInvalidLetter},
		{"latin letter", ymd(e.day(1)), "a", "دلیل", service.ErrInvalidLetter},
		{"digit", ymd(e.day(1)), "1", "دلیل", service.ErrInvalidLetter},
		{"ineligible rare letter", ymd(e.day(1)), "ء", "دلیل", service.ErrInvalidLetter},
	}
	for _, tc := range cases {
		if _, err := e.svc.SetStartLetter(ctx, operator, tc.date, tc.letter, tc.reason); !errors.Is(err, tc.want) {
			t.Errorf("%s: got %v, want %v", tc.name, err, tc.want)
		}
	}
	if len(e.audit.Audits) != 0 || e.fake.setCalls != 0 {
		t.Error("rejected requests must not write")
	}
}

func TestDailyCalendar(t *testing.T) {
	e := newContentEnv(t)
	ctx := context.Background()
	letters := engine.DailyStartLetters()
	e.fake.add(e.day(-2), letters[0])
	e.fake.players[ymd(e.day(-2))] = 4
	e.fake.add(e.day(0), letters[0])
	e.fake.add(e.day(1), letters[1]) // may or may not differ from the seed's letter

	out, err := e.svc.DailyCalendar(ctx, "", "")
	if err != nil {
		t.Fatal(err)
	}
	// today+7 … today-29: 7 future days (some synthesized, tomorrow real) + today + the one generated past day.
	if len(out.Rows) != 7+1+1 {
		t.Fatalf("rows = %d: %+v", len(out.Rows), out.Rows)
	}
	if out.Rows[0].Date != ymd(e.day(7)) || out.Rows[0].Generated || !out.Rows[0].Editable || out.Rows[0].Status != "future" {
		t.Errorf("first row %+v", out.Rows[0])
	}
	if out.Rows[0].StartLetter != engine.PickDailyStartLetter(e.day(7).Unix()) {
		t.Errorf("synthesized row must show the letter that will be generated")
	}
	last := out.Rows[len(out.Rows)-1]
	if last.Date != ymd(e.day(-2)) || last.Players != 4 || last.Editable || last.Status != "past" {
		t.Errorf("last row %+v", last)
	}
	if today := out.Rows[7]; today.Date != ymd(e.day(0)) || today.Status != "today" || today.Editable {
		t.Errorf("today row %+v", today)
	}
	if len(out.EligibleLetters) != len(letters) {
		t.Errorf("eligible letters = %d", len(out.EligibleLetters))
	}

	for name, q := range map[string][2]string{
		"reversed":   {ymd(e.day(1)), ymd(e.day(-1))},
		"garbage":    {"x", ""},
		"too wide":   {ymd(e.day(-200)), ymd(e.day(0))},
		"too far up": {"", ymd(e.day(service.AdminDailyMaxFutureDays + 1))},
	} {
		if _, err := e.svc.DailyCalendar(ctx, q[0], q[1]); !errors.Is(err, service.ErrInvalidDate) {
			t.Errorf("%s: got %v", name, err)
		}
	}
}

func TestDailyDetail_PayoutStates(t *testing.T) {
	e := newContentEnv(t)
	ctx := context.Background()
	l := engine.DailyStartLetters()[0]
	for _, off := range []int{-5, -1, 0, 1} {
		e.fake.add(e.day(off), l)
	}
	state := func(off, players, doneCreated int, flag bool) string {
		e.fake.players[ymd(e.day(off))] = players
		e.fake.rewards = repository.AdminDailyRewards{DoneCreated: doneCreated}
		d, err := e.svc.DailyDetail(ctx, ymd(e.day(off)))
		if err != nil {
			t.Fatal(err)
		}
		return d.Payout.State
	}
	if got := state(1, 0, 0, false); got != "not_due" {
		t.Errorf("future = %s", got)
	}
	if got := state(0, 3, 0, false); got != "not_due" {
		t.Errorf("today = %s", got)
	}
	if got := state(-1, 0, 0, false); got != "no_players" {
		t.Errorf("empty = %s", got)
	}
	if got := state(-1, 3, 0, false); got != "pending" {
		t.Errorf("yesterday unpaid = %s", got)
	}
	if got := state(-5, 3, 0, false); got != "missed" {
		t.Errorf("old unpaid = %s", got)
	}
	// Flag set by a run that predates the attempts: no rewards exist, so it is not "paid".
	e.fake.players[ymd(e.day(-1))] = 3
	e.fake.rewards = repository.AdminDailyRewards{}
	if err := e.rdb.Set(ctx, "payout:daily:"+ymd(e.day(-1)), 1, 0).Err(); err != nil {
		t.Fatal(err)
	}
	if got := state(-1, 3, 0, true); got != "missed" {
		t.Errorf("flagged but unpaid = %s", got)
	}
	if got := state(-5, 3, 3, false); got != "paid" {
		t.Errorf("old paid (flag long expired, rewards exist) = %s", got)
	}

	if _, err := e.svc.DailyDetail(ctx, ymd(e.day(30))); !errors.Is(err, service.ErrNoChallenge) {
		t.Errorf("missing day: %v", err)
	}
	if _, err := e.svc.DailyDetail(ctx, "nope"); !errors.Is(err, service.ErrInvalidDate) {
		t.Errorf("bad date: %v", err)
	}
}

func TestDailyDetail_FlagsBannedOnBoard(t *testing.T) {
	e := newContentEnv(t)
	e.fake.add(e.day(-1), engine.DailyStartLetters()[0])
	e.fake.board = []*repository.DailyBoardRow{{Rank: 1, UserID: "u1", Username: "a", Score: 90}, {Rank: 2, UserID: "u2", Username: "b", Score: 50}}
	e.fake.banned["u2"] = struct{}{}
	d, err := e.svc.DailyDetail(context.Background(), ymd(e.day(-1)))
	if err != nil {
		t.Fatal(err)
	}
	if d.Board[0].Banned || !d.Board[1].Banned {
		t.Errorf("board %+v", d.Board)
	}
}

func TestBoards(t *testing.T) {
	e := newContentEnv(t)
	ctx := context.Background()
	e.fake.weekly = []service.LeaderboardEntry{{Rank: 1, UserID: "u1", Username: "a", Score: 10, AvatarID: "lion"}}

	w, err := e.svc.WeeklyBoard(ctx, 0)
	if err != nil {
		t.Fatal(err)
	}
	if w.Limit != 50 || len(w.Entries) != 1 || w.Entries[0].AvatarID != "lion" || w.ResetsAt == nil {
		t.Errorf("weekly %+v", w)
	}
	if l := w.ResetsAt.In(config.IranLocation); l.Weekday() != time.Saturday || l.Hour() != 0 || !w.ResetsAt.After(time.Now()) {
		t.Errorf("resets_at = %v", l)
	}
	a, err := e.svc.AllTimeBoard(ctx, 10)
	if err != nil || a.Limit != 10 || a.ResetsAt != nil {
		t.Errorf("alltime %+v %v", a, err)
	}
	for _, bad := range []int{-1, 101} {
		if _, err := e.svc.WeeklyBoard(ctx, bad); !errors.Is(err, service.ErrInvalidLimit) {
			t.Errorf("limit %d: %v", bad, err)
		}
	}

	h, err := e.svc.WeeklyRewardHistory(ctx, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(h.Weeks) != 2 || h.Weeks[0].PayoutDate != "2026-10-03" || len(h.Weeks[0].Rewards) != 2 || !h.Weeks[0].Rewards[1].Banned {
		t.Errorf("history %+v", h)
	}
	if fmt.Sprint(h.Prizes) != fmt.Sprint([]int{500, 300, 100}) {
		t.Errorf("prizes %v", h.Prizes)
	}
	if _, err := e.svc.WeeklyRewardHistory(ctx, 53); !errors.Is(err, service.ErrInvalidLimit) {
		t.Errorf("weeks 53: %v", err)
	}
}

func TestReasonFor(t *testing.T) {
	script := service.AuditActor{Name: "script"}
	if r, err := service.ReasonFor(script, "  "); err != nil || r != "" {
		t.Errorf("script without reason: %q %v", r, err)
	}
	if _, err := service.ReasonFor(script, "x"); !errors.Is(err, service.ErrReasonRequired) {
		t.Errorf("script with a too-short reason must be rejected: %v", err)
	}
	if _, err := service.ReasonFor(operator, ""); !errors.Is(err, service.ErrReasonRequired) {
		t.Errorf("session without reason: %v", err)
	}
	if r, err := service.ReasonFor(operator, " ok then "); err != nil || r != "ok then" {
		t.Errorf("session: %q %v", r, err)
	}
	if _, err := service.ReasonFor(operator, strings.Repeat("x", 201)); !errors.Is(err, service.ErrReasonRequired) {
		t.Errorf("too long: %v", err)
	}
}

func TestAvatarUsageAndLists(t *testing.T) {
	e := newContentEnv(t)
	ctx := context.Background()
	u, err := e.svc.AvatarUsage(ctx, "lion")
	if err != nil || u.Users != 3 || u.ActiveUsers != 1 {
		t.Errorf("usage %+v %v", u, err)
	}
	if _, err := e.svc.AvatarUsage(ctx, "nope"); !errors.Is(err, repository.ErrCatalogItemNotFound) {
		t.Errorf("unknown avatar: %v", err)
	}
	av, _ := e.svc.Avatars(ctx)
	if av.MaxBytes != config.AvatarMaxBytes || len(av.Items) != 1 {
		t.Errorf("avatars %+v", av)
	}
	ta, _ := e.svc.Taunts(ctx)
	if ta.MaxTextRunes != config.TauntMaxTextRunes || len(ta.Items) != 1 {
		t.Errorf("taunts %+v", ta)
	}
}
