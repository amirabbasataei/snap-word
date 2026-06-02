package ws

import (
	"encoding/json"
	"testing"
	"time"
)

// newTestClient builds a Client with no real WebSocket connection.
// The send channel is buffered so broadcasts don't block during tests.
func newTestClient(room *Room, userID string) *Client {
	return &Client{
		room:   room,
		userID: userID,
		conn:   nil,
		send:   make(chan []byte, 256),
	}
}

func drainMsg(c *Client) outMsg {
	select {
	case raw := <-c.send:
		var m outMsg
		_ = json.Unmarshal(raw, &m)
		return m
	case <-time.After(2 * time.Second):
		return outMsg{Type: "timeout"}
	}
}

func drainAll(c *Client) []outMsg {
	var msgs []outMsg
	for {
		select {
		case raw := <-c.send:
			var m outMsg
			_ = json.Unmarshal(raw, &m)
			msgs = append(msgs, m)
		case <-time.After(100 * time.Millisecond):
			return msgs
		}
	}
}

func TestRoomJoinStartsGameOnSecondPlayer(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-1", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")

	if err := room.Join(c1); err != nil {
		t.Fatalf("join c1: %v", err)
	}
	// No game_start yet — only one player.
	select {
	case raw := <-c1.send:
		t.Fatalf("unexpected message before second player joins: %s", raw)
	case <-time.After(50 * time.Millisecond):
	}

	if err := room.Join(c2); err != nil {
		t.Fatalf("join c2: %v", err)
	}

	// Both players must receive game_start.
	gs1 := drainMsg(c1)
	gs2 := drainMsg(c2)
	if gs1.Type != "game_start" {
		t.Errorf("c1 expected game_start, got %q", gs1.Type)
	}
	if gs2.Type != "game_start" {
		t.Errorf("c2 expected game_start, got %q", gs2.Type)
	}
	if gs1.State == nil {
		t.Fatal("game_start state is nil")
	}
	if gs1.State.Mode != "classic" {
		t.Errorf("mode: want classic, got %q", gs1.State.Mode)
	}
	if len(gs1.State.Players) != 2 {
		t.Errorf("players: want 2, got %d", len(gs1.State.Players))
	}
}

func TestRoomWordAccepted(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-2", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	_ = room.Join(c1)
	_ = room.Join(c2)

	// Drain game_start and turn_change from both clients.
	drainAll(c1)
	drainAll(c2)

	// Player 1 goes first. Submit "apple" (starts with any letter — first move).
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"apple"}`))

	wa := drainMsg(c1)
	if wa.Type != "word_accepted" {
		t.Fatalf("expected word_accepted, got %q", wa.Type)
	}
	if wa.Word != "apple" {
		t.Errorf("word: want apple, got %q", wa.Word)
	}
	if wa.NextLetter != "e" {
		t.Errorf("next_letter: want e, got %q", wa.NextLetter)
	}
	if wa.Score <= 0 {
		t.Errorf("score should be positive, got %d", wa.Score)
	}

	// c2 should also receive word_accepted.
	wa2 := drainMsg(c2)
	if wa2.Type != "word_accepted" {
		t.Errorf("c2 expected word_accepted, got %q", wa2.Type)
	}
}

func TestRoomWordRejectedWrongLetter(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-3", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	_ = room.Join(c1)
	_ = room.Join(c2)
	drainAll(c1)
	drainAll(c2)

	// First word sets the chain: "apple" → next must start with 'e'.
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"apple"}`))
	drainAll(c1)
	drainAll(c2)

	// Now it's c2's turn. Submit "dog" which does not start with 'e'.
	room.handleMessage(c2, []byte(`{"type":"submit_word","word":"dog"}`))

	msgs := drainAll(c2)
	found := false
	for _, m := range msgs {
		if m.Type == "word_rejected" && m.Reason == "wrong_letter" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected word_rejected with wrong_letter; got: %+v", msgs)
	}
}

func TestRoomNotYourTurnIgnored(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-4", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	_ = room.Join(c1)
	_ = room.Join(c2)
	drainAll(c1)
	drainAll(c2)

	// c2 tries to submit when it's c1's turn — should be silently ignored.
	room.handleMessage(c2, []byte(`{"type":"submit_word","word":"apple"}`))

	select {
	case raw := <-c2.send:
		var m outMsg
		_ = json.Unmarshal(raw, &m)
		// Only turn_change is acceptable; word_accepted/rejected are not.
		if m.Type == "word_accepted" || m.Type == "word_rejected" {
			t.Errorf("c2 should not get word event on opponent's turn; got %q", m.Type)
		}
	case <-time.After(100 * time.Millisecond):
		// Nothing sent — correct behaviour.
	}
}

func TestRoomRoomFullReturnsError(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-5", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	c3 := newTestClient(room, "player3")

	_ = room.Join(c1)
	_ = room.Join(c2)

	if err := room.Join(c3); err == nil {
		t.Error("expected error joining a full room")
	}
}

func TestRoomAlternatingTurns(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-6", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	_ = room.Join(c1)
	_ = room.Join(c2)
	drainAll(c1)
	drainAll(c2)

	// c1: apple → next letter e
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"apple"}`))
	drainAll(c1)
	drainAll(c2)

	// c2: "era" starts with 'e'
	room.handleMessage(c2, []byte(`{"type":"submit_word","word":"era"}`))
	wa := drainMsg(c2)
	if wa.Type != "word_accepted" {
		t.Fatalf("c2 expected word_accepted after era, got %q", wa.Type)
	}
	if wa.NextLetter != "a" {
		t.Errorf("next_letter after era: want a, got %q", wa.NextLetter)
	}
}

func TestRoomPingPong(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-7", "classic")
	c1 := newTestClient(room, "player1")
	_ = room.Join(c1)

	room.handleMessage(c1, []byte(`{"type":"ping"}`))
	msg := drainMsg(c1)
	if msg.Type != "pong" {
		t.Errorf("expected pong, got %q", msg.Type)
	}
}

func TestRoomShieldNegatesLoss(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-8", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	_ = room.Join(c1)
	_ = room.Join(c2)
	drainAll(c1)
	drainAll(c2)

	// Manually activate c1's shield (skip inventory deduction — deps nil).
	room.mu.Lock()
	room.shieldActive["player1"] = true
	room.mu.Unlock()

	// c1 submits an invalid word (too short).
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"ab"}`))

	msgs := drainAll(c1)
	types := make(map[string]bool)
	for _, m := range msgs {
		types[m.Type] = true
	}
	// Shield fires: should see powerup_used but NOT loss_event.
	if types["loss_event"] {
		t.Error("shield should have negated the loss_event")
	}
	if !types["powerup_used"] {
		t.Error("expected powerup_used (shield auto-activate) event")
	}
}

func TestRoomContinueWindowOpensAfterLoss(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-9", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	_ = room.Join(c1)
	_ = room.Join(c2)
	drainAll(c1)
	drainAll(c2)

	// c1 submits invalid word; should trigger loss_event + continue_window.
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"zzzzzzqq"}`))

	msgs := drainAll(c1)
	types := make(map[string]bool)
	for _, m := range msgs {
		types[m.Type] = true
	}
	if !types["loss_event"] {
		t.Error("expected loss_event")
	}
	if !types["continue_window"] {
		t.Error("expected continue_window")
	}
}

func TestRoomContinueResumesGame(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-10", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	_ = room.Join(c1)
	_ = room.Join(c2)
	drainAll(c1)
	drainAll(c2)

	// Trigger loss for c1.
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"zzzzzzqq"}`))
	drainAll(c1)
	drainAll(c2)

	// c1 decides to continue via ad.
	room.handleMessage(c1, []byte(`{"type":"continue","method":"ad"}`))

	msgs := drainAll(c1)
	types := make(map[string]bool)
	for _, m := range msgs {
		types[m.Type] = true
	}
	if !types["continue_decision"] {
		t.Error("expected continue_decision")
	}
	if !types["turn_change"] {
		t.Error("expected turn_change after continue")
	}

	room.mu.Lock()
	gotState := room.state
	usedContinue := room.continueUsed["player1"]
	room.mu.Unlock()

	if gotState != stateActive {
		t.Errorf("room should be active after continue, got %v", gotState)
	}
	if !usedContinue {
		t.Error("continueUsed should be true for player1 after using continue")
	}
}

func TestRoomSecondContinueNotAllowed(t *testing.T) {
	hub := NewHub(RoomDeps{})
	room := hub.GetOrCreateRoom("room-11", "classic")

	c1 := newTestClient(room, "player1")
	c2 := newTestClient(room, "player2")
	_ = room.Join(c1)
	_ = room.Join(c2)
	drainAll(c1)
	drainAll(c2)

	// First loss → continue.
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"zzzzzzqq"}`))
	drainAll(c1)
	drainAll(c2)
	room.handleMessage(c1, []byte(`{"type":"continue","method":"ad"}`))
	drainAll(c1)
	drainAll(c2)

	// Second loss for the same player → no continue available, game_over fires.
	room.handleMessage(c1, []byte(`{"type":"submit_word","word":"zzzzzzqq"}`))

	msgs := drainAll(c1)
	types := make(map[string]bool)
	for _, m := range msgs {
		types[m.Type] = true
	}
	if types["continue_window"] {
		t.Error("second loss should not open a continue window")
	}
	if !types["game_over"] {
		t.Error("expected game_over after second loss with no continue available")
	}
}
