package repository_test

import (
	"context"
	"errors"
	"testing"

	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/testutil"
)

const (
	wordUserA = "dddddddd-0000-4000-8000-00000000000a"
	wordUserB = "dddddddd-0000-4000-8000-00000000000b"
)

func TestWords_SubmitCountsDistinctReporters(t *testing.T) {
	db := testutil.NewPostgres(t)
	repo := repository.NewWordRepository(db)
	ctx := context.Background()
	for _, u := range []struct{ id, phone string }{{wordUserA, "09120000001"}, {wordUserB, "09120000002"}} {
		if _, err := db.Exec(`INSERT INTO users (id, phone) VALUES ($1, $2)`, u.id, u.phone); err != nil {
			t.Fatal(err)
		}
	}

	in := repository.WordReportInput{Word: "آزمونک", Kind: repository.WordKindAdd, ReporterKey: "i:" + installA, InstallID: installA}
	r, err := repo.SubmitReport(ctx, in)
	if err != nil || !r.Counted || r.Reporters != 1 || r.Status != repository.WordPending {
		t.Fatalf("first report = %+v, %v", r, err)
	}
	// The same reporter again is not counted twice.
	if r, err = repo.SubmitReport(ctx, in); err != nil || r.Counted || r.Reporters != 1 {
		t.Fatalf("repeat report = %+v, %v", r, err)
	}
	// A signed-in player and another guest add two more.
	in.ReporterKey, in.UserID = "u:"+wordUserA, wordUserA
	if r, _ = repo.SubmitReport(ctx, in); r.Reporters != 2 {
		t.Fatalf("after user report: %+v", r)
	}
	in.ReporterKey, in.UserID, in.InstallID = "i:"+installB, "", installB
	if r, _ = repo.SubmitReport(ctx, in); r.Reporters != 3 {
		t.Fatalf("after second guest: %+v", r)
	}

	items, total, err := repo.ListSuggestions(ctx, repository.WordListParams{Status: "pending", Limit: 10})
	if err != nil || total != 1 || items[0].Reporters != 3 {
		t.Fatalf("queue = %+v total=%d err=%v", items, total, err)
	}
}

func TestWords_ApproveAddRewardsFirstSignedInReporterOnce(t *testing.T) {
	db := testutil.NewPostgres(t)
	repo := repository.NewWordRepository(db)
	ctx := context.Background()
	for _, u := range []struct{ id, phone string }{{wordUserA, "09120000001"}, {wordUserB, "09120000002"}} {
		if _, err := db.Exec(`INSERT INTO users (id, phone) VALUES ($1, $2)`, u.id, u.phone); err != nil {
			t.Fatal(err)
		}
	}
	word := "آزمونک"
	report := func(key, uid, inst string) {
		t.Helper()
		if _, err := repo.SubmitReport(ctx, repository.WordReportInput{Word: word, Kind: repository.WordKindAdd, ReporterKey: key, UserID: uid, InstallID: inst}); err != nil {
			t.Fatal(err)
		}
	}
	report("i:"+installA, "", installA) // a guest reports first: no reward for them
	report("u:"+wordUserB, wordUserB, "")
	report("u:"+wordUserA, wordUserA, "")

	var id int64
	if err := db.QueryRow(`SELECT id FROM word_suggestions WHERE word = $1`, word).Scan(&id); err != nil {
		t.Fatal(err)
	}
	res, err := repo.ApproveSuggestion(ctx, id, "admin1", "ok", "", 25)
	if err != nil {
		t.Fatal(err)
	}
	if !res.RewardCreated || res.RewardUserID != wordUserB {
		t.Fatalf("reward = %+v; want the earliest signed-in reporter", res)
	}
	if !res.Override.Present || res.Override.Seq == 0 {
		t.Fatalf("override = %+v", res.Override)
	}
	var coins int
	var claimed bool
	if err := db.QueryRow(`SELECT coins, claimed_at IS NOT NULL FROM inbox_rewards WHERE user_id = $1 AND kind = 'word_suggestion' AND ref = $2`, wordUserB, word).Scan(&coins, &claimed); err != nil || coins != 25 || claimed {
		t.Fatalf("inbox reward = %d claimed=%v err=%v", coins, claimed, err)
	}

	// A second approval is refused; later reports of the word are refused too.
	if _, err := repo.ApproveSuggestion(ctx, id, "admin1", "", "", 25); !errors.Is(err, repository.ErrSuggestionNotPending) {
		t.Fatalf("second approve err = %v", err)
	}
	if _, err := repo.SubmitReport(ctx, repository.WordReportInput{Word: word, Kind: repository.WordKindAdd, ReporterKey: "u:" + wordUserA, UserID: wordUserA}); !errors.Is(err, repository.ErrSuggestionNotPending) {
		t.Fatalf("report after review err = %v", err)
	}

	mine, err := repo.MyReports(ctx, wordUserB, 10)
	if err != nil || len(mine) != 1 || mine[0].Status != "approved" || !mine[0].Rewarded {
		t.Fatalf("mine(B) = %+v err=%v", mine, err)
	}
	mine, _ = repo.MyReports(ctx, wordUserA, 10)
	if len(mine) != 1 || mine[0].Rewarded {
		t.Fatalf("mine(A) should show approved but unrewarded: %+v", mine)
	}

	ov, err := repo.LoadOverrides(ctx)
	if err != nil || len(ov) != 1 || ov[0].Word != word || !ov[0].Present {
		t.Fatalf("overrides = %+v err=%v", ov, err)
	}
}

func TestWords_RemovalOutcomesAndOverrideSemantics(t *testing.T) {
	db := testutil.NewPostgres(t)
	repo := repository.NewWordRepository(db)
	ctx := context.Background()

	submit := func(word string) int64 {
		t.Helper()
		if _, err := repo.SubmitReport(ctx, repository.WordReportInput{Word: word, Kind: repository.WordKindRemove,
			ReporterKey: "i:" + installA, InstallID: installA, Reason: "inappropriate"}); err != nil {
			t.Fatal(err)
		}
		var id int64
		if err := db.QueryRow(`SELECT id FROM word_suggestions WHERE word = $1 AND kind = 'remove'`, word).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}

	idBlock, idRemove := submit("بدکلمه"), submit("نکلمه")
	if _, err := repo.ApproveSuggestion(ctx, idBlock, "a", "", "", 25); !errors.Is(err, repository.ErrSuggestionOutcome) {
		t.Fatalf("removal without outcome err = %v", err)
	}
	ab, err := repo.ApproveSuggestion(ctx, idBlock, "a", "rare", repository.WordOutcomeAIBlock, 25)
	if err != nil || !ab.Override.Present || !ab.Override.AIBlocked || ab.RewardCreated {
		t.Fatalf("ai_block = %+v err=%v", ab, err)
	}
	rm, err := repo.ApproveSuggestion(ctx, idRemove, "a", "not a word", repository.WordOutcomeRemove, 25)
	if err != nil || rm.Override.Present || rm.Override.AIBlocked || rm.Override.Seq <= ab.Override.Seq {
		t.Fatalf("remove = %+v err=%v", rm, err)
	}

	// A re-add keeps an AI block; unblocking keeps presence; seq only grows.
	o1, _ := repo.SetOverride(ctx, "بدکلمه", repository.OverrideAdd)
	if !o1.Present || !o1.AIBlocked || o1.Seq <= rm.Override.Seq {
		t.Fatalf("re-add = %+v", o1)
	}
	o2, _ := repo.SetOverride(ctx, "بدکلمه", repository.OverrideAIUnblock)
	if !o2.Present || o2.AIBlocked || o2.Seq <= o1.Seq {
		t.Fatalf("unblock = %+v", o2)
	}
	o3, _ := repo.SetOverride(ctx, "تازه", repository.OverrideAIBlock)
	if !o3.Present || !o3.AIBlocked {
		t.Fatalf("block of untouched word = %+v", o3)
	}
}

func TestWords_RejectAndCounts(t *testing.T) {
	db := testutil.NewPostgres(t)
	repo := repository.NewWordRepository(db)
	ctx := context.Background()
	for _, w := range []string{"یکی", "دومی"} {
		if _, err := repo.SubmitReport(ctx, repository.WordReportInput{Word: w, Kind: repository.WordKindAdd, ReporterKey: "i:" + installA, InstallID: installA}); err != nil {
			t.Fatal(err)
		}
	}
	counts, err := repo.SuggestionCounts(ctx)
	if err != nil || counts["add"] != 2 || counts["remove"] != 0 {
		t.Fatalf("counts = %v err=%v", counts, err)
	}
	var id int64
	_ = db.QueryRow(`SELECT id FROM word_suggestions WHERE word = 'یکی'`).Scan(&id)
	if w, err := repo.RejectSuggestion(ctx, id, "a", "colloquial"); err != nil || w != "یکی" {
		t.Fatalf("reject = %q, %v", w, err)
	}
	if _, err := repo.RejectSuggestion(ctx, id, "a", ""); !errors.Is(err, repository.ErrSuggestionNotPending) {
		t.Fatalf("second reject err = %v", err)
	}
	if _, err := repo.RejectSuggestion(ctx, 99999, "a", ""); !errors.Is(err, repository.ErrSuggestionNotFound) {
		t.Fatalf("missing reject err = %v", err)
	}
	if st, _ := repo.WordSuggestionStatus(ctx, "یکی", "add"); st != "rejected" {
		t.Fatalf("status = %q", st)
	}
	counts, _ = repo.SuggestionCounts(ctx)
	if counts["add"] != 1 {
		t.Fatalf("counts after reject = %v", counts)
	}
	// Rejecting leaves no override behind.
	if ov, _ := repo.LoadOverrides(ctx); len(ov) != 0 {
		t.Fatalf("overrides = %+v", ov)
	}
}
