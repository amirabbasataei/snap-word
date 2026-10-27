package service

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
)

const wordMissesKey = "dict:misses"

// WordMissService keeps an anonymous tally of words rejected as
// not_in_dictionary in multiplayer (word and count, never who typed it), so
// the admin panel can show which missing words players actually try.
type WordMissService struct {
	rdb *redis.Client
}

func NewWordMissService(rdb *redis.Client) *WordMissService { return &WordMissService{rdb: rdb} }

// WordMiss is one entry of the tally.
type WordMiss struct {
	Word  string `json:"word"`
	Count int    `json:"count"`
}

// RecordWordMiss counts one rejection. It never blocks the caller (the room
// loop) and ignores Redis failures.
func (s *WordMissService) RecordWordMiss(word string) {
	if s == nil || s.rdb == nil || word == "" {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if err := s.rdb.ZIncrBy(ctx, wordMissesKey, 1, word).Err(); err != nil {
			slog.Warn("word miss tally failed", "error", err)
			return
		}
		// Keep the set bounded: when it grows 20% past the cap, drop the rarest.
		if n, err := s.rdb.ZCard(ctx, wordMissesKey).Result(); err == nil && n > config.WordMissesKeep*6/5 {
			s.rdb.ZRemRangeByRank(ctx, wordMissesKey, 0, n-config.WordMissesKeep-1)
		}
	}()
}

// Top returns the n most-rejected words, most first.
func (s *WordMissService) Top(ctx context.Context, n int) ([]WordMiss, error) {
	if s.rdb == nil {
		return []WordMiss{}, nil
	}
	zs, err := s.rdb.ZRevRangeWithScores(ctx, wordMissesKey, 0, int64(n-1)).Result()
	if err != nil {
		return nil, fmt.Errorf("WordMissService.Top: %w", err)
	}
	out := make([]WordMiss, 0, len(zs))
	for _, z := range zs {
		w, _ := z.Member.(string)
		out = append(out, WordMiss{Word: w, Count: int(z.Score)})
	}
	return out, nil
}

// Dismiss removes a word from the tally once it has been dealt with.
func (s *WordMissService) Dismiss(ctx context.Context, word string) error {
	if s.rdb == nil {
		return nil
	}
	if err := s.rdb.ZRem(ctx, wordMissesKey, word).Err(); err != nil {
		return fmt.Errorf("WordMissService.Dismiss: %w", err)
	}
	return nil
}
