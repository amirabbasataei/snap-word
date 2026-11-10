package ws

import (
	"context"
	"sync"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/testutil"
)

// sideEffects records every progression hook a finished game fires.
type sideEffects struct {
	mu    sync.Mutex
	calls []string
}

func (s *sideEffects) add(c string) {
	s.mu.Lock()
	s.calls = append(s.calls, c)
	s.mu.Unlock()
}

func (s *sideEffects) snapshot() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.calls...)
}

func (s *sideEffects) RecordGamePlayed(_ context.Context, id string, _ time.Time) error {
	s.add("streak:" + id)
	return nil
}
func (s *sideEffects) AddXP(_ context.Context, id string, _ int) error {
	s.add("xp:" + id)
	return nil
}
func (s *sideEffects) AddTotalScore(_ context.Context, id string, _ int) error {
	s.add("total_score:" + id)
	return nil
}

const (
	fbHuman  = "11111111-0000-0000-0000-00000000f001"
	fbHuman2 = "11111111-0000-0000-0000-00000000f002"
)

func playToEnd(t *testing.T, roomID string, humans ...string) (*sideEffects, *fakeRating) {
	t.Helper()
	db := testutil.NewPostgres(t)
	for i, id := range humans {
		if _, err := db.Exec(`INSERT INTO users (id, phone, username, phone_verified_at) VALUES ($1,$2,$3,now())`,
			id, "0916000000"+string(rune('1'+i)), "fb"+string(rune('a'+i))); err != nil {
			t.Fatal(err)
		}
	}
	fx := &sideEffects{}
	rating := &fakeRating{}
	hub := NewHub(RoomDeps{
		MatchRepo:      repository.NewMatchRepository(db),
		StreakSvc:      fx,
		XPSvc:          fx,
		LeaderboardSvc: fx,
		Rating:         rating,
	})
	room := hub.GetOrCreateRoom(roomID, "classic")
	players := append([]string(nil), humans...)
	if len(players) == 1 {
		players = append(players, config.SystemAIUserID)
	}
	for _, id := range players {
		_ = room.Join(newTestClient(room, id))
	}
	room.mu.Lock()
	room.scores[players[0]] = 120
	room.scores[players[1]] = 80
	room.resolveGame(players[0])
	room.mu.Unlock()

	// afterGame runs in its own goroutine: wait for the last bookkeeping step.
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if len(fx.snapshot()) >= 2*len(humans) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	time.Sleep(100 * time.Millisecond) // let any unexpected extra call land
	return fx, rating
}

// A game against the fallback AI is practice: it feeds XP and the daily streak
// and nothing else — no rating, no weekly/all-time board, no lifetime total.
func TestAIFallbackGameTouchesOnlyXPAndStreak(t *testing.T) {
	fx, rating := playToEnd(t, "aaaaaaaa-0000-0000-0000-00000000f001", fbHuman)
	got := map[string]bool{}
	for _, c := range fx.snapshot() {
		got[c] = true
	}
	if !got["streak:"+fbHuman] || !got["xp:"+fbHuman] || len(got) != 2 {
		t.Fatalf("AI game side effects = %v, want exactly streak + xp for the human", fx.snapshot())
	}
	if rating.callCount() != 0 {
		t.Fatal("an AI game must not be rated")
	}
}

// The control: the same finish between two humans also feeds the lifetime
// total and the rating, so the test above is not passing vacuously.
func TestHumanGameFeedsEverything(t *testing.T) {
	fx, rating := playToEnd(t, "aaaaaaaa-0000-0000-0000-00000000f002", fbHuman, fbHuman2)
	got := map[string]bool{}
	for _, c := range fx.snapshot() {
		got[c] = true
	}
	for _, id := range []string{fbHuman, fbHuman2} {
		for _, k := range []string{"streak:", "xp:", "total_score:"} {
			if !got[k+id] {
				t.Errorf("missing %s%s in %v", k, id, fx.snapshot())
			}
		}
	}
	if rating.callCount() != 1 {
		t.Fatalf("rating calls = %d, want 1", rating.callCount())
	}
}
