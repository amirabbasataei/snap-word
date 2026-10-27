package service

import (
	"context"
	"fmt"
	"sort"
	"sync"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
)

type dictionaryStore interface {
	LoadOverrides(ctx context.Context) ([]repository.DictOverride, error)
}

// DictChange is one word's desired state in a dictionary delta.
type DictChange struct {
	Word      string `json:"word"`
	Present   bool   `json:"present"`
	AIBlocked bool   `json:"ai_blocked"`
}

// DictDelta answers GET /dictionary/delta. Seq is the value the client sends
// as `since` next time; More means the page was capped and the client should
// ask again at once; Reset means the client's seq is ahead of the server's
// (database restored) and it must drop its cached delta before applying this one.
type DictDelta struct {
	Seq     int64        `json:"seq"`
	More    bool         `json:"more"`
	Reset   bool         `json:"reset"`
	Changes []DictChange `json:"changes"`
}

// DictionaryService owns the dictionary overlay: it loads the overrides at
// startup, applies new ones to the live engine, and serves the delta that lets
// the app's bundled word list catch up without a release. The overrides are
// small (one row per changed word), so they are served from memory. A single
// server instance is assumed; with several, each would need to re-Load.
type DictionaryService struct {
	store dictionaryStore

	mu   sync.RWMutex
	rows map[string]repository.DictOverride
	max  int64
}

func NewDictionaryService(store dictionaryStore) *DictionaryService {
	return &DictionaryService{store: store, rows: map[string]repository.DictOverride{}}
}

// Load reads every override from the database and applies it to the engine.
func (s *DictionaryService) Load(ctx context.Context) error {
	rows, err := s.store.LoadOverrides(ctx)
	if err != nil {
		return fmt.Errorf("DictionaryService.Load: %w", err)
	}
	s.Apply(rows...)
	return nil
}

// Apply records overrides that are already stored and makes them live.
func (s *DictionaryService) Apply(rows ...repository.DictOverride) {
	if len(rows) == 0 {
		return
	}
	changes := make([]engine.Override, len(rows))
	s.mu.Lock()
	for i, o := range rows {
		s.rows[o.Word] = o
		if o.Seq > s.max {
			s.max = o.Seq
		}
		changes[i] = engine.Override{Word: o.Word, Present: o.Present, AIBlocked: o.AIBlocked}
	}
	s.mu.Unlock()
	engine.ApplyOverrides(changes)
}

// Delta returns the overrides with seq greater than since, oldest first.
func (s *DictionaryService) Delta(since int64) DictDelta {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := DictDelta{Seq: since, Changes: []DictChange{}}
	if since > s.max {
		out.Reset, since = true, 0
	}
	var pending []repository.DictOverride
	for _, o := range s.rows {
		if o.Seq > since {
			pending = append(pending, o)
		}
	}
	sort.Slice(pending, func(i, j int) bool { return pending[i].Seq < pending[j].Seq })
	if len(pending) > config.DictDeltaMaxRows {
		pending, out.More = pending[:config.DictDeltaMaxRows], true
	}
	for _, o := range pending {
		out.Changes = append(out.Changes, DictChange{Word: o.Word, Present: o.Present, AIBlocked: o.AIBlocked})
		out.Seq = o.Seq
	}
	if out.Reset && len(pending) == 0 {
		out.Seq = s.max
	}
	return out
}

// Overrides returns every override, oldest first (admin export).
func (s *DictionaryService) Overrides() []repository.DictOverride {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]repository.DictOverride, 0, len(s.rows))
	for _, o := range s.rows {
		out = append(out, o)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Seq < out[j].Seq })
	return out
}
