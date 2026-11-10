package ws

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"wordchain/backend/internal/config"
)

type ratingCall struct{ match, winner, loser string }

// fakeRating plays service.RatingService: equal ratings, ±16.
type fakeRating struct {
	mu      sync.Mutex
	calls   []ratingCall
	capped  bool
	failErr error
}

func (f *fakeRating) ApplyMatchResult(_ context.Context, matchID, winnerID, loserID string) (*RatingOutcome, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, ratingCall{matchID, winnerID, loserID})
	if f.failErr != nil {
		return nil, f.failErr
	}
	if f.capped {
		return &RatingOutcome{Rated: false, Reason: "pair_cap", Changes: map[string]RatingChange{
			winnerID: {Before: 1000, After: 1000}, loserID: {Before: 1000, After: 1000},
		}}, nil
	}
	return &RatingOutcome{Rated: true, Changes: map[string]RatingChange{
		winnerID: {Before: 1000, After: 1016, Delta: 16},
		loserID:  {Before: 1000, After: 984, Delta: -16},
	}}, nil
}

func (f *fakeRating) RatingsOf(_ context.Context, ids []string) (map[string]int, error) {
	out := map[string]int{}
	for i, id := range ids {
		out[id] = 1000 + 100*i
	}
	return out, nil
}

func (f *fakeRating) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.calls)
}

func startRatedRoom(t *testing.T, rating *fakeRating, a, b string) (*Room, *Client, *Client, outMsg) {
	t.Helper()
	hub := NewHub(RoomDeps{Rating: rating})
	room := hub.GetOrCreateRoom("rated-room", "classic")
	c1, c2 := newTestClient(room, a), newTestClient(room, b)
	_ = room.Join(c1)
	_ = room.Join(c2)
	gs := drainMsg(c1)
	drainAll(c1)
	drainAll(c2)
	return room, c1, c2, gs
}

func ofType(msgs []outMsg, typ string) []outMsg {
	var out []outMsg
	for _, m := range msgs {
		if m.Type == typ {
			out = append(out, m)
		}
	}
	return out
}

func TestRatingUpdateFollowsGameOver(t *testing.T) {
	rating := &fakeRating{}
	room, c1, c2, gs := startRatedRoom(t, rating, "p1", "p2")
	if gs.Type != "game_start" || gs.State.Ratings["p1"] != 1000 || gs.State.Ratings["p2"] != 1100 {
		t.Fatalf("game_start ratings: %+v", gs.State)
	}

	room.handleMessage(c1, []byte(`{"type":"forfeit"}`)) // a forfeit is a loss
	// A second resolution (e.g. a racing timeout) must not rate again.
	room.handleMessage(c2, []byte(`{"type":"forfeit"}`))

	for i, c := range []*Client{c1, c2} {
		msgs := drainAll(c)
		var types []string
		for _, m := range msgs {
			types = append(types, m.Type)
		}
		if len(msgs) != 2 || msgs[0].Type != "game_over" || msgs[1].Type != "rating_update" {
			t.Fatalf("client %d: want game_over then rating_update, got %v", i+1, types)
		}
		ru := msgs[1]
		if ru.Reason != "" || ru.Rating["p2"] != (RatingChange{1000, 1016, 16}) || ru.Rating["p1"] != (RatingChange{1000, 984, -16}) {
			t.Fatalf("client %d: rating_update %+v", i+1, ru)
		}
	}
	if rating.callCount() != 1 || rating.calls[0] != (ratingCall{"rated-room", "p2", "p1"}) {
		t.Fatalf("rating calls %+v", rating.calls)
	}
}

func TestRatingPairCapReported(t *testing.T) {
	rating := &fakeRating{capped: true}
	room, c1, _, _ := startRatedRoom(t, rating, "p1", "p2")
	room.mu.Lock()
	room.resolveGame("p1")
	room.mu.Unlock()
	ru := ofType(drainAll(c1), "rating_update")
	if len(ru) != 1 || ru[0].Reason != "pair_cap" || ru[0].Rating["p1"].Delta != 0 {
		t.Fatalf("pair-capped rating_update %+v", ru)
	}
}

func TestRatingSkippedForDraw(t *testing.T) {
	rating := &fakeRating{}
	room, c1, _, _ := startRatedRoom(t, rating, "p1", "p2")
	room.mu.Lock()
	room.resolveGame("")
	room.mu.Unlock()
	msgs := drainAll(c1)
	if len(ofType(msgs, "game_over")) != 1 || len(ofType(msgs, "rating_update")) != 0 {
		t.Fatalf("draw: %+v", msgs)
	}
	if rating.callCount() != 0 {
		t.Fatal("a draw must not be rated")
	}
}

func TestRatingSkippedForAIRoom(t *testing.T) {
	rating := &fakeRating{}
	room, c1, _, gs := startRatedRoom(t, rating, "p1", config.SystemAIUserID)
	if _, ok := gs.State.Ratings[config.SystemAIUserID]; ok || gs.State.Ratings["p1"] != 1000 {
		t.Fatalf("AI room ratings: %+v", gs.State.Ratings)
	}
	room.mu.Lock()
	room.resolveGame("p1")
	room.mu.Unlock()
	if len(ofType(drainAll(c1), "rating_update")) != 0 || rating.callCount() != 0 {
		t.Fatal("an AI-fallback game must not be rated")
	}
}

func TestRatingSkippedForCancelledRoom(t *testing.T) {
	rating := &fakeRating{}
	hub := NewHub(RoomDeps{Rating: rating, Coins: &fakeLedger{balances: map[string]int{"p1": config.EntryFeeCoins}}})
	room := hub.GetOrCreateRoom("broke-room", "classic")
	c1, c2 := newTestClient(room, "p1"), newTestClient(room, "p2")
	_ = room.Join(c1)
	_ = room.Join(c2) // p2 cannot pay → match_cancelled
	msgs := drainAll(c1)
	if len(ofType(msgs, "match_cancelled")) != 1 {
		t.Fatalf("want match_cancelled, got %+v", msgs)
	}
	time.Sleep(50 * time.Millisecond)
	if rating.callCount() != 0 {
		t.Fatal("a cancelled room must not be rated")
	}
}

func TestRatingFailureStillClosesRoom(t *testing.T) {
	rating := &fakeRating{failErr: errors.New("db down")}
	room, c1, _, _ := startRatedRoom(t, rating, "p1", "p2")
	room.mu.Lock()
	room.resolveGame("p1")
	room.mu.Unlock()
	msgs := drainAll(c1)
	if len(ofType(msgs, "game_over")) != 1 || len(ofType(msgs, "rating_update")) != 0 {
		t.Fatalf("failed rating: %+v", msgs)
	}
	// closeAfterDrain still runs: the send channel closes after its 2 s drain.
	select {
	case _, ok := <-c1.send:
		if ok {
			t.Fatal("unexpected message after game_over")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("room did not close its connections")
	}
}
