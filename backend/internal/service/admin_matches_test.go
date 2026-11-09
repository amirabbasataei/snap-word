package service_test

import (
	"context"
	"errors"
	"testing"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

const (
	mUserA   = "aaaaaaaa-0000-0000-0000-00000000000a"
	mUserB   = "bbbbbbbb-0000-0000-0000-00000000000b"
	mSolo    = "10000000-0000-0000-0000-000000000001"
	mVersus  = "10000000-0000-0000-0000-000000000002"
	mAI      = "10000000-0000-0000-0000-000000000003"
	mDaily   = "10000000-0000-0000-0000-000000000004"
	mPending = "10000000-0000-0000-0000-000000000005"
)

func newMatchSvc(t *testing.T) *service.AdminMatchService {
	t.Helper()
	db := testutil.NewPostgres(t)
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := db.Exec(q, args...); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}
	exec(`INSERT INTO users (id, phone, username, phone_verified_at) VALUES ($1,'09140000001','ali',now()), ($2,'09140000002','sara',now())`, mUserA, mUserB)
	exec(`INSERT INTO matches (id, mode, status, winner_id, game_state, started_at, ended_at) VALUES
	  ($1,'classic','finished',$6,'{"word_chain":["کتاب","بهار","رود"],"score":90}','2026-11-01 10:00:00+00','2026-11-01 10:01:30+00'),
	  ($2,'classic','finished',$7,'{"word_chain":["آب","بابا"],"scores":{}}','2026-11-02 10:00:00+00','2026-11-02 10:05:00+00'),
	  ($3,'classic','finished',NULL,NULL,'2026-11-03 10:00:00+00','2026-11-03 10:02:00+00'),
	  ($4,'daily','finished',$6,'{"word_chain":["دل"]}','2026-11-04 10:00:00+00','2026-11-04 10:01:00+00'),
	  ($5,'classic','pending',NULL,NULL,NULL,NULL)`,
		mSolo, mVersus, mAI, mDaily, mPending, mUserA, mUserB)
	exec(`INSERT INTO match_players (match_id, user_id, score, is_ai, continue_used) VALUES
	  ($1,$5,90,false,false),
	  ($2,$5,40,false,true), ($2,$6,70,false,false),
	  ($3,$5,10,false,false), ($3,$7,0,true,false),
	  ($4,$5,30,false,false)`,
		mSolo, mVersus, mAI, mDaily, mUserA, mUserB, config.SystemAIUserID)
	return service.NewAdminMatchService(repository.NewAdminRepository(db))
}

func ids(p *service.AdminMatchPage) []string {
	out := []string{}
	for _, it := range p.Items {
		out = append(out, it.ID)
	}
	return out
}

func TestAdminMatches_ListKindsAndOrder(t *testing.T) {
	svc := newMatchSvc(t)
	ctx := context.Background()

	all, err := svc.List(ctx, service.MatchListQuery{})
	if err != nil {
		t.Fatal(err)
	}
	// pending is hidden by default; newest first.
	want := []string{mDaily, mAI, mVersus, mSolo}
	got := ids(all)
	if all.Total != 4 || len(got) != 4 {
		t.Fatalf("total=%d items=%v", all.Total, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("order = %v, want %v", got, want)
		}
	}
	kinds := map[string]string{}
	for _, it := range all.Items {
		kinds[it.ID] = it.Kind
	}
	if kinds[mSolo] != "solo" || kinds[mVersus] != "versus" || kinds[mAI] != "ai" || kinds[mDaily] != "daily" {
		t.Errorf("kinds = %v", kinds)
	}

	for kind, id := range map[string]string{"solo": mSolo, "versus": mVersus, "ai": mAI, "daily": mDaily} {
		p, err := svc.List(ctx, service.MatchListQuery{Kind: kind})
		if err != nil || p.Total != 1 || p.Items[0].ID != id {
			t.Errorf("kind %s: %+v, %v", kind, p, err)
		}
	}
	if p, _ := svc.List(ctx, service.MatchListQuery{Status: "pending"}); p == nil || p.Total != 1 || p.Items[0].ID != mPending {
		t.Errorf("pending filter: %+v", p)
	}
}

func TestAdminMatches_ListFiltersAndPlayers(t *testing.T) {
	svc := newMatchSvc(t)
	ctx := context.Background()

	// By player name (partial, case-insensitive) and by exact user id.
	for _, q := range []string{"SAR", mUserB} {
		p, err := svc.List(ctx, service.MatchListQuery{Q: q})
		if err != nil || p.Total != 1 || p.Items[0].ID != mVersus {
			t.Errorf("q=%s: %+v, %v", q, p, err)
		}
	}
	// By match id.
	if p, _ := svc.List(ctx, service.MatchListQuery{Q: mAI}); p == nil || p.Total != 1 {
		t.Errorf("by match id: %+v", p)
	}
	// LIKE wildcards are literal.
	if p, _ := svc.List(ctx, service.MatchListQuery{Q: "%"}); p == nil || p.Total != 0 {
		t.Errorf("wildcard matched: %+v", p)
	}

	// Iran-day range, inclusive on both ends.
	p, err := svc.List(ctx, service.MatchListQuery{From: "2026-11-02", To: "2026-11-03"})
	if err != nil || p.Total != 2 {
		t.Fatalf("range: %+v, %v", p, err)
	}

	// Paging.
	p, _ = svc.List(ctx, service.MatchListQuery{PageSize: 3, Page: 2})
	if p.Total != 4 || len(p.Items) != 1 {
		t.Errorf("page 2: total=%d items=%d", p.Total, len(p.Items))
	}

	// Players, continue use, winner, duration, chain length.
	v, _ := svc.List(ctx, service.MatchListQuery{Kind: "versus"})
	it := v.Items[0]
	if len(it.Players) != 2 || it.Players[0].Username != "ali" || !it.Players[0].ContinueUsed || it.Players[1].Score != 70 {
		t.Errorf("players = %+v", it.Players)
	}
	if it.WinnerID != mUserB || it.ChainLength != 2 || it.DurationSec == nil || *it.DurationSec != 300 {
		t.Errorf("item = %+v", it)
	}
	ai, _ := svc.List(ctx, service.MatchListQuery{Kind: "ai"})
	if !ai.Items[0].Players[1].IsAI || ai.Items[0].ChainLength != 0 {
		t.Errorf("ai item = %+v", ai.Items[0])
	}
}

func TestAdminMatches_Validation(t *testing.T) {
	svc := newMatchSvc(t)
	ctx := context.Background()
	for _, q := range []service.MatchListQuery{
		{Kind: "nope"}, {Status: "nope"}, {From: "2026-13-01"}, {To: "x"}, {From: "2026-11-05", To: "2026-11-01"},
	} {
		if _, err := svc.List(ctx, q); !errors.Is(err, service.ErrInvalidMatchFilter) {
			t.Errorf("%+v: err = %v", q, err)
		}
	}
}

func TestAdminMatches_Detail(t *testing.T) {
	svc := newMatchSvc(t)
	ctx := context.Background()

	d, err := svc.Detail(ctx, mSolo)
	if err != nil {
		t.Fatal(err)
	}
	if len(d.WordChain) != 3 || d.WordChain[0] != "کتاب" || d.Kind != "solo" {
		t.Errorf("detail = %+v", d)
	}
	// A match without game_state has an empty (not null) chain.
	if d, err := svc.Detail(ctx, mAI); err != nil || d.WordChain == nil || len(d.WordChain) != 0 {
		t.Errorf("no state: %+v, %v", d, err)
	}
	for _, id := range []string{"not-a-uuid", "99999999-0000-0000-0000-000000000009"} {
		if _, err := svc.Detail(ctx, id); !errors.Is(err, service.ErrAdminMatchNotFound) {
			t.Errorf("%s: err = %v", id, err)
		}
	}
}
