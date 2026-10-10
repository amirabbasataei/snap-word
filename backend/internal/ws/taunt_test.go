package ws

import (
	"context"
	"testing"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

type fakePerks map[string]repository.Perks

func (f fakePerks) GetPerks(_ context.Context, ids []string) (map[string]repository.Perks, error) {
	out := map[string]repository.Perks{}
	for _, id := range ids {
		if p, ok := f[id]; ok {
			out[id] = p
		}
	}
	return out, nil
}

// fakeTaunts is a fixed taunt catalogue standing in for service.CatalogService.
type fakeTaunts map[string]string

func (f fakeTaunts) TauntText(_ context.Context, id string) (string, bool) {
	text, ok := f[id]
	return text, ok
}

var testTaunts = fakeTaunts{"hurry_up": "زود باش!", "good_game": "بازی خوبی بود"}

func startedTauntRoom(t *testing.T, perks fakePerks) (*Room, *Client, *Client) {
	t.Helper()
	hub := NewHub(RoomDeps{Perks: perks, Taunts: testTaunts})
	room := hub.GetOrCreateRoom("taunt-room", "classic")
	c1, c2 := newTestClient(room, "p1"), newTestClient(room, "p2")
	if err := room.Join(c1); err != nil {
		t.Fatal(err)
	}
	if err := room.Join(c2); err != nil {
		t.Fatal(err)
	}
	drainAll(c1)
	drainAll(c2)
	return room, c1, c2
}

func findType(msgs []outMsg, typ string) *outMsg {
	for i := range msgs {
		if msgs[i].Type == typ {
			return &msgs[i]
		}
	}
	return nil
}

func TestTauntPremiumBroadcastsToBoth(t *testing.T) {
	room, c1, c2 := startedTauntRoom(t, fakePerks{"p1": {Premium: true}})
	room.handleMessage(c1, []byte(`{"type":"send_taunt","taunt":"hurry_up"}`))

	for _, c := range []*Client{c1, c2} {
		m := findType(drainAll(c), "taunt")
		if m == nil || m.Taunt != "hurry_up" || m.PlayerID != "p1" || m.Text != "زود باش!" {
			t.Fatalf("expected taunt hurry_up (with its text) from p1, got %+v", m)
		}
	}
}

func TestTauntNonPremiumRejected(t *testing.T) {
	room, c1, c2 := startedTauntRoom(t, fakePerks{"p1": {Premium: true}})
	room.handleMessage(c2, []byte(`{"type":"send_taunt","taunt":"hurry_up"}`))

	m := findType(drainAll(c2), "taunt_rejected")
	if m == nil || m.Reason != "premium_required" {
		t.Fatalf("expected premium_required rejection, got %+v", m)
	}
	if findType(drainAll(c1), "taunt") != nil {
		t.Fatal("rejected taunt must not reach the opponent")
	}
}

func TestTauntUnknownIDIgnored(t *testing.T) {
	room, c1, c2 := startedTauntRoom(t, fakePerks{"p1": {Premium: true}})
	room.handleMessage(c1, []byte(`{"type":"send_taunt","taunt":"free text insult"}`))

	if findType(drainAll(c2), "taunt") != nil || findType(drainAll(c1), "taunt_rejected") != nil {
		t.Fatal("unknown taunt IDs must be dropped silently")
	}
}

func TestTauntCooldownAndMatchCap(t *testing.T) {
	room, c1, _ := startedTauntRoom(t, fakePerks{"p1": {Premium: true}})
	room.handleMessage(c1, []byte(`{"type":"send_taunt","taunt":"hurry_up"}`))
	room.handleMessage(c1, []byte(`{"type":"send_taunt","taunt":"hurry_up"}`))

	msgs := drainAll(c1)
	if findType(msgs, "taunt") == nil {
		t.Fatal("first taunt should be delivered")
	}
	if m := findType(msgs, "taunt_rejected"); m == nil || m.Reason != "rate_limited" {
		t.Fatalf("second immediate taunt should be rate_limited, got %+v", m)
	}

	// The per-match cap applies even once the cooldown has elapsed.
	room.mu.Lock()
	room.tauntCount["p1"] = config.TauntMaxPerMatch
	delete(room.tauntLast, "p1")
	room.mu.Unlock()
	room.handleMessage(c1, []byte(`{"type":"send_taunt","taunt":"good_game"}`))
	if m := findType(drainAll(c1), "taunt_rejected"); m == nil || m.Reason != "rate_limited" {
		t.Fatalf("taunt over the match cap should be rate_limited, got %+v", m)
	}
}

func TestGameStartCarriesPremiumAndAvatars(t *testing.T) {
	hub := NewHub(RoomDeps{Perks: fakePerks{"p1": {Premium: true, AvatarID: "lion"}}})
	room := hub.GetOrCreateRoom("perk-room", "classic")
	c1, c2 := newTestClient(room, "p1"), newTestClient(room, "p2")
	_ = room.Join(c1)
	_ = room.Join(c2)

	gs := findType(drainAll(c2), "game_start")
	if gs == nil || gs.State == nil {
		t.Fatal("no game_start")
	}
	if len(gs.State.Premium) != 1 || gs.State.Premium[0] != "p1" {
		t.Errorf("premium: want [p1], got %v", gs.State.Premium)
	}
	if gs.State.Avatars["p1"] != "lion" || len(gs.State.Avatars) != 1 {
		t.Errorf("avatars: want {p1:lion}, got %v", gs.State.Avatars)
	}
}
