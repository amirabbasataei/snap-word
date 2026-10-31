package service

import (
	"time"

	"wordchain/backend/internal/config"
)

// SetNow lets tests move the admin session clock.
func (s *AdminAuthService) SetNow(f func() time.Time) { s.now = f }

// SetNow lets tests move the dashboard clock.
func (s *AdminDashboardService) SetNow(f func() time.Time) { s.now = f }

// SetBaseURL points the Kavenegar client at a fake server.
func (k *KavenegarClient) SetBaseURL(u string) { k.baseURL = u }

// NewBazaarClientForTest points a Bazaar client at a fake server.
func NewBazaarClientForTest(cfg *config.Config, base string) *BazaarClient {
	c := NewBazaarClient(cfg)
	c.base = base
	return c
}
