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

// testAuthService returns a service wired to a nil DB — sufficient for testing
// input validation that returns before any DB call is made.
func testAuthService() *service.AuthService {
	return service.NewAuthService(
		repository.NewUserRepository(nil),
		&config.Config{
			JWTSecret:     "test-secret-at-least-32-chars-long",
			JWTAccessTTL:  15 * time.Minute,
			JWTRefreshTTL: 720 * time.Hour,
		},
	)
}

func TestRegister_WeakPassword(t *testing.T) {
	svc := testAuthService()
	cases := []string{
		"short1",    // under 8 chars
		"allletter", // no digit
		"12345678",  // no letter
	}
	for _, p := range cases {
		_, err := svc.Register(context.Background(), "alice", "a@b.com", p)
		if !errors.Is(err, service.ErrWeakPassword) {
			t.Errorf("password=%q: got %v, want ErrWeakPassword", p, err)
		}
	}
}

func TestRegister_InvalidUsername(t *testing.T) {
	svc := testAuthService()
	cases := []string{
		"ab",            // too short (2 chars)
		"bad name",      // space
		"bad-name",      // hyphen
		"bad@name",      // @
		"this_username_is_way_too_long_over_32_chars", // too long
	}
	for _, u := range cases {
		_, err := svc.Register(context.Background(), u, "a@b.com", "Valid1pass")
		if !errors.Is(err, service.ErrInvalidUsername) {
			t.Errorf("username=%q: got %v, want ErrInvalidUsername", u, err)
		}
	}
}

func TestRegister_InvalidEmail(t *testing.T) {
	svc := testAuthService()
	cases := []string{
		"notanemail",
		"@nodomain",
		"no-at-sign",
		"spaces @b.com",
	}
	for _, e := range cases {
		_, err := svc.Register(context.Background(), "alice", e, "Valid1pass")
		if !errors.Is(err, service.ErrInvalidEmail) {
			t.Errorf("email=%q: got %v, want ErrInvalidEmail", e, err)
		}
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
