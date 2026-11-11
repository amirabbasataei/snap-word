package service_test

import (
	"bufio"
	"context"
	"errors"
	"os"
	"sort"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

// variantChain walks fa.txt (sorted, words of 3+ letters) for n words linked
// on letter position pos, the first one carrying start there.
func variantChain(t *testing.T, start string, pos, n int) []string {
	t.Helper()
	f, err := os.Open("../engine/data/fa.txt")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var words []string
	for sc := bufio.NewScanner(f); sc.Scan(); {
		if w := sc.Text(); engine.LetterCount(w) >= 3 {
			words = append(words, w)
		}
	}
	sort.Strings(words)
	used := map[string]bool{}
	letter := []rune(start)[0]
	var chain []string
	for len(chain) < n {
		next := ""
		for _, w := range words {
			if !used[w] && engine.LetterAt(w, pos) == letter {
				next = w
				break
			}
		}
		if next == "" {
			t.Fatal("dictionary ran out")
		}
		used[next] = true
		chain = append(chain, next)
		letter = engine.LastLetter(next)
	}
	return chain
}

// Each Daily variant is its own daily: its own free attempt, retry, board,
// rank and prizes, all on the same day's challenge row.
func TestDailyVariantsAreSeparateDailies(t *testing.T) {
	db := testutil.NewPostgres(t)
	ctx := context.Background()
	const (
		a = "44000000-0000-0000-0000-000000000001"
		b = "44000000-0000-0000-0000-000000000002"
	)
	if _, err := db.Exec(`INSERT INTO users (id, phone, username, phone_verified_at, coins) VALUES
		($1,'09170000001','alice',now(),100), ($2,'09170000002','bob',now(),100)`, a, b); err != nil {
		t.Fatal(err)
	}
	started := time.Now().UTC().Truncate(time.Second)
	date := config.IranDate(started)
	if _, err := db.Exec(`INSERT INTO daily_challenges (challenge_date, seed, start_letter) VALUES ($1, 1, 'ن')`, date); err != nil {
		t.Fatal(err)
	}
	dailyRepo := repository.NewDailyRepository(db)
	game := service.NewGameService(repository.NewMatchRepository(db), repository.NewStatsRepository(db), nil, dailyRepo)
	daily, err := service.NewDailyService(dailyRepo, repository.NewStatsRepository(db), repository.NewUserRepository(db),
		service.NewNotificationService(&config.Config{}, repository.NewNotificationRepository(db)), &config.Config{GameEpochDate: "2025-01-01"})
	if err != nil {
		t.Fatal(err)
	}

	// run uploads a Daily run of the variant with an exact trace (4 s a word).
	run := func(user string, variant int, chain []string, offset time.Duration) error {
		timer := float64(config.DailyTurnTimerSec(variant))
		times, streaks, score := make([]int, len(chain)), make([]int, len(chain)), 0
		for i, w := range chain {
			times[i], streaks[i] = 4000, i
			score += engine.CalculateScore(w, 4, i, timer)
		}
		_, _, err := game.CreateSoloGame(ctx, user, service.SoloGameInput{Mode: "daily", Score: score, WordChain: chain,
			StartedAt: started.Add(offset), EndedAt: started.Add(offset + time.Minute),
			WordTimesMs: times, WordStreaks: streaks, DailyVariant: variant})
		return err
	}

	classic := dailyChain(t, "ن", 5)
	second := variantChain(t, "ن", 2, 6)
	third := variantChain(t, "ن", 3, 3)

	if err := run(a, 2, second, 0); err != nil {
		t.Fatalf("variant 2 run: %v", err)
	}
	// The classic daily is still open after the 2nd-letter one.
	if err := run(a, 1, classic, time.Second); err != nil {
		t.Fatalf("classic run after variant 2: %v", err)
	}
	if err := run(b, 2, second[:3], 2*time.Second); err != nil {
		t.Fatalf("bob variant 2: %v", err)
	}
	// A second free run of the same variant is refused.
	if err := run(a, 2, second[:2], 3*time.Second); !errors.Is(err, service.ErrDailyNotAllowed) {
		t.Fatalf("second variant-2 run: want ErrDailyNotAllowed, got %v", err)
	}
	// A classic chain is not a 2nd-letter chain, an unknown variant is refused.
	if err := run(b, 3, classic, 4*time.Second); !errors.Is(err, service.ErrInvalidDailyChain) {
		t.Fatalf("classic chain as variant 3: want ErrInvalidDailyChain, got %v", err)
	}
	if err := run(b, 4, classic, 5*time.Second); !errors.Is(err, service.ErrInvalidDailyChain) {
		t.Fatalf("variant 4: want ErrInvalidDailyChain, got %v", err)
	}
	if err := run(b, 3, third, 4500*time.Millisecond); err != nil {
		t.Fatalf("bob variant 3: %v", err)
	}
	// An old app sends no variant: it is the classic daily.
	if err := run(b, 0, classic[:2], 6*time.Second); err != nil {
		t.Fatalf("no variant (old app): %v", err)
	}

	info1, err := daily.GetDailyInfo(ctx, a, 1)
	if err != nil {
		t.Fatal(err)
	}
	info2, err := daily.GetDailyInfo(ctx, a, 2)
	if err != nil {
		t.Fatal(err)
	}
	info3, err := daily.GetDailyInfo(ctx, a, 3)
	if err != nil {
		t.Fatal(err)
	}
	if info1.Attempt == nil || len(info1.Attempt.WordChain) != len(classic) {
		t.Fatalf("classic attempt = %+v", info1.Attempt)
	}
	if info2.Attempt == nil || len(info2.Attempt.WordChain) != len(second) {
		t.Fatalf("variant 2 attempt = %+v", info2.Attempt)
	}
	if info3.Attempt != nil || info3.Rank != nil {
		t.Fatalf("variant 3 has an attempt: %+v", info3.Attempt)
	}
	if got := info3.PlayedVariants; len(got) != 2 || got[0] != 1 || got[1] != 2 {
		t.Fatalf("played variants = %v, want [1 2]", got)
	}
	if info2.TurnTimerSec != 20 || info3.TurnTimerSec != 25 || info1.TurnTimerSec != config.TurnTimerClassicSec {
		t.Fatalf("timers = %d / %d / %d", info1.TurnTimerSec, info2.TurnTimerSec, info3.TurnTimerSec)
	}
	if info2.Rank == nil || *info2.Rank != 1 || info1.Rank == nil {
		t.Fatalf("ranks: classic %v, variant 2 %v", info1.Rank, info2.Rank)
	}

	// Each board holds its own variant only.
	board2, err := daily.Leaderboard(ctx, a, 2, 10)
	if err != nil || len(board2.Entries) != 2 || board2.Entries[0].UserID != a {
		t.Fatalf("variant 2 board = %+v (%v)", board2, err)
	}
	board3, _ := daily.Leaderboard(ctx, a, 3, 10)
	if len(board3.Entries) != 1 || board3.Entries[0].UserID != b || board3.MyRank != nil {
		t.Fatalf("variant 3 board = %+v", board3)
	}

	// Retries are per variant.
	if err := daily.Retry(ctx, a, 3); !errors.Is(err, service.ErrDailyNotAttempted) {
		t.Fatalf("retry of an unplayed variant: want ErrDailyNotAttempted, got %v", err)
	}
	if err := daily.Retry(ctx, a, 2); err != nil {
		t.Fatalf("variant 2 retry: %v", err)
	}
	if ok, _ := dailyRepo.HasRetry(ctx, a, date, 1); ok {
		t.Fatal("the variant 2 retry unlocked the classic retry")
	}
	if err := run(a, 2, second[:2], 7*time.Second); err != nil {
		t.Fatalf("paid variant 2 run: %v", err)
	}

	// Prizes per variant: alice finished two variants and tops variant 2.
	if err := daily.RunDailyPayout(ctx, date); err != nil {
		t.Fatal(err)
	}
	rows, err := db.Query(`SELECT kind, ref FROM inbox_rewards WHERE user_id=$1 ORDER BY kind, ref`, a)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var got []string
	for rows.Next() {
		var kind, ref string
		if err := rows.Scan(&kind, &ref); err != nil {
			t.Fatal(err)
		}
		got = append(got, kind+" "+ref)
	}
	d := date.Format("2006-01-02")
	want := []string{"daily_done " + d, "daily_done " + d + "/v2", "daily_rank " + d, "daily_rank " + d + "/v2"}
	if len(got) != len(want) {
		t.Fatalf("rewards = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("rewards = %v, want %v", got, want)
		}
	}
	// Re-running pays nothing twice.
	if err := daily.RunDailyPayout(ctx, date); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := db.QueryRow(`SELECT count(*) FROM inbox_rewards WHERE user_id=$1`, a).Scan(&n); err != nil || n != 4 {
		t.Fatalf("after re-run alice has %d rewards (%v)", n, err)
	}
}
