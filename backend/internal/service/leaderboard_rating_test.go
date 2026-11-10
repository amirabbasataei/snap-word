package service_test

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

func TestWeeklyPrizeWinners(t *testing.T) {
	e := func(id string, score float64, games int) service.LeaderboardEntry {
		return service.LeaderboardEntry{UserID: id, Score: score, Games: games}
	}
	board := []service.LeaderboardEntry{
		e("few-games", 90, 4), // positive but < 5 rated games
		e("first", 60, 5),
		e("second", 40, 12),
		e("third", 1, 5),
		e("fourth", 1, 9),
		e("zero", 0, 20),
	}
	got := service.WeeklyPrizeWinners(board, 3)
	want := []string{"first", "second", "third"}
	if len(got) != 3 {
		t.Fatalf("got %d winners", len(got))
	}
	for i, w := range want {
		if got[i].UserID != w || got[i].Rank != i+1 {
			t.Fatalf("winner %d = %+v, want %s rank %d", i, got[i], w, i+1)
		}
	}
	if n := len(service.WeeklyPrizeWinners([]service.LeaderboardEntry{e("neg", -3, 10), e("zero", 0, 10)}, 3)); n != 0 {
		t.Fatalf("a non-positive week never wins a prize, got %d", n)
	}
}

const (
	lbA      = "aaaaaaaa-1111-0000-0000-0000000000a1"
	lbB      = "bbbbbbbb-1111-0000-0000-0000000000b2"
	lbC      = "cccccccc-1111-0000-0000-0000000000c3"
	lbD      = "dddddddd-1111-0000-0000-0000000000d4"
	lbBanned = "eeeeeeee-1111-0000-0000-0000000000e5"
)

func newBoardEnv(t *testing.T) (*service.LeaderboardService, *redis.Client, *sql.DB) {
	t.Helper()
	db := testutil.NewPostgres(t)
	_, rdb := testutil.NewRedis(t)
	if _, err := db.Exec(`INSERT INTO users (id, phone, username, phone_verified_at, created_at, banned_at) VALUES
		($1,'09160000001','ali',now(), now() - interval '5 days', NULL),
		($2,'09160000002','sara',now(), now() - interval '4 days', NULL),
		($3,'09160000003','reza',now(), now() - interval '3 days', NULL),
		($4,'09160000004','mina',now(), now() - interval '2 days', NULL),
		($5,'09160000005','cheat',now(), now() - interval '1 day', now())`,
		lbA, lbB, lbC, lbD, lbBanned); err != nil {
		t.Fatal(err)
	}
	svc := service.NewLeaderboardService(rdb, repository.NewUserRepository(db), repository.NewFriendshipRepository(db),
		repository.NewLeaderboardRepository(db), repository.NewRatingRepository(db),
		service.NewNotificationService(&config.Config{}, repository.NewNotificationRepository(db)))
	return svc, rdb, db
}

func TestWeeklyBoard_OrderTieBreakAndStanding(t *testing.T) {
	svc, rdb, _ := newBoardEnv(t)
	ctx := context.Background()
	rec := func(w, l string, dw, dl int) {
		t.Helper()
		if err := svc.RecordRatedGame(ctx, w, l, dw, dl); err != nil {
			t.Fatal(err)
		}
	}
	// A: +16 +16 −16 = +16 (2 wins, 3 games); B: −16 +16 = 0 (1 win);
	// C: +16 (1 win, 1 game), ties A on Δ with fewer wins; D: −16 −16 = −32.
	rec(lbA, lbB, 16, -16)
	rec(lbA, lbD, 16, -16)
	rec(lbB, lbA, 16, -16)
	rec(lbC, lbD, 16, -16)
	rec(lbBanned, lbD, 50, 0) // banned: dropped on read, still in Redis

	top, err := svc.GetTopN(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	want := []struct {
		id          string
		score       float64
		wins, games int
	}{{lbA, 16, 2, 3}, {lbC, 16, 1, 1}, {lbB, 0, 1, 2}, {lbD, -32, 0, 3}}
	if len(top) != len(want) {
		t.Fatalf("board %+v", top)
	}
	for i, w := range want {
		e := top[i]
		if e.UserID != w.id || e.Score != w.score || e.Wins == nil || *e.Wins != w.wins || e.Games != w.games || e.Rank != i+1 {
			t.Fatalf("row %d = %+v (wins %v), want %+v", i, e, e.Wins, w)
		}
	}
	if top[0].Username != "ali" {
		t.Fatalf("username %q", top[0].Username)
	}

	stA, err := svc.WeeklyStanding(ctx, lbA)
	if err != nil {
		t.Fatal(err)
	}
	// The banned player's +50 is still above A in Redis (rank counts it, as before S2).
	if stA.Rank != 2 || stA.Score != 16 || stA.Wins != 2 || stA.Games != 3 {
		t.Fatalf("standing A %+v", stA)
	}
	stC, _ := svc.WeeklyStanding(ctx, lbC)
	if stC.Rank != 3 {
		t.Fatalf("C ties A on Δ with fewer wins: rank %d", stC.Rank)
	}
	stNone, _ := svc.WeeklyStanding(ctx, "ffffffff-0000-0000-0000-000000000000")
	if stNone != (service.PlayerStanding{}) {
		t.Fatalf("no game this week: %+v", stNone)
	}

	// The legacy word-points key is never written.
	if n, _ := rdb.Exists(ctx, "leaderboard:global:weekly").Result(); n != 0 {
		t.Fatal("legacy key written")
	}
}

func TestWeeklyReset_PaysEligibleOnlyAndClears(t *testing.T) {
	svc, rdb, db := newBoardEnv(t)
	ctx := context.Background()
	rec := func(w, l string, times int) {
		for i := 0; i < times; i++ {
			if err := svc.RecordRatedGame(ctx, w, l, 16, -16); err != nil {
				t.Fatal(err)
			}
		}
	}
	rec(lbC, lbD, 4) // C: +64 in 4 games — the best week, but too few games
	rec(lbA, lbD, 3)
	rec(lbB, lbA, 1)
	rec(lbA, lbB, 1) // A: +48 in 5 games
	rec(lbB, lbD, 3)
	rec(lbD, lbB, 1)                                        // B: +32 in 6 games; D negative
	rdb.ZIncrBy(ctx, "leaderboard:global:weekly", 999, lbA) // left over from before S2

	week := time.Date(2026, 11, 7, 0, 0, 0, 0, time.UTC)
	svc.RunWeeklyReset(ctx, week)
	svc.RunWeeklyReset(ctx, week) // idempotent

	rows, err := db.Query(`SELECT user_id, rank, coins_awarded FROM weekly_leaderboard_rewards WHERE week_start = $1`, week)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	got := map[string][2]int{}
	for rows.Next() {
		var id string
		var rank, coins int
		if err := rows.Scan(&id, &rank, &coins); err != nil {
			t.Fatal(err)
		}
		got[id] = [2]int{rank, coins}
	}
	if len(got) != 2 || got[lbA] != [2]int{1, config.CoinWeeklyRank1} || got[lbB] != [2]int{2, config.CoinWeeklyRank2} {
		t.Fatalf("weekly rewards %v, want A 1st and B 2nd (C has only 4 games, D is negative)", got)
	}
	var inbox int
	if err := db.QueryRow(`SELECT count(*) FROM inbox_rewards WHERE kind = 'weekly_rank'`).Scan(&inbox); err != nil || inbox != 2 {
		t.Fatalf("inbox rewards %d, %v", inbox, err)
	}
	for _, k := range []string{"leaderboard:weekly:rating", "leaderboard:weekly:wins", "leaderboard:weekly:games", "leaderboard:global:weekly"} {
		if n, _ := rdb.Exists(ctx, k).Result(); n != 0 {
			t.Fatalf("%s not cleared", k)
		}
	}
}

func setRating(t *testing.T, db *sql.DB, id string, rating, games int) {
	t.Helper()
	if _, err := db.Exec(`INSERT INTO player_stats (user_id, rating, rated_games, peak_rating) VALUES ($1,$2,$3,$2)
		ON CONFLICT (user_id) DO UPDATE SET rating = $2, rated_games = $3, peak_rating = $2`, id, rating, games); err != nil {
		t.Fatal(err)
	}
}

func TestAllTimeBoard_RatingWithMinGames(t *testing.T) {
	svc, _, db := newBoardEnv(t)
	ctx := context.Background()
	setRating(t, db, lbA, 1100, config.RatingMinGamesForBoard)   // exactly the minimum
	setRating(t, db, lbB, 1100, 25)                              // same rating, more games → above A
	setRating(t, db, lbC, 1300, config.RatingMinGamesForBoard-1) // one game short of the board
	setRating(t, db, lbD, 950, 40)
	setRating(t, db, lbBanned, 2000, 50)
	setRating(t, db, config.SystemAIUserID, 3000, 999)

	top, err := svc.GetAllTimeTop(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{lbB, lbA, lbD}
	if len(top) != len(want) {
		t.Fatalf("board %+v", top)
	}
	for i, id := range want {
		if top[i].UserID != id || top[i].Rank != i+1 || top[i].Wins != nil {
			t.Fatalf("row %d = %+v, want %s", i, top[i], id)
		}
	}
	if top[0].Score != 1100 || top[0].Games != 25 {
		t.Fatalf("row 0 %+v", top[0])
	}

	if st, err := svc.AllTimeStanding(ctx, lbA); err != nil || st.Rank != 2 || st.Score != 1100 || st.Games != config.RatingMinGamesForBoard {
		t.Fatalf("standing A %+v %v", st, err)
	}
	// Not on the board yet: rank 0, but rating and games are reported.
	if st, _ := svc.AllTimeStanding(ctx, lbC); st.Rank != 0 || st.Score != 1300 || st.Games != config.RatingMinGamesForBoard-1 {
		t.Fatalf("standing C %+v", st)
	}
	if st, _ := svc.AllTimeStanding(ctx, lbBanned); st.Rank != 0 {
		t.Fatalf("banned standing %+v", st)
	}
	// No stats row at all: the start rating.
	if st, _ := svc.AllTimeStanding(ctx, "ffffffff-0000-0000-0000-000000000000"); st.Rank != 0 || st.Score != config.RatingStart {
		t.Fatalf("no-row standing %+v", st)
	}
}

func TestFriendsBoard_ByRating(t *testing.T) {
	svc, _, db := newBoardEnv(t)
	ctx := context.Background()
	if _, err := db.Exec(`INSERT INTO friendships (requester_id, addressee_id, status) VALUES
		($1,$2,'accepted'), ($3,$1,'accepted'), ($1,$4,'pending'), ($1,$5,'accepted')`,
		lbA, lbB, lbC, lbD, lbBanned); err != nil {
		t.Fatal(err)
	}
	setRating(t, db, lbA, 1040, 3)
	setRating(t, db, lbB, 1200, 30)
	setRating(t, db, lbD, 1500, 30)      // pending request: not a friend
	setRating(t, db, lbBanned, 1900, 30) // banned friend: hidden
	// C has no stats row → 1000.

	entries, me, err := svc.GetFriendsLeaderboard(ctx, lbA, 100)
	if err != nil {
		t.Fatal(err)
	}
	want := []struct {
		id     string
		rating float64
		games  int
	}{{lbB, 1200, 30}, {lbA, 1040, 3}, {lbC, 1000, 0}}
	if len(entries) != len(want) {
		t.Fatalf("friends board %+v", entries)
	}
	for i, w := range want {
		if entries[i].UserID != w.id || entries[i].Score != w.rating || entries[i].Games != w.games || entries[i].Rank != i+1 {
			t.Fatalf("row %d = %+v, want %+v", i, entries[i], w)
		}
	}
	if me.Rank != 2 || me.Score != 1040 || me.Games != 3 {
		t.Fatalf("own place among friends %+v", me)
	}
	if _, me, _ := svc.GetFriendsLeaderboard(ctx, lbA, 1); me.Rank != 2 {
		t.Fatalf("own rank must not depend on the limit: %+v", me)
	}
}
