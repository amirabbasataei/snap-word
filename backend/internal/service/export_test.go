package service

import "time"

// SetNow lets tests move the admin session clock.
func (s *AdminAuthService) SetNow(f func() time.Time) { s.now = f }

// SetNow lets tests move the dashboard clock.
func (s *AdminDashboardService) SetNow(f func() time.Time) { s.now = f }
