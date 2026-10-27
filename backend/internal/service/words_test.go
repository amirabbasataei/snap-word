package service_test

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

const (
	wInstall = "aaaaaaaa-0000-4000-8000-000000000001"
	wUser    = "dddddddd-0000-4000-8000-00000000000a"
)

// fakeWordStore is an in-memory wordSuggestionStore + adminWordStore.
type fakeWordStore struct {
	mu       sync.Mutex
	next     int64
	seq      int64
	sugg     map[string]*repository.AdminWordSuggestion // by word|kind
	reporter map[int64]map[string]string                // id -> key -> userID
	reported []repository.WordReportInput
	rewarded map[string]bool
}

func newFakeWordStore() *fakeWordStore {
	return &fakeWordStore{sugg: map[string]*repository.AdminWordSuggestion{}, reporter: map[int64]map[string]string{}, rewarded: map[string]bool{}}
}

func (f *fakeWordStore) SubmitReport(_ context.Context, in repository.WordReportInput) (*repository.WordReportResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.reported = append(f.reported, in)
	k := in.Word + "|" + in.Kind
	s := f.sugg[k]
	if s == nil {
		f.next++
		s = &repository.AdminWordSuggestion{ID: f.next, Word: in.Word, Kind: in.Kind, Status: repository.WordPending}
		f.sugg[k] = s
		f.reporter[s.ID] = map[string]string{}
	}
	if s.Status != repository.WordPending {
		return nil, repository.ErrSuggestionNotPending
	}
	_, dup := f.reporter[s.ID][in.ReporterKey]
	if !dup {
		f.reporter[s.ID][in.ReporterKey] = in.UserID
		s.Reporters++
	}
	return &repository.WordReportResult{Status: s.Status, Reporters: s.Reporters, Counted: !dup}, nil
}

func (f *fakeWordStore) MyReports(context.Context, string, int) ([]repository.MyWordReport, error) {
	return []repository.MyWordReport{{Word: "x", Kind: "add", Status: "pending"}}, nil
}

func (f *fakeWordStore) byID(id int64) *repository.AdminWordSuggestion {
	for _, s := range f.sugg {
		if s.ID == id {
			return s
		}
	}
	return nil
}

func (f *fakeWordStore) ListSuggestions(_ context.Context, p repository.WordListParams) ([]repository.AdminWordSuggestion, int, error) {
	out := []repository.AdminWordSuggestion{}
	for _, s := range f.sugg {
		if (p.Status == "" || s.Status == p.Status) && (p.Kind == "" || s.Kind == p.Kind) {
			out = append(out, *s)
		}
	}
	return out, len(out), nil
}
func (f *fakeWordStore) SuggestionCounts(context.Context) (map[string]int, error) {
	return map[string]int{"add": len(f.sugg), "remove": 0}, nil
}
func (f *fakeWordStore) GetSuggestion(_ context.Context, id int64) (*repository.AdminWordSuggestion, []repository.AdminWordReport, error) {
	s := f.byID(id)
	if s == nil {
		return nil, nil, repository.ErrSuggestionNotFound
	}
	rep := []repository.AdminWordReport{}
	for key, uid := range f.reporter[id] {
		rep = append(rep, repository.AdminWordReport{Username: key, UserID: uid})
	}
	return s, rep, nil
}

func (f *fakeWordStore) ApproveSuggestion(_ context.Context, id int64, _, _, outcome string, _ int) (*repository.ApprovedWord, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	s := f.byID(id)
	if s == nil {
		return nil, repository.ErrSuggestionNotFound
	}
	if s.Status != repository.WordPending {
		return nil, repository.ErrSuggestionNotPending
	}
	f.seq++
	ov := repository.DictOverride{Word: s.Word, Present: true, Seq: f.seq}
	out := &repository.ApprovedWord{Word: s.Word, Kind: s.Kind, Outcome: "add"}
	switch {
	case s.Kind == repository.WordKindAdd:
		for _, uid := range f.reporter[id] {
			if uid != "" && !f.rewarded[s.Word] {
				f.rewarded[s.Word] = true
				out.RewardUserID, out.RewardCreated = uid, true
			}
		}
	case outcome == repository.WordOutcomeRemove:
		ov.Present, out.Outcome = false, outcome
	case outcome == repository.WordOutcomeAIBlock:
		ov.AIBlocked, out.Outcome = true, outcome
	default:
		return nil, repository.ErrSuggestionOutcome
	}
	s.Status = repository.WordApproved
	out.Override = ov
	return out, nil
}

func (f *fakeWordStore) RejectSuggestion(_ context.Context, id int64, _, _ string) (string, error) {
	s := f.byID(id)
	if s == nil {
		return "", repository.ErrSuggestionNotFound
	}
	if s.Status != repository.WordPending {
		return "", repository.ErrSuggestionNotPending
	}
	s.Status = repository.WordRejected
	return s.Word, nil
}

func (f *fakeWordStore) SetOverride(_ context.Context, word string, a repository.OverrideAction) (repository.DictOverride, error) {
	f.seq++
	return repository.DictOverride{Word: word, Present: a != repository.OverrideRemove, AIBlocked: a == repository.OverrideAIBlock, Seq: f.seq}, nil
}
func (f *fakeWordStore) SuggestionsForWord(context.Context, string) ([]repository.AdminWordSuggestion, error) {
	return nil, nil
}
func (f *fakeWordStore) LoadOverrides(context.Context) ([]repository.DictOverride, error) {
	return nil, nil
}

type fakePush struct {
	mu   sync.Mutex
	sent []string
	done chan struct{}
}

func (p *fakePush) SendToUser(_ context.Context, userID, _, body string) error {
	p.mu.Lock()
	p.sent = append(p.sent, userID+": "+body)
	p.mu.Unlock()
	select {
	case p.done <- struct{}{}:
	default:
	}
	return nil
}

// forget makes the engine treat word as absent again (the overlay is process-wide).
func forget(t *testing.T, words ...string) {
	t.Helper()
	t.Cleanup(func() {
		for _, w := range words {
			engine.ApplyOverrides([]engine.Override{{Word: w, Present: false}})
		}
	})
}

func newSuggestionSvc(t *testing.T) (*service.WordSuggestionService, *fakeWordStore) {
	t.Helper()
	_, rdb := testutil.NewRedis(t)
	st := newFakeWordStore()
	return service.NewWordSuggestionService(st, rdb), st
}

func TestWordSubmit_Rules(t *testing.T) {
	svc, st := newSuggestionSvc(t)
	ctx := context.Background()
	const missing = "ناموجودک"

	var existing string
	for _, w := range []string{"کتاب", "درخت", "مدرسه"} {
		if engine.IsValid(w) {
			existing = w
			break
		}
	}
	if existing == "" {
		t.Fatal("no known dictionary word for the test")
	}

	cases := []struct {
		name   string
		userID string
		in     service.SubmitWordInput
		want   error
	}{
		{"ok guest", "", service.SubmitWordInput{Word: missing, Kind: "add", InstallID: wInstall}, nil},
		{"ok signed in, no install", wUser, service.SubmitWordInput{Word: missing, Kind: "add"}, nil},
		{"guest needs install id", "", service.SubmitWordInput{Word: missing, Kind: "add"}, service.ErrWordInvalid},
		{"latin", wUser, service.SubmitWordInput{Word: "abc", Kind: "add"}, service.ErrWordInvalid},
		{"too short", wUser, service.SubmitWordInput{Word: "اب", Kind: "add"}, service.ErrWordInvalid},
		{"too long", wUser, service.SubmitWordInput{Word: strings.Repeat("ا", 31), Kind: "add"}, service.ErrWordInvalid},
		{"bad kind", wUser, service.SubmitWordInput{Word: missing, Kind: "zap"}, service.ErrWordInvalid},
		{"already in dictionary", wUser, service.SubmitWordInput{Word: existing, Kind: "add"}, service.ErrWordInDictionary},
		{"remove needs reason", wUser, service.SubmitWordInput{Word: existing, Kind: "remove"}, service.ErrWordInvalid},
		{"remove ok", wUser, service.SubmitWordInput{Word: existing, Kind: "remove", Reason: "inappropriate"}, nil},
		{"remove unknown word", wUser, service.SubmitWordInput{Word: missing, Kind: "remove", Reason: "not_a_word"}, service.ErrWordUnknown},
	}
	for _, c := range cases {
		_, err := svc.Submit(ctx, c.userID, "1.2.3.4", c.in)
		if !errors.Is(err, c.want) {
			t.Errorf("%s: err = %v, want %v", c.name, err, c.want)
		}
	}

	// The account (not the install) is the reporter key, and a repeat is flagged.
	res, err := svc.Submit(ctx, wUser, "1.2.3.4", service.SubmitWordInput{Word: missing, Kind: "add", InstallID: wInstall})
	if err != nil || !res.AlreadyReported {
		t.Fatalf("repeat = %+v, %v", res, err)
	}
	last := st.reported[len(st.reported)-1]
	if last.ReporterKey != "u:"+wUser || last.UserID != wUser {
		t.Fatalf("reporter = %+v", last)
	}
}

func TestWordSubmit_KnownRejectedAndReviewed(t *testing.T) {
	svc, st := newSuggestionSvc(t)
	ctx := context.Background()
	if _, err := svc.Submit(ctx, wUser, "ip", service.SubmitWordInput{Word: "آبجویی", Kind: "add"}); !errors.Is(err, service.ErrWordReviewed) {
		// آبجویی is on the curation-rejected list unless it was later added.
		if !engine.IsValid("آبجویی") {
			t.Fatalf("known-rejected word err = %v", err)
		}
	}
	// A suggestion an admin already decided on is refused.
	if _, err := svc.Submit(ctx, wUser, "ip", service.SubmitWordInput{Word: "نابودکلمهتست", Kind: "add"}); err != nil {
		t.Fatal(err)
	}
	st.sugg["نابودکلمهتست|add"].Status = repository.WordRejected
	if _, err := svc.Submit(ctx, "other-user", "ip", service.SubmitWordInput{Word: "نابودکلمهتست", Kind: "add"}); !errors.Is(err, service.ErrWordReviewed) {
		t.Fatalf("reviewed err = %v", err)
	}
}

func TestWordSubmit_RateLimit(t *testing.T) {
	svc, _ := newSuggestionSvc(t)
	ctx := context.Background()
	for i := 0; i < config.WordSuggestPerDay; i++ {
		w := "آزمونکی" + strings.Repeat("ا", i)
		if _, err := svc.Submit(ctx, wUser, "9.9.9.9", service.SubmitWordInput{Word: w, Kind: "add"}); err != nil {
			t.Fatalf("report %d: %v", i, err)
		}
	}
	if _, err := svc.Submit(ctx, wUser, "9.9.9.9", service.SubmitWordInput{Word: "آزمونکیاخر", Kind: "add"}); !errors.Is(err, service.ErrWordRateLimited) {
		t.Fatalf("over limit err = %v", err)
	}
	// Another player on a different IP is unaffected.
	if _, err := svc.Submit(ctx, "someone-else", "8.8.8.8", service.SubmitWordInput{Word: "آزمونکیاخر", Kind: "add"}); err != nil {
		t.Fatalf("other player: %v", err)
	}
}

func TestDictionaryDelta(t *testing.T) {
	d := service.NewDictionaryService(newFakeWordStore())
	forget(t, "دلتاالف", "دلتاب")
	if got := d.Delta(0); len(got.Changes) != 0 || got.Seq != 0 || got.Reset {
		t.Fatalf("empty delta = %+v", got)
	}
	d.Apply(repository.DictOverride{Word: "دلتاالف", Present: true, Seq: 3})
	d.Apply(repository.DictOverride{Word: "دلتاب", Present: false, AIBlocked: true, Seq: 5})
	if !engine.IsValid("دلتاالف") {
		t.Fatal("Apply must reach the engine")
	}

	got := d.Delta(0)
	if len(got.Changes) != 2 || got.Seq != 5 || got.Changes[0].Word != "دلتاالف" {
		t.Fatalf("delta(0) = %+v", got)
	}
	got = d.Delta(3)
	if len(got.Changes) != 1 || got.Changes[0].Word != "دلتاب" || !got.Changes[0].AIBlocked || got.Seq != 5 {
		t.Fatalf("delta(3) = %+v", got)
	}
	// Up to date: nothing, seq unchanged.
	if got = d.Delta(5); len(got.Changes) != 0 || got.Seq != 5 || got.Reset {
		t.Fatalf("delta(5) = %+v", got)
	}
	// A client ahead of the server must resync from scratch.
	got = d.Delta(99)
	if !got.Reset || len(got.Changes) != 2 || got.Seq != 5 {
		t.Fatalf("delta(99) = %+v", got)
	}
}

func newAdminWords(t *testing.T) (*service.AdminWordService, *fakeWordStore, *fakePush, *service.DictionaryService, *testutil.FakeAdminStore) {
	t.Helper()
	_, rdb := testutil.NewRedis(t)
	st := newFakeWordStore()
	push := &fakePush{done: make(chan struct{}, 4)}
	dict := service.NewDictionaryService(st)
	audits := testutil.NewFakeAdminStore()
	svc := service.NewAdminWordService(st, dict, service.NewWordMissService(rdb), push, service.NewAuditService(audits))
	return svc, st, push, dict, audits
}

var wActor = service.AuditActor{AdminID: "adm-1", Name: "amir", IP: "1.1.1.1"}

func TestAdminWords_ApproveAddMakesWordLiveRewardsAndPushes(t *testing.T) {
	svc, st, push, _, audits := newAdminWords(t)
	ctx := context.Background()
	const word = "تأییدکلمه"
	forget(t, word)
	sugSvc := service.NewWordSuggestionService(st, nil)
	if _, err := sugSvc.Submit(ctx, wUser, "ip", service.SubmitWordInput{Word: word, Kind: "add"}); err != nil {
		t.Fatal(err)
	}
	if engine.IsValid(word) {
		t.Fatal("word valid before approval")
	}

	res, err := svc.Approve(ctx, wActor, st.sugg[word+"|add"].ID, "", "")
	if err != nil || !res.Rewarded || res.Outcome != "add" {
		t.Fatalf("approve = %+v, %v", res, err)
	}
	if !engine.IsValid(word) || engine.ValidateMove("", word, nil) != nil {
		t.Fatal("approved word must be playable immediately")
	}
	select {
	case <-push.done:
	case <-time.After(2 * time.Second):
		t.Fatal("no push sent to the reporter")
	}
	if !strings.Contains(push.sent[0], wUser) || !strings.Contains(push.sent[0], word) || !strings.Contains(push.sent[0], "۲۵") {
		t.Fatalf("push = %q", push.sent[0])
	}
	if len(audits.Audits) != 1 || audits.Audits[0].Action != "word.approve" || audits.Audits[0].TargetID != word {
		t.Fatalf("audit = %+v", audits.Audits)
	}

	// Approving twice is refused.
	if _, err := svc.Approve(ctx, wActor, st.sugg[word+"|add"].ID, "", ""); !errors.Is(err, repository.ErrSuggestionNotPending) {
		t.Fatalf("second approve err = %v", err)
	}
}

func TestAdminWords_RemovalNeedsReasonAndOutcome(t *testing.T) {
	svc, st, _, _, _ := newAdminWords(t)
	ctx := context.Background()
	var victim string
	for _, w := range []string{"کتاب", "درخت", "مدرسه", "خانه"} {
		if engine.IsValid(w) {
			victim = w
			break
		}
	}
	forget(t)
	sugSvc := service.NewWordSuggestionService(st, nil)
	if _, err := sugSvc.Submit(ctx, wUser, "ip", service.SubmitWordInput{Word: victim, Kind: "remove", Reason: "not_a_word"}); err != nil {
		t.Fatal(err)
	}
	id := st.sugg[victim+"|remove"].ID
	t.Cleanup(func() { engine.ApplyOverrides([]engine.Override{{Word: victim, Present: true}}) })

	if _, err := svc.Approve(ctx, wActor, id, "remove", ""); !errors.Is(err, service.ErrReasonRequired) {
		t.Fatalf("remove without reason err = %v", err)
	}
	if _, err := svc.Approve(ctx, wActor, id, "", "x y z"); !errors.Is(err, repository.ErrSuggestionOutcome) {
		t.Fatalf("remove without outcome err = %v", err)
	}
	if _, err := svc.Approve(ctx, wActor, id, "ai_block", "نادر است"); err != nil {
		t.Fatal(err)
	}
	if !engine.IsValid(victim) || !engine.IsAIBlocked(victim) {
		t.Fatal("ai_block keeps the word valid for players but blocked for the AI")
	}
}

func TestAdminWords_BulkContinuesPastFailures(t *testing.T) {
	svc, st, _, _, _ := newAdminWords(t)
	ctx := context.Background()
	forget(t, "بالکیالف", "بالکیب")
	sugSvc := service.NewWordSuggestionService(st, nil)
	for _, w := range []string{"بالکیالف", "بالکیب"} {
		if _, err := sugSvc.Submit(ctx, wUser, "ip", service.SubmitWordInput{Word: w, Kind: "add"}); err != nil {
			t.Fatal(err)
		}
	}
	ids := []int64{st.sugg["بالکیالف|add"].ID, 4040, st.sugg["بالکیب|add"].ID}
	out, err := svc.Bulk(ctx, wActor, ids, "approve", "")
	if err != nil || out.Done != 2 || len(out.Failed) != 1 || out.Failed[0].ID != 4040 || out.Failed[0].Error != "not_found" {
		t.Fatalf("bulk = %+v, %v", out, err)
	}
	if _, err := svc.Bulk(ctx, wActor, nil, "approve", ""); !errors.Is(err, service.ErrBulkTooMany) {
		t.Fatalf("empty bulk err = %v", err)
	}
	if _, err := svc.Bulk(ctx, wActor, ids, "explode", ""); !errors.Is(err, service.ErrWordBadAction) {
		t.Fatalf("bad action err = %v", err)
	}
}

func TestAdminWords_SetWordRequiresReasonForPanelSessions(t *testing.T) {
	svc, _, _, _, _ := newAdminWords(t)
	ctx := context.Background()
	forget(t, "دستیکلمه")
	if _, err := svc.SetWord(ctx, wActor, "دستیکلمه", repository.OverrideAdd, ""); !errors.Is(err, service.ErrReasonRequired) {
		t.Fatalf("no reason err = %v", err)
	}
	if _, err := svc.SetWord(ctx, wActor, "abc", repository.OverrideAdd, "valid reason"); !errors.Is(err, service.ErrWordInvalid) {
		t.Fatalf("latin err = %v", err)
	}
	if _, err := svc.SetWord(ctx, wActor, "دستیکلمه", "nuke", "valid reason"); !errors.Is(err, service.ErrWordBadAction) {
		t.Fatalf("bad action err = %v", err)
	}
	if _, err := svc.SetWord(ctx, wActor, "دستیکلمه", repository.OverrideAdd, "players use it"); err != nil || !engine.IsValid("دستیکلمه") {
		t.Fatalf("add err = %v valid=%v", err, engine.IsValid("دستیکلمه"))
	}
	// The key script (no admin id) may omit the reason.
	if _, err := svc.SetWord(ctx, service.AuditActor{Name: "script"}, "دستیکلمه", repository.OverrideAIBlock, ""); err != nil {
		t.Fatalf("script err = %v", err)
	}
	exp := svc.Export()
	found := false
	for _, w := range exp.Added {
		found = found || w == "دستیکلمه"
	}
	if !found || len(exp.AIBlocked) != 1 {
		t.Fatalf("export = %+v", exp)
	}
}

func TestWordWarnings(t *testing.T) {
	var base string
	for _, w := range []string{"کتاب", "درخت", "خانه"} {
		if engine.IsValid(w) {
			base = w
			break
		}
	}
	has := func(ws []string, c string) bool {
		for _, w := range ws {
			if w == c {
				return true
			}
		}
		return false
	}
	if !has(service.WordWarnings(base+"‌ها"), service.WarnSuffixOfKnown) {
		t.Error("plural of a known word should warn")
	}
	if !has(service.WordWarnings("می‌رفتند"), service.WarnVerbPrefix) {
		t.Error("می‌ prefix should warn")
	}
	if !has(service.WordWarnings("جزء"), service.WarnEndsInHamza) {
		t.Error("final hamza should warn")
	}
	if got := service.WordWarnings("زنجیرِ"); len(got) != 0 && has(got, service.WarnVerbPrefix) {
		t.Errorf("unexpected warnings %v", got)
	}
}
