package service_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

// testAuthService returns a service wired to a nil DB and an unconfigured
// Kavenegar client (no API key, so SendOTP would no-op rather than dial out) —
// sufficient for testing input validation that returns before any DB/HTTP call.
func testAuthService() *service.AuthService {
	cfg := &config.Config{
		JWTSecret:         "test-secret-at-least-32-chars-long",
		JWTAccessTTL:      15 * time.Minute,
		JWTRefreshTTL:     720 * time.Hour,
		OTPCodeTTL:        2 * time.Minute,
		OTPResendCooldown: 42 * time.Second,
	}
	return service.NewAuthService(
		repository.NewUserRepository(nil),
		service.NewKavenegarClient(cfg),
		nil, // rdb: nil-safe, daily send-rate cap no-ops
		cfg,
	)
}

func TestSendOTP_InvalidPhone(t *testing.T) {
	svc := testAuthService()
	cases := []string{
		"",
		"123",
		"08361234567",  // wrong prefix (not 09)
		"0912345678",   // too short
		"09123456789a", // trailing letter
		"+1 555 0100",  // not an Iran number
	}
	for _, p := range cases {
		err := svc.SendOTP(context.Background(), p, false)
		if !errors.Is(err, service.ErrInvalidPhone) {
			t.Errorf("phone=%q: got %v, want ErrInvalidPhone", p, err)
		}
	}
}

func TestVerifyOTP_InvalidPhone(t *testing.T) {
	svc := testAuthService()
	_, _, err := svc.VerifyOTP(context.Background(), "not-a-phone", "1234", "")
	if !errors.Is(err, service.ErrInvalidPhone) {
		t.Errorf("got %v, want ErrInvalidPhone", err)
	}
}

func TestRefreshToken_InvalidToken(t *testing.T) {
	svc := testAuthService()

	cases := []string{
		"",
		"not.a.jwt",
		"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.invalid",
	}
	for _, tok := range cases {
		_, err := svc.RefreshToken(context.Background(), tok)
		if !errors.Is(err, service.ErrInvalidToken) {
			t.Errorf("token=%q: got %v, want ErrInvalidToken", tok, err)
		}
	}
}
