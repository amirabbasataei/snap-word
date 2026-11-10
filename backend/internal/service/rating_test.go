package service_test

import (
	"context"
	"database/sql"
	"fmt"
	"sync"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

// ---- pure Elo math ----

func TestEloExpected(t *testing.T) {
	if got := service.EloExpected(1000, 1000); got != 0.5 {
		t.Fatalf("equal ratings: %v", got)
	}
	if got := service.EloExpected(1000, 1400); got < 0.0908 || got > 0.0910 {
		t.Fatalf("400 below: %v, want ≈ 0.0909", got)
	}
	if a, b := service.EloExpected(1200, 1000), service.EloExpected(1000, 1200); a+b < 0.9999 || a+b > 1.0001 {
		t.Fatalf("expectations must sum to 1: %v + %v", a, b)
	}
}

func TestEloK(t *testing.T) {
	cases := map[int]int{0: 32, 29: 32, 30: 16, 500: 16}
	for games, want := range cases {
		if got := service.EloK(games); got != want {
			t.Errorf("EloK(%d) = %d, want %d", games, got, want)
		}
	}
}

func TestEloUpdate(t *testing.T) {
	pr := func(rating, games int) repository.PlayerRating {
		return repository.PlayerRating{Rating: rating, RatedGames: games, Peak: rating}
	}
	cases := []struct {
		name         string
		winner, lose repository.PlayerRating
		wantW, wantL int
	}{
		{"equal, both provisional", pr(1000, 0), pr(1000, 0), 1016, 984},
		{"equal, both stable", pr(1000, 30), pr(1000, 30), 1008, 992},
		{"each player's own K", pr(1000, 5), pr(1000, 40), 1016, 992},
		{"upset win (400 below)", pr(1000, 40), pr(1400, 40), 1015, 1385},
		{"favourite wins (400 above)", pr(1400, 40), pr(1000, 40), 1401, 999},
		{"floor at 0", pr(10, 0), pr(10, 0), 26, 0},
		{"underdog loser loses ~nothing", pr(1000, 0), pr(10, 0), 1000, 10},
		{"huge gap rounds to 0", pr(2400, 40), pr(800, 40), 2400, 800},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			w, l := service.EloUpdate(c.winner, c.lose)
			if w != c.wantW || l != c.wantL {
				t.Fatalf("got %d/%d, want %d/%d", w, l, c.wantW, c.wantL)
			}
		})
	}
}

func TestIsRatedPair(t *testing.T) {
	cases := []struct {
		w, l string
		want bool
	}{
		{"a", "b", true},
		{"", "b", false}, // draw
		{"a", "", false},
		{"a", "a", false},
		{config.SystemAIUserID, "b", false},
		{"a", config.SystemAIUserID, false},
	}
	for _, c := range cases {
		if got := service.IsRatedPair(c.w, c.l); got != c.want {
			t.Errorf("IsRatedPair(%q,%q) = %v", c.w, c.l, got)
		}
	}
}

// ---- RatingService against Postgres ----

const (
	rUserA = "aaaaaaaa-0000-0000-0000-0000000000a1"
	rUserB = "bbbbbbbb-0000-0000-0000-0000000000b2"
	rUserC = "cccccccc-0000-0000-0000-0000000000c3"
)

type fakeWeeklyBoard struct {
	mu    sync.Mutex
	calls []string
}

func (f *fakeWeeklyBoard) RecordRatedGame(_ context.Context, w, l string, dw, dl int) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, fmt.Sprintf("%s:%d,%s:%d", w, dw, l, dl))
	return nil
}

func (f *fakeWeeklyBoard) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.calls)
}

type ratingEnv struct {
	db    *sql.DB
	svc   *service.RatingService
	board *fakeWeeklyBoard
	n     int
}

func newRatingEnv(t *testing.T) *ratingEnv {
	t.Helper()
	db := testutil.NewPostgres(t)
	if _, err := db.Exec(`INSERT INTO users (id, phone, username, phone_verified_at, created_at) VALUES
		($1,'09150000001','ali',now(), now() - interval '3 days'),
		($2,'09150000002','sara',now(), now() - interval '2 days'),
		($3,'09150000003','reza',now(), now() - interval '1 day')`, rUserA, rUserB, rUserC); err != nil {
		t.Fatal(err)
	}
	board := &fakeWeeklyBoard{}
	return &ratingEnv{db: db, svc: service.NewRatingService(repository.NewRatingRepository(db), board), board: board}
}

// match inserts a finished classic match row and returns its id.
func (e *ratingEnv) match(t *testing.T) string {
	t.Helper()
	e.n++
	id := fmt.Sprintf("20000000-0000-0000-0000-%012d", e.n)
	if _, err := e.db.Exec(`INSERT INTO matches (id, mode, status) VALUES ($1,'classic','finished')`, id); err != nil {
		t.Fatal(err)
	}
	return id
}

func (e *ratingEnv) stats(t *testing.T, id string) (rating, games, peak int) {
	t.Helper()
	if err := e.db.QueryRow(`SELECT rating, rated_games, peak_rating FROM player_stats WHERE user_id=$1`, id).
		Scan(&rating, &games, &peak); err != nil {
		t.Fatal(err)
	}
	return
}

func (e *ratingEnv) historyRows(t *testing.T) int {
	t.Helper()
	var n int
	if err := e.db.QueryRow(`SELECT count(*) FROM rating_history`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestRating_ApplyUpdatesBothPlayers(t *testing.T) {
	e := newRatingEnv(t)
	ctx := context.Background()
	m := e.match(t)

	res, err := e.svc.ApplyMatchResult(ctx, m, rUserA, rUserB)
	if err != nil {
		t.Fatal(err)
	}
	if !res.Rated || res.Reason != "" {
		t.Fatalf("want rated, got %+v", res)
	}
	if c := res.Changes[rUserA]; c.Before != 1000 || c.After != 1016 || c.Delta != 16 {
		t.Fatalf("winner change %+v", c)
	}
	if c := res.Changes[rUserB]; c.Before != 1000 || c.After != 984 || c.Delta != -16 {
		t.Fatalf("loser change %+v", c)
	}
	if r, g, p := e.stats(t, rUserA); r != 1016 || g != 1 || p != 1016 {
		t.Fatalf("winner stats %d/%d/%d", r, g, p)
	}
	if r, g, p := e.stats(t, rUserB); r != 984 || g != 1 || p != 1000 {
		t.Fatalf("loser stats %d/%d/%d (peak must not drop)", r, g, p)
	}
	if e.historyRows(t) != 2 {
		t.Fatal("want 2 history rows")
	}
	var opp string
	if err := e.db.QueryRow(`SELECT opponent_id FROM rating_history WHERE match_id=$1 AND user_id=$2`, m, rUserB).Scan(&opp); err != nil || opp != rUserA {
		t.Fatalf("loser's opponent = %q, %v", opp, err)
	}
	if e.board.count() != 1 || e.board.calls[0] != rUserA+":16,"+rUserB+":-16" {
		t.Fatalf("weekly board calls %v", e.board.calls)
	}
}

func TestRating_ReplayIsNoop(t *testing.T) {
	e := newRatingEnv(t)
	ctx := context.Background()
	m := e.match(t)
	first, err := e.svc.ApplyMatchResult(ctx, m, rUserA, rUserB)
	if err != nil {
		t.Fatal(err)
	}
	again, err := e.svc.ApplyMatchResult(ctx, m, rUserA, rUserB)
	if err != nil {
		t.Fatal(err)
	}
	if !again.Rated || again.Changes[rUserA] != first.Changes[rUserA] || again.Changes[rUserB] != first.Changes[rUserB] {
		t.Fatalf("replay must return the stored result: %+v vs %+v", again, first)
	}
	if r, g, _ := e.stats(t, rUserA); r != 1016 || g != 1 {
		t.Fatalf("replay changed stats: %d/%d", r, g)
	}
	if e.historyRows(t) != 2 || e.board.count() != 1 {
		t.Fatalf("replay wrote again: rows=%d board=%d", e.historyRows(t), e.board.count())
	}
}

func TestRating_ConcurrentApplyOnce(t *testing.T) {
	e := newRatingEnv(t)
	m := e.match(t)
	var wg sync.WaitGroup
	errs := make(chan error, 4)
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := e.svc.ApplyMatchResult(context.Background(), m, rUserA, rUserB)
			errs <- err
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if r, g, _ := e.stats(t, rUserA); r != 1016 || g != 1 {
		t.Fatalf("applied more than once: %d/%d", r, g)
	}
	if e.board.count() != 1 {
		t.Fatalf("board fed %d times", e.board.count())
	}
}

func TestRating_PairCapPerIranDay(t *testing.T) {
	e := newRatingEnv(t)
	ctx := context.Background()
	// 23:00 Iran time; the next Iran day starts one hour later.
	now := time.Date(2026, 11, 10, 23, 0, 0, 0, config.IranLocation)
	e.svc.SetNow(func() time.Time { return now })
	// History rows get the DB clock (now()); pin each one to the test clock so
	// the cap's Iran-day window sees it.
	play := func(w, l string) *service.MatchRating {
		t.Helper()
		m := e.match(t)
		res, err := e.svc.ApplyMatchResult(ctx, m, w, l)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := e.db.Exec(`UPDATE rating_history SET created_at = $2 WHERE match_id = $1`, m, now.Add(-time.Minute)); err != nil {
			t.Fatal(err)
		}
		return res
	}

	// Three games count, whoever wins them.
	for _, wl := range [][2]string{{rUserA, rUserB}, {rUserB, rUserA}, {rUserA, rUserB}} {
		if res := play(wl[0], wl[1]); !res.Rated {
			t.Fatalf("game should be rated: %+v", res)
		}
	}
	ratingA, gamesA, _ := e.stats(t, rUserA)

	res := play(rUserB, rUserA)
	if res.Rated || res.Reason != service.RatingReasonPairCap {
		t.Fatalf("4th game of the day must be capped: %+v", res)
	}
	if c := res.Changes[rUserA]; c.Before != ratingA || c.After != ratingA || c.Delta != 0 {
		t.Fatalf("capped change %+v (rating %d)", c, ratingA)
	}
	if r, g, _ := e.stats(t, rUserA); r != ratingA || g != gamesA {
		t.Fatalf("capped game changed stats %d/%d", r, g)
	}
	if e.historyRows(t) != 6 || e.board.count() != 3 {
		t.Fatalf("capped game was recorded: rows=%d board=%d", e.historyRows(t), e.board.count())
	}
	// The cap is per pair: A vs C still counts the same day.
	if res := play(rUserA, rUserC); !res.Rated {
		t.Fatalf("other pair must be rated: %+v", res)
	}
	// 01:00 the next Iran day: the pair counts again.
	now = now.Add(2 * time.Hour)
	if res := play(rUserB, rUserA); !res.Rated {
		t.Fatalf("a new Iran day resets the cap: %+v", res)
	}
}

func TestRating_DrawAndAIAreUnrated(t *testing.T) {
	e := newRatingEnv(t)
	ctx := context.Background()
	for _, wl := range [][2]string{{"", rUserB}, {rUserA, ""}, {config.SystemAIUserID, rUserA}, {rUserA, config.SystemAIUserID}} {
		res, err := e.svc.ApplyMatchResult(ctx, e.match(t), wl[0], wl[1])
		if err != nil || res != nil {
			t.Fatalf("%v: want nil result, got %+v %v", wl, res, err)
		}
	}
	if e.historyRows(t) != 0 || e.board.count() != 0 {
		t.Fatal("unrated matches wrote something")
	}
}

func TestRating_StableKAndFloor(t *testing.T) {
	e := newRatingEnv(t)
	ctx := context.Background()
	if _, err := e.db.Exec(`INSERT INTO player_stats (user_id, rating, rated_games, peak_rating) VALUES
		($1, 1000, 30, 1100), ($2, 5, 2, 1000), ($3, 1000, 0, 1000)`, rUserA, rUserB, rUserC); err != nil {
		t.Fatal(err)
	}
	// A has 30 rated games (K 16), C has none (K 32).
	res, err := e.svc.ApplyMatchResult(ctx, e.match(t), rUserA, rUserC)
	if err != nil {
		t.Fatal(err)
	}
	if res.Changes[rUserA].Delta != 8 || res.Changes[rUserC].Delta != -16 {
		t.Fatalf("K per player: %+v", res.Changes)
	}
	if _, _, p := e.stats(t, rUserA); p != 1100 {
		t.Fatalf("peak dropped to %d", p)
	}

	// B (5) loses to an evenly rated player: −16 would go below 0.
	if _, err := e.db.Exec(`UPDATE player_stats SET rating = 8 WHERE user_id = $1`, rUserC); err != nil {
		t.Fatal(err)
	}
	res, err = e.svc.ApplyMatchResult(ctx, e.match(t), rUserC, rUserB)
	if err != nil {
		t.Fatal(err)
	}
	if c := res.Changes[rUserB]; c.After != 0 || c.Delta != -5 {
		t.Fatalf("floor: %+v", c)
	}
}

func TestRating_RatingsOfDefaultsToStart(t *testing.T) {
	e := newRatingEnv(t)
	ctx := context.Background()
	if _, err := e.svc.ApplyMatchResult(ctx, e.match(t), rUserA, rUserB); err != nil {
		t.Fatal(err)
	}
	got, err := e.svc.RatingsOf(ctx, []string{rUserA, rUserB, rUserC})
	if err != nil {
		t.Fatal(err)
	}
	if got[rUserA] != 1016 || got[rUserB] != 984 || got[rUserC] != config.RatingStart {
		t.Fatalf("ratings %v", got)
	}
}
