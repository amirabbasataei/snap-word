package ws

import (
	"sync"
	"testing"
)

type recordedMisses struct {
	mu    sync.Mutex
	words []string
}

func (r *recordedMisses) RecordWordMiss(w string) {
	r.mu.Lock()
	r.words = append(r.words, w)
	r.mu.Unlock()
}

func TestNotInDictionaryRejectionIsTallied(t *testing.T) {
	rec := &recordedMisses{}
	hub := NewHub(RoomDeps{WordMisses: rec})
	room := hub.GetOrCreateRoom("miss-room", "classic")
	c1, c2 := newTestClient(room, "p1"), newTestClient(room, "p2")
	for _, c := range []*Client{c1, c2} {
		if err := room.Join(c); err != nil {
			t.Fatal(err)
		}
	}
	drainAll(c1)
	drainAll(c2)

	cur := c1
	if room.currentPlayerID() == "p2" {
		cur = c2
	}
	// Persian letters, 3+ long, but not a word: rejected as not_in_dictionary.
	room.handleMessage(cur, []byte(`{"type":"submit_word","word":"زززیژیژ"}`))

	rec.mu.Lock()
	defer rec.mu.Unlock()
	if len(rec.words) != 1 || rec.words[0] != "زززیژیژ" {
		t.Fatalf("tallied words = %v", rec.words)
	}
}
