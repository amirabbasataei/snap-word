package service

import (
	"context"
	"time"
)

// SetNow lets tests move the admin session clock.
func (s *AdminAuthService) SetNow(f func() time.Time) { s.now = f }

// SetNow lets tests move the dashboard clock.
func (s *AdminDashboardService) SetNow(f func() time.Time) { s.now = f }

// SetBaseURL points the Kavenegar client at a fake server.
func (k *KavenegarClient) SetBaseURL(u string) { k.baseURL = u }

// SetNow lets tests move the rating clock (the pair cap's Iran day).
func (s *RatingService) SetNow(f func() time.Time) { s.now = f }

// NewMatchmakingForTest builds a MatchmakingService without its background
// goroutine, Redis or hub, for the fallback-level tests.
func NewMatchmakingForTest(r RatingLookup) *MatchmakingService {
	return &MatchmakingService{ratings: r}
}

// FallbackDifficulty exposes the fallback AI level lookup.
func (s *MatchmakingService) FallbackDifficulty(ctx context.Context, userID string) string {
	return s.fallbackDifficulty(ctx, userID)
}
