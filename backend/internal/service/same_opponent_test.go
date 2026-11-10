package service_test

import (
	"context"
	"fmt"
	"testing"

	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

func opp(id string, games int) repository.AdminOpponentGames {
	return repository.AdminOpponentGames{OpponentID: id, OpponentUsername: "u" + id, Games: games}
}

func TestSameOpponentSignal(t *testing.T) {
	cases := []struct {
		name    string
		counts  []repository.AdminOpponentGames
		flagged bool
		total   int
	}{
		{"no games", nil, false, 0},
		{"all against one but too few games", []repository.AdminOpponentGames{opp("a", 3)}, false, 3},
		{"exactly half is not more than half", []repository.AdminOpponentGames{opp("a", 4), opp("b", 4)}, false, 8},
		{"just over half", []repository.AdminOpponentGames{opp("a", 5), opp("b", 4)}, true, 9},
		{"spread out", []repository.AdminOpponentGames{opp("a", 2), opp("b", 2), opp("c", 2), opp("d", 2)}, false, 8},
		{"min sample, all one opponent", []repository.AdminOpponentGames{opp("a", 4)}, true, 4},
	}
	for _, c := range cases {
		got := service.SameOpponentSignal(c.counts)
		if got.Flagged != c.flagged || got.RatedGames != c.total || got.WindowDays != 7 {
			t.Errorf("%s: %+v", c.name, got)
		}
	}
	if v := service.SameOpponentSignal(nil); v.TopOpponent != nil {
		t.Error("no games must have no top opponent")
	}
}

// The user page reads rating_history: only the last 7 days count, per opponent.
func TestAdminUserDetailSameOpponentFlag(t *testing.T) {
	db := testutil.NewPostgres(t)
	const (
		me    = "31000000-0000-0000-0000-000000000001"
		pal   = "31000000-0000-0000-0000-000000000002"
		other = "31000000-0000-0000-0000-000000000003"
	)
	if _, err := db.Exec(`INSERT INTO users (id, phone, username, phone_verified_at) VALUES
		($1,'09170000001','me',now()), ($2,'09170000002','pal',now()), ($3,'09170000003','other',now())`, me, pal, other); err != nil {
		t.Fatal(err)
	}
	n := 0
	game := func(opponent, age string) {
		n++
		id := fmt.Sprintf("32000000-0000-0000-0000-%012d", n)
		if _, err := db.Exec(`INSERT INTO matches (id, mode, status) VALUES ($1,'classic','finished')`, id); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO rating_history (match_id, user_id, opponent_id, rating_before, rating_after, delta, created_at)
			VALUES ($1,$2,$3,1000,1010,10, now() - $4::interval)`, id, me, opponent, age); err != nil {
			t.Fatal(err)
		}
	}
	svc := service.NewAdminUserService(repository.NewAdminRepository(db), nil, nil, nil)
	detail := func() service.AdminUserDetail {
		d, err := svc.Detail(context.Background(), "viewer", me)
		if err != nil {
			t.Fatal(err)
		}
		return *d
	}

	if d := detail(); d.SameOpponent.Flagged || d.SameOpponent.RatedGames != 0 || d.SameOpponent.TopOpponent != nil {
		t.Fatalf("no games: %+v", d.SameOpponent)
	}

	// 3 against pal, 1 against other this week; 10 older ones against other
	// must not count (they would otherwise hide the pattern).
	for i := 0; i < 3; i++ {
		game(pal, "1 day")
	}
	game(other, "2 days")
	for i := 0; i < 10; i++ {
		game(other, "9 days")
	}
	d := detail()
	s := d.SameOpponent
	if !s.Flagged || s.RatedGames != 4 || s.TopGames != 3 || s.TopOpponent == nil || s.TopOpponent.ID != pal || s.TopOpponent.Username != "pal" {
		t.Fatalf("flag: %+v", s)
	}

	// Two more against the other player: 3 of 6 is exactly half → not flagged.
	game(other, "1 hour")
	game(other, "1 hour")
	if s := detail().SameOpponent; s.Flagged || s.RatedGames != 6 {
		t.Fatalf("after balancing: %+v", s)
	}
}
