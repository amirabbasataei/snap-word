package service

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/ws"
)

const queueKeyPrefix = "queue:"

type queueEntry struct {
	UserID     string    `json:"user_id"`
	Difficulty string    `json:"difficulty"`
	EnqueuedAt time.Time `json:"enqueued_at"`
}

type matchResult struct {
	roomID string
	isAI   bool
}

type matchWaiter struct {
	ch   chan matchResult
	done chan struct{} // closed by Cancel to unblock Join
}

// MatchmakingService manages per-mode Redis queues and AI opponent creation.
// A background goroutine polls every 500 ms, pairs players, and falls back to
// an AI opponent after AIFallbackWaitSec seconds.
type MatchmakingService struct {
	rdb *redis.Client
	hub *ws.Hub

	mu      sync.Mutex
	waiters map[string]*matchWaiter // userID → in-flight Join waiter
}

func NewMatchmakingService(rdb *redis.Client, hub *ws.Hub) *MatchmakingService {
	s := &MatchmakingService{
		rdb:     rdb,
		hub:     hub,
		waiters: make(map[string]*matchWaiter),
	}
	go s.runBackground()
	return s
}

// Join adds userID to the queue for mode and blocks until a match is made.
// On success it returns the roomID to connect to via WebSocket and whether
// the opponent is an AI.
func (s *MatchmakingService) Join(ctx context.Context, userID, mode, difficulty string) (string, bool, error) {
	w := &matchWaiter{
		ch:   make(chan matchResult, 1),
		done: make(chan struct{}),
	}

	s.mu.Lock()
	if _, exists := s.waiters[userID]; exists {
		s.mu.Unlock()
		return "", false, fmt.Errorf("already_in_queue")
	}
	s.waiters[userID] = w
	s.mu.Unlock()

	defer func() {
		s.mu.Lock()
		delete(s.waiters, userID)
		s.mu.Unlock()
	}()

	entry := queueEntry{UserID: userID, Difficulty: difficulty, EnqueuedAt: time.Now()}
	b, _ := json.Marshal(entry)
	if err := s.rdb.RPush(ctx, queueKeyPrefix+mode, b).Err(); err != nil {
		return "", false, fmt.Errorf("Join: rpush: %w", err)
	}

	// Wait slightly longer than the AI fallback window so the background
	// goroutine has time to create the AI room and notify us.
	timeout := time.Duration(config.AIFallbackWaitSec+5) * time.Second

	select {
	case result := <-w.ch:
		return result.roomID, result.isAI, nil
	case <-w.done:
		return "", false, fmt.Errorf("cancelled")
	case <-ctx.Done():
		return "", false, ctx.Err()
	case <-time.After(timeout):
		return "", false, fmt.Errorf("timeout")
	}
}

// Cancel removes userID from the matchmaking queue.
func (s *MatchmakingService) Cancel(ctx context.Context, userID, mode string) error {
	s.mu.Lock()
	w, ok := s.waiters[userID]
	if ok {
		close(w.done)
		delete(s.waiters, userID)
	}
	s.mu.Unlock()

	entries, err := s.rdb.LRange(ctx, queueKeyPrefix+mode, 0, -1).Result()
	if err != nil {
		return fmt.Errorf("Cancel: lrange: %w", err)
	}
	for _, raw := range entries {
		var e queueEntry
		if err := json.Unmarshal([]byte(raw), &e); err != nil {
			continue
		}
		if e.UserID == userID {
			s.rdb.LRem(ctx, queueKeyPrefix+mode, 1, raw) //nolint:errcheck
			break
		}
	}
	return nil
}

func (s *MatchmakingService) runBackground() {
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	modes := []string{"classic", "time_attack"}
	for range ticker.C {
		for _, mode := range modes {
			s.processQueue(mode)
		}
	}
}

func (s *MatchmakingService) processQueue(mode string) {
	ctx := context.Background()

	rawEntries, err := s.rdb.LRange(ctx, queueKeyPrefix+mode, 0, -1).Result()
	if err != nil {
		slog.Error("matchmaking: lrange failed", "mode", mode, "error", err)
		return
	}

	type parsedEntry struct {
		raw   string
		entry queueEntry
	}

	var entries []parsedEntry
	for _, raw := range rawEntries {
		var e queueEntry
		if err := json.Unmarshal([]byte(raw), &e); err != nil {
			continue
		}
		entries = append(entries, parsedEntry{raw: raw, entry: e})
	}

	now := time.Now()
	fallbackDur := time.Duration(config.AIFallbackWaitSec) * time.Second

	var fresh, stale []parsedEntry
	for _, pe := range entries {
		if now.Sub(pe.entry.EnqueuedAt) >= fallbackDur {
			stale = append(stale, pe)
		} else {
			fresh = append(fresh, pe)
		}
	}

	// Pair fresh players two at a time.
	for len(fresh) >= 2 {
		p1, p2 := fresh[0], fresh[1]
		fresh = fresh[2:]

		s.rdb.LRem(ctx, queueKeyPrefix+mode, 1, p1.raw) //nolint:errcheck
		s.rdb.LRem(ctx, queueKeyPrefix+mode, 1, p2.raw) //nolint:errcheck

		roomID := newRoomID()
		s.hub.GetOrCreateRoom(roomID, mode)
		slog.Info("matchmaking: paired", "room", roomID,
			"p1", p1.entry.UserID, "p2", p2.entry.UserID, "mode", mode)

		s.notify(p1.entry.UserID, matchResult{roomID: roomID, isAI: false})
		s.notify(p2.entry.UserID, matchResult{roomID: roomID, isAI: false})
	}

	// AI fallback for players who have waited too long.
	for _, pe := range stale {
		s.rdb.LRem(ctx, queueKeyPrefix+mode, 1, pe.raw) //nolint:errcheck

		difficulty := pe.entry.Difficulty
		if difficulty == "" {
			difficulty = "easy"
		}

		roomID := newRoomID()
		room := s.hub.GetOrCreateRoom(roomID, mode)

		aiUserID := "ai:" + difficulty + ":" + roomID[:8]
		aiClient := ws.NewAIClient(room, aiUserID, difficulty)
		if err := room.Join(aiClient); err != nil {
			slog.Error("matchmaking: AI join failed", "room", roomID, "error", err)
			continue
		}
		slog.Info("matchmaking: AI fallback",
			"room", roomID, "player", pe.entry.UserID, "difficulty", difficulty)

		s.notify(pe.entry.UserID, matchResult{roomID: roomID, isAI: true})
	}
}

func (s *MatchmakingService) notify(userID string, result matchResult) {
	s.mu.Lock()
	w, ok := s.waiters[userID]
	s.mu.Unlock()
	if !ok {
		return
	}
	select {
	case w.ch <- result:
	default:
	}
}

// newRoomID generates a random 32-character hex room identifier.
func newRoomID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return fmt.Sprintf("%x", b)
}
