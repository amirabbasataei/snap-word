package ws

import (
	"context"
	"sync"
	"testing"
)

func newStartedRoom(t *testing.T, id string, deps RoomDeps) (*Room, *Client, *Client) {
	t.Helper()
	hub := NewHub(deps)
	room := hub.GetOrCreateRoom(id, "classic")
	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	_ = room.Join(c1)
	_ = room.Join(c2)
	drainAll(c1)
	drainAll(c2)
	return room, c1, c2
}

func streakOf(room *Room, player string) int {
	room.mu.Lock()
	defer room.mu.Unlock()
	return room.streaks[player]
}

func setStreak(room *Room, player string, n int) {
	room.mu.Lock()
	room.streaks[player] = n
	room.mu.Unlock()
}

// A rejected word ends the match streak, so the first word after a continue
// earns no +50 % streak bonus.
func TestRoomStreakResetsAfterRejectAndContinue(t *testing.T) {
	room, c1, c2 := newStartedRoom(t, "streak-1", RoomDeps{})
	setStreak(room, "player1", 3)

	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"zzzzzzqq"}`))
	drainAll(c1)
	drainAll(c2)
	if got := streakOf(room, "player1"); got != 0 {
		t.Fatalf("streak after rejection = %d, want 0", got)
	}

	room.handleMessage(c1, []byte(`{"type":"continue","method":"ad"}`))
	drainAll(c1)
	drainAll(c2)

	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"کتاب"}`))
	var accepted *outMsg
	for _, m := range drainAll(c1) {
		if m.Type == "word_accepted" {
			m := m
			accepted = &m
		}
	}
	if accepted == nil {
		t.Fatal("expected word_accepted after continue")
	}
	// کتاب: base 40 + speed ≤ 30 = 70 without the streak bonus (90 with it).
	if accepted.Score > 70 {
		t.Errorf("score = %d, want ≤ 70 (no streak bonus after a mistake)", accepted.Score)
	}
	if got := streakOf(room, "player1"); got != 1 {
		t.Errorf("streak after the next word = %d, want 1", got)
	}
}

// The shield saves the match, not the streak.
func TestRoomStreakResetsWhenShieldNegatesLoss(t *testing.T) {
	room, c1, _ := newStartedRoom(t, "streak-2", RoomDeps{})
	setStreak(room, "player1", 4)
	room.mu.Lock()
	room.shieldActive["player1"] = true
	room.mu.Unlock()

	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"zzzzzzqq"}`))
	if got := streakOf(room, "player1"); got != 0 {
		t.Errorf("streak after a shield-negated mistake = %d, want 0", got)
	}
}

func TestRoomStreakResetsOnTimeout(t *testing.T) {
	room, _, _ := newStartedRoom(t, "streak-3", RoomDeps{})
	setStreak(room, "player1", 5)

	room.mu.Lock()
	seq := room.turnSeq
	room.mu.Unlock()
	room.triggerTurnTimeout(seq, "player1")

	if got := streakOf(room, "player1"); got != 0 {
		t.Errorf("streak after timeout = %d, want 0", got)
	}
}

type countingDeductor struct {
	mu    sync.Mutex
	calls int
}

func (d *countingDeductor) UseItem(context.Context, string, string) (PowerupReceipt, error) {
	d.mu.Lock()
	d.calls++
	d.mu.Unlock()
	return PowerupReceipt{}, nil
}

// Freeze was removed: an old app that still sends it gets an answer and is
// never charged.
func TestRoomFreezeRejectedWithoutCharge(t *testing.T) {
	ded := &countingDeductor{}
	room, c1, _ := newStartedRoom(t, "streak-4", RoomDeps{PowerupSvc: ded})

	room.handleMessage(c1, []byte(`{"type":"use_powerup","powerup":"freeze"}`))

	m := drainMsg(c1)
	if m.Type != "powerup_rejected" || m.Powerup != "freeze" || m.Reason != "unknown_powerup" {
		t.Errorf("got %+v, want powerup_rejected freeze unknown_powerup", m)
	}
	ded.mu.Lock()
	defer ded.mu.Unlock()
	if ded.calls != 0 {
		t.Errorf("UseItem called %d times, want 0", ded.calls)
	}
}
