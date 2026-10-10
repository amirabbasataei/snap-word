package service

import "time"

// SetNow lets tests move the admin session clock.
func (s *AdminAuthService) SetNow(f func() time.Time) { s.now = f }
