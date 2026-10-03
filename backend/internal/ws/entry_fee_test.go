package ws

import (
	"context"
	"sync"
	"testing"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

type fakeLedger struct {
	mu       sync.Mutex
	balances map[string]int
}

func (l *fakeLedger) SpendCoins(_ context.Context, id string, amt int) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.balances[id] < amt {
		return repository.ErrInsufficientCoins
	}
	l.balances[id] -= amt
	return nil
}

func (l *fakeLedger) AwardCoins(_ context.Context, id string, amt int) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.balances[id] += amt
	return nil
}

func (l *fakeLedger) balance(id string) int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.balances[id]
}

func startFeeRoom(t *testing.T, ledger *fakeLedger, a, b string) (*Room, *Client, *Client) {
	t.Helper()
	hub := NewHub(RoomDeps{Coins: ledger})
	room := hub.GetOrCreateRoom("fee-room", "classic")
	c1, c2 := newTestClient(room, a), newTestClient(room, b)
	_ = room.Join(c1)
	_ = room.Join(c2)
	return room, c1, c2
}

func TestEntryFeeChargedAndWinnerTakesPot(t *testing.T) {
	fee := config.EntryFeeCoins
	ledger := &fakeLedger{balances: map[string]int{"p1": fee + 5, "p2": fee}}
	room, c1, _ := startFeeRoom(t, ledger, "p1", "p2")

	gs := drainMsg(c1)
	if gs.Type != "game_start" || gs.State.EntryFee != fee {
		t.Fatalf("game_start entry fee: want %d, got %+v", fee, gs.State)
	}
	if ledger.balance("p1") != 5 || ledger.balance("p2") != 0 {
		t.Fatalf("fees not charged: p1=%d p2=%d", ledger.balance("p1"), ledger.balance("p2"))
	}

	room.mu.Lock()
	room.resolveGame("p1")
	room.mu.Unlock()

	if got := ledger.balance("p1"); got != 5+2*fee {
		t.Errorf("winner balance: want %d, got %d", 5+2*fee, got)
	}
	if got := ledger.balance("p2"); got != 0 {
		t.Errorf("loser balance: want 0, got %d", got)
	}
	var over outMsg
	for _, m := range drainAll(c1) {
		if m.Type == "game_over" {
			over = m
		}
	}
	if over.Payout != 2*fee {
		t.Errorf("game_over payout: want %d, got %d", 2*fee, over.Payout)
	}
}

func TestEntryFeeRefundedOnDraw(t *testing.T) {
	fee := config.EntryFeeCoins
	ledger := &fakeLedger{balances: map[string]int{"p1": fee, "p2": fee}}
	room, _, _ := startFeeRoom(t, ledger, "p1", "p2")

	room.mu.Lock()
	room.resolveGame("")
	room.mu.Unlock()

	if ledger.balance("p1") != fee || ledger.balance("p2") != fee {
		t.Errorf("draw should refund: p1=%d p2=%d", ledger.balance("p1"), ledger.balance("p2"))
	}
}

func TestEntryFeeCancelsMatchWhenOnePlayerBroke(t *testing.T) {
	fee := config.EntryFeeCoins
	ledger := &fakeLedger{balances: map[string]int{"p1": fee, "p2": 0}}
	room, c1, _ := startFeeRoom(t, ledger, "p1", "p2")

	if m := drainMsg(c1); m.Type != "match_cancelled" || m.Reason != "insufficient_coins" {
		t.Fatalf("expected match_cancelled, got %+v", m)
	}
	if ledger.balance("p1") != fee {
		t.Errorf("p1 should be refunded, got %d", ledger.balance("p1"))
	}
	if room.state != stateFinished {
		t.Errorf("room should be finished, got %s", room.state)
	}
}

func TestEntryFeeSkippedAgainstAI(t *testing.T) {
	ledger := &fakeLedger{balances: map[string]int{"p1": 0}}
	_, c1, _ := startFeeRoom(t, ledger, "p1", config.SystemAIUserID)
	if m := drainMsg(c1); m.Type != "game_start" || m.State.EntryFee != 0 {
		t.Fatalf("AI match should start free, got %+v", m)
	}
}

func TestWaitingPlayerLeavingFreesSeat(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("wait-room", "classic")

	creator := newTestClient(room, "creator")
	_ = room.Join(creator)
	room.leave(creator)

	friend, other := newTestClient(room, "friend"), newTestClient(room, "other")
	_ = room.Join(friend)
	if m := drainAll(friend); len(m) != 0 {
		t.Fatalf("game must not start with an absent creator, got %+v", m)
	}
	_ = room.Join(other)
	if m := drainMsg(friend); m.Type != "game_start" {
		t.Fatalf("want game_start once two present players joined, got %q", m.Type)
	}
}
