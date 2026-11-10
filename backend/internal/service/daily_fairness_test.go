package service_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

// Phase 25 S5: prizes, the board and the rank use the free attempt only; a
// paid retry is a personal best and nothing more.
func TestDailyRankingUsesFreeAttemptOnly(t *testing.T) {
	db := testutil.NewPostgres(t)
	ctx := context.Background()
	date := config.IranDate(time.Now()).AddDate(0, 0, -1)
	const (
		a = "41000000-0000-0000-0000-000000000001" // low free run, huge paid retry
		b = "41000000-0000-0000-0000-000000000002"
		c = "41000000-0000-0000-0000-000000000003"
	)
	if _, err := db.Exec(`INSERT INTO users (id, phone, username, phone_verified_at) VALUES
		($1,'09180000001','alice',now()), ($2,'09180000002','bob',now()), ($3,'09180000003','cara',now())`, a, b, c); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO daily_challenges (challenge_date, seed, start_letter) VALUES ($1, 1, 'س')`, date); err != nil {
		t.Fatal(err)
	}
	dailyRepo := repository.NewDailyRepository(db)
	for _, at := range []struct {
		user    string
		attempt int
		score   int
	}{{a, 1, 100}, {a, 2, 900}, {b, 1, 300}, {c, 1, 200}, {c, 2, 250}} {
		if err := dailyRepo.InsertAttempt(ctx, at.user, date, at.attempt, at.score, []string{"سلام"}); err != nil {
			t.Fatal(err)
		}
	}

	board, err := dailyRepo.GetDailyLeaderboard(ctx, date, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(board) != 3 || board[0].UserID != b || board[1].UserID != c || board[2].UserID != a {
		t.Fatalf("board order: %+v", board)
	}
	if board[2].Score != 100 || board[2].Rank != 3 {
		t.Fatalf("a paid retry leaked into the board: %+v", board[2])
	}
	if rank, _ := dailyRepo.GetUserRank(ctx, date, a); rank == nil || *rank != 3 {
		t.Fatalf("alice rank = %v, want 3", rank)
	}
	if best, _ := dailyRepo.GetTodayBest(ctx, date); best != 300 {
		t.Fatalf("today best = %d, want 300 (free attempts only)", best)
	}

	// Payout: bob/cara/alice take the three rank prizes; the 900-point retry buys nothing.
	userRepo := repository.NewUserRepository(db)
	notif := service.NewNotificationService(&config.Config{}, repository.NewNotificationRepository(db))
	daily, err := service.NewDailyService(dailyRepo, repository.NewStatsRepository(db), userRepo, notif,
		&config.Config{GameEpochDate: "2025-01-01"})
	if err != nil {
		t.Fatal(err)
	}
	if err := daily.RunDailyPayout(ctx, date); err != nil {
		t.Fatal(err)
	}
	wantCoins := map[string]int{b: config.CoinDailyRank1, c: config.CoinDailyRank2, a: config.CoinDailyRank3}
	for user, coins := range wantCoins {
		var got int
		if err := db.QueryRow(`SELECT coins FROM inbox_rewards WHERE user_id=$1 AND kind='daily_rank'`, user).Scan(&got); err != nil {
			t.Fatalf("rank reward of %s: %v", user, err)
		}
		if got != coins {
			t.Errorf("rank reward of %s = %d, want %d", user, got, coins)
		}
	}
	var done int
	if err := db.QueryRow(`SELECT count(*) FROM inbox_rewards WHERE kind='daily_done'`).Scan(&done); err != nil || done != 3 {
		t.Fatalf("daily_done rewards = %d (%v), want 3", done, err)
	}
}

// A retry that outscores the free run still posts the personal best.
func TestDailyInfoKeepsPersonalBestButFreeRank(t *testing.T) {
	db := testutil.NewPostgres(t)
	ctx := context.Background()
	today := config.IranDate(time.Now())
	const (
		a = "42000000-0000-0000-0000-000000000001"
		b = "42000000-0000-0000-0000-000000000002"
	)
	if _, err := db.Exec(`INSERT INTO users (id, phone, username, phone_verified_at) VALUES
		($1,'09190000001','alice',now()), ($2,'09190000002','bob',now())`, a, b); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO daily_challenges (challenge_date, seed, start_letter) VALUES ($1, 1, 'س')`, today); err != nil {
		t.Fatal(err)
	}
	dailyRepo := repository.NewDailyRepository(db)
	for _, at := range []struct {
		user    string
		attempt int
		score   int
	}{{a, 1, 100}, {a, 2, 900}, {b, 1, 300}} {
		if err := dailyRepo.InsertAttempt(ctx, at.user, today, at.attempt, at.score, []string{"سلام"}); err != nil {
			t.Fatal(err)
		}
	}
	daily, err := service.NewDailyService(dailyRepo, repository.NewStatsRepository(db), repository.NewUserRepository(db),
		service.NewNotificationService(&config.Config{}, repository.NewNotificationRepository(db)), &config.Config{GameEpochDate: "2025-01-01"})
	if err != nil {
		t.Fatal(err)
	}
	info, err := daily.GetDailyInfo(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	if info.YourBest != 900 || info.Rank == nil || *info.Rank != 2 || info.TodayBest != 300 {
		t.Fatalf("info = best %d rank %v today %d, want 900 / 2 / 300", info.YourBest, info.Rank, info.TodayBest)
	}
}

// POST /game/solo for a Daily run: with a trace the score is recomputed.
func TestCreateSoloGameDailyRecomputesScore(t *testing.T) {
	db := testutil.NewPostgres(t)
	ctx := context.Background()
	const (
		user    = "43000000-0000-0000-0000-000000000001"
		oldUser = "43000000-0000-0000-0000-000000000002"
	)
	if _, err := db.Exec(`INSERT INTO users (id, phone, username, phone_verified_at) VALUES
		($1,'09150000001','alice',now()), ($2,'09150000002','olduser',now())`, user, oldUser); err != nil {
		t.Fatal(err)
	}
	started := time.Now().UTC().Truncate(time.Second)
	date := config.IranDate(started)
	if _, err := db.Exec(`INSERT INTO daily_challenges (challenge_date, seed, start_letter) VALUES ($1, 1, 'س')`, date); err != nil {
		t.Fatal(err)
	}
	dailyRepo := repository.NewDailyRepository(db)
	svc := service.NewGameService(repository.NewMatchRepository(db), repository.NewStatsRepository(db), nil, dailyRepo)

	chain := dailyChain(t, "س", 4)
	times := []int{3000, 4500, 2000, 9000}
	streaks := []int{0, 1, 0, 1} // a life was lost before the third word
	score := 0
	for i, w := range chain {
		score += engine.CalculateScore(w, float64(times[i])/1000, streaks[i], config.TurnTimerClassicSec)
	}
	in := func(offset time.Duration, score int, t, s []int) service.SoloGameInput {
		return service.SoloGameInput{Mode: "daily", Score: score, WordChain: chain,
			StartedAt: started.Add(offset), EndedAt: started.Add(offset + time.Minute), WordTimesMs: t, WordStreaks: s}
	}

	// A score one point off is refused and leaves no attempt behind.
	if _, _, err := svc.CreateSoloGame(ctx, user, in(0, score+1, times, streaks)); !errors.Is(err, service.ErrInvalidDailyChain) {
		t.Fatalf("mismatch: want ErrInvalidDailyChain, got %v", err)
	}
	// A trace with only one half is malformed.
	if _, _, err := svc.CreateSoloGame(ctx, user, in(0, score, times, nil)); !errors.Is(err, service.ErrInvalidDailyChain) {
		t.Fatalf("half a trace: want ErrInvalidDailyChain, got %v", err)
	}
	attempts, _ := dailyRepo.GetUserAttempts(ctx, user, date)
	if len(attempts) != 0 {
		t.Fatalf("a rejected run stored %d attempts", len(attempts))
	}

	// The exact score is accepted and the trace is kept with the match.
	m, existed, err := svc.CreateSoloGame(ctx, user, in(0, score, times, streaks))
	if err != nil || existed {
		t.Fatalf("exact trace: %v (existed %v)", err, existed)
	}
	var state string
	if err := db.QueryRow(`SELECT game_state::text FROM matches WHERE id=$1`, m.ID).Scan(&state); err != nil || !strings.Contains(state, "word_times_ms") {
		t.Fatalf("trace not stored: %q (%v)", state, err)
	}

	// An older app sends no trace: only the upper bound applies, so a score
	// the formula could not give but the bound allows still goes through.
	loose := score - 7
	if _, _, err := svc.CreateSoloGame(ctx, oldUser, in(0, loose, nil, nil)); err != nil {
		t.Fatalf("no trace (old app): %v", err)
	}

	// An app installed before S6 scored long words with the old ×2 rule and
	// uploads a trace computed that way: still accepted, on a day of its own
	// (this player has no attempt yet).
	const legacyUser = "43000000-0000-0000-0000-000000000003"
	if _, err := db.Exec(`INSERT INTO users (id, phone, username, phone_verified_at) VALUES ($1,'09150000003','legacy',now())`, legacyUser); err != nil {
		t.Fatal(err)
	}
	legacyChain := []string{"دانشگاه", "هواپیما", "اتوبوس"}
	lt, ls := []int{3000, 4000, 5000}, []int{0, 1, 2}
	legacyScore, newScore := 0, 0
	for i, w := range legacyChain {
		sec := float64(lt[i]) / 1000
		newScore += engine.CalculateScore(w, sec, ls[i], config.TurnTimerClassicSec)
		legacyScore += (engine.CalculateScore(w, sec, ls[i], config.TurnTimerClassicSec) - engine.LongWordBonus(engine.LetterCount(w)))
		if engine.LetterCount(w) >= 7 {
			legacyScore += engine.CalculateScore(w, sec, ls[i], config.TurnTimerClassicSec) - engine.LongWordBonus(engine.LetterCount(w))
		}
	}
	if legacyScore == newScore {
		t.Fatal("test is vacuous: both formulas agree")
	}
	legacyIn := service.SoloGameInput{Mode: "daily", Score: legacyScore, WordChain: legacyChain,
		StartedAt: started, EndedAt: started.Add(time.Minute), WordTimesMs: lt, WordStreaks: ls}
	// The chain starts with د, not the day's letter, so it needs its own day.
	if _, err := db.Exec(`UPDATE daily_challenges SET start_letter='د' WHERE challenge_date=$1`, date); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.CreateSoloGame(ctx, legacyUser, legacyIn); err != nil {
		t.Fatalf("old-formula trace (app from before S6): %v", err)
	}
}

func dailyChain(t *testing.T, start string, n int) []string {
	t.Helper()
	used := map[string]bool{}
	letter := []rune(start)[0]
	var chain []string
	for len(chain) < n {
		w := engine.SuggestWord(letter, used)
		if w == "" {
			t.Fatal("dictionary ran out")
		}
		used[w] = true
		chain = append(chain, w)
		letter = engine.LastLetter(w)
	}
	return chain
}
