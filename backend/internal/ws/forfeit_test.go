package ws

import (
	"testing"

	"wordchain/backend/internal/config"
)

// startForfeitRoom starts a funded 1v1 room; p1 moves first.
func startForfeitRoom(t *testing.T) (*Room, *Client, *Client, *fakeLedger) {
	t.Helper()
	fee := config.EntryFeeCoins
	ledger := &fakeLedger{balances: map[string]int{"p1": fee, "p2": fee}}
	room, c1, c2 := startFeeRoom(t, ledger, "p1", "p2")
	drainAll(c1)
	drainAll(c2)
	return room, c1, c2, ledger
}

func gameOvers(msgs []outMsg) []outMsg {
	var out []outMsg
	for _, m := range msgs {
		if m.Type == "game_over" {
			out = append(out, m)
		}
	}
	return out
}

// assertSettledForOpponent checks exactly one game_over reached both players,
// the winner is `winner`, and the pot was paid out once.
func assertSettledForOpponent(t *testing.T, ledger *fakeLedger, winner, loser string, c1, c2 *Client, msgs1, msgs2 []outMsg) {
	t.Helper()
	fee := config.EntryFeeCoins
	for i, msgs := range [][]outMsg{msgs1, msgs2} {
		overs := gameOvers(msgs)
		if len(overs) != 1 {
			t.Fatalf("client %d: want exactly 1 game_over, got %d", i+1, len(overs))
		}
		if overs[0].Winner != winner {
			t.Errorf("client %d: winner want %s, got %s", i+1, winner, overs[0].Winner)
		}
		if overs[0].Payout != 2*fee {
			t.Errorf("client %d: payout want %d, got %d", i+1, 2*fee, overs[0].Payout)
		}
	}
	if got := ledger.balance(winner); got != 2*fee {
		t.Errorf("winner balance: want %d, got %d", 2*fee, got)
	}
	if got := ledger.balance(loser); got != 0 {
		t.Errorf("loser balance: want 0, got %d", got)
	}
}

func TestForfeitByPlayerToMove(t *testing.T) {
	room, c1, c2, ledger := startForfeitRoom(t)
	room.handleMessage(c1, []byte(`{"type":"forfeit"}`))
	assertSettledForOpponent(t, ledger, "p2", "p1", c1, c2, drainAll(c1), drainAll(c2))
}

func TestForfeitByWaitingPlayer(t *testing.T) {
	room, c1, c2, ledger := startForfeitRoom(t)
	room.handleMessage(c2, []byte(`{"type":"forfeit"}`))
	assertSettledForOpponent(t, ledger, "p1", "p2", c1, c2, drainAll(c1), drainAll(c2))
}

func TestForfeitDuringContinueWindow(t *testing.T) {
	room, c1, c2, ledger := startForfeitRoom(t)
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"zzzzzzqq"}`))
	drainAll(c1)
	drainAll(c2)

	// The opponent leaving mid-window also ends the match.
	room.handleMessage(c2, []byte(`{"type":"forfeit"}`))
	assertSettledForOpponent(t, ledger, "p1", "p2", c1, c2, drainAll(c1), drainAll(c2))

	room.mu.Lock()
	seq := room.continueSeq
	room.mu.Unlock()
	// The window timer firing afterwards must not resolve again.
	room.triggerContinueTimeout(seq-1, "p1")
	if got := ledger.balance("p1"); got != 2*config.EntryFeeCoins {
		t.Errorf("late continue timeout re-settled: p1=%d", got)
	}
}

func TestContinueForfeitResolvesImmediately(t *testing.T) {
	room, c1, c2, ledger := startForfeitRoom(t)
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"zzzzzzqq"}`))
	drainAll(c1)
	drainAll(c2)

	room.handleMessage(c1, []byte(`{"type":"continue","method":"forfeit"}`))
	msgs1, msgs2 := drainAll(c1), drainAll(c2)
	assertSettledForOpponent(t, ledger, "p2", "p1", c1, c2, msgs1, msgs2)

	var decided bool
	for _, m := range msgs2 {
		if m.Type == "continue_decision" && m.Decision == "forfeit" && m.PlayerID == "p1" {
			decided = true
		}
	}
	if !decided {
		t.Error("opponent should see continue_decision forfeit")
	}

	// Cancelled window timer: a stale firing is a no-op.
	room.triggerContinueTimeout(0, "p1")
	if got := ledger.balance("p2"); got != 2*config.EntryFeeCoins {
		t.Errorf("window timer re-settled: p2=%d", got)
	}
}

func TestForfeitAfterGameOverIsNoop(t *testing.T) {
	room, c1, c2, ledger := startForfeitRoom(t)
	room.mu.Lock()
	room.resolveGame("p1")
	room.mu.Unlock()
	drainAll(c1)
	drainAll(c2)

	room.handleMessage(c2, []byte(`{"type":"forfeit"}`))
	if n := len(gameOvers(drainAll(c1))); n != 0 {
		t.Errorf("forfeit after game over sent %d game_over", n)
	}
	if got := ledger.balance("p1"); got != 2*config.EntryFeeCoins {
		t.Errorf("winner balance changed: %d", got)
	}
}

func TestDoubleForfeitSettlesOnce(t *testing.T) {
	room, c1, c2, ledger := startForfeitRoom(t)
	room.handleMessage(c1, []byte(`{"type":"forfeit"}`))
	room.handleMessage(c1, []byte(`{"type":"forfeit"}`))
	room.handleMessage(c2, []byte(`{"type":"forfeit"}`)) // the other side too
	assertSettledForOpponent(t, ledger, "p2", "p1", c1, c2, drainAll(c1), drainAll(c2))
}

func TestForfeitRacingTimeout(t *testing.T) {
	room, c1, c2, ledger := startForfeitRoom(t)
	room.mu.Lock()
	seq := room.turnSeq
	room.mu.Unlock()

	done := make(chan struct{})
	go func() {
		room.triggerTurnTimeout(seq, "p1") // p1 timed out ...
		close(done)
	}()
	room.handleMessage(c1, []byte(`{"type":"forfeit"}`)) // ... while forfeiting
	<-done

	// Whichever won the race, p1 either forfeited (p2 wins) or is in a continue
	// window; a forfeit afterwards must settle in p2's favour exactly once.
	room.handleMessage(c1, []byte(`{"type":"forfeit"}`))
	msgs1, msgs2 := drainAll(c1), drainAll(c2)
	assertSettledForOpponent(t, ledger, "p2", "p1", c1, c2, msgs1, msgs2)
}

func TestForfeitFromUnseatedClientIgnored(t *testing.T) {
	room, c1, c2, ledger := startForfeitRoom(t)

	spectator := newTestClient(room, "spectator")
	room.handleMessage(spectator, []byte(`{"type":"forfeit"}`))

	// A stale connection of a seated player (replaced by a reconnect) is ignored too.
	stale := newTestClient(room, "p1")
	room.handleMessage(stale, []byte(`{"type":"forfeit"}`))

	room.mu.Lock()
	state := room.state
	room.mu.Unlock()
	if state != stateActive {
		t.Fatalf("room should still be active, got %v", state)
	}
	if n := len(gameOvers(append(drainAll(c1), drainAll(c2)...))); n != 0 {
		t.Errorf("unexpected game_over (%d)", n)
	}
	if ledger.balance("p1") != 0 || ledger.balance("p2") != 0 {
		t.Error("entry fees must stay held")
	}
}

func TestForfeitWhileWaitingIsNoop(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("forfeit-wait", "classic")
	c1 := newTestClient(room, "p1")
	_ = room.Join(c1)
	drainAll(c1)

	room.handleMessage(c1, []byte(`{"type":"forfeit"}`))
	room.mu.Lock()
	state := room.state
	room.mu.Unlock()
	if state != stateWaiting {
		t.Errorf("forfeit in waiting room changed state to %v", state)
	}
}
