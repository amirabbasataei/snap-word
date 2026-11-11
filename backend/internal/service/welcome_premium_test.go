package service_test

import (
	"context"
	"testing"
	"time"

	"wordchain/backend/internal/config"
)

// A new account gets the 7-day Special Subscription and the gift message; a
// second sign-in of the same account grants nothing more.
func TestVerifyOTP_NewAccountGetsWelcomePremium(t *testing.T) {
	h := newOTPHarness(t, false)
	ctx := context.Background()
	if err := h.auth.SendOTP(ctx, testPhone); err != nil {
		t.Fatal(err)
	}
	_, res, err := h.auth.VerifyOTP(ctx, testPhone, "1111", "")
	if err != nil || !res.IsNewUser {
		t.Fatalf("verify: %v %+v", err, res)
	}

	until, err := h.users.GetPremiumUntil(ctx, res.UserID)
	if err != nil || until == nil {
		t.Fatalf("premium_until = %v, %v", until, err)
	}
	want := time.Duration(config.WelcomePremiumDays) * 24 * time.Hour
	if d := time.Until(*until); d > want || d < want-time.Minute {
		t.Fatalf("premium lasts %v, want ~%v", d, want)
	}

	// Signing in again (not a new user) must not extend it.
	if err := h.users.SetOTP(ctx, res.UserID, "4821", time.Now().Add(time.Minute), time.Now()); err != nil {
		t.Fatal(err)
	}
	if _, res2, err := h.auth.VerifyOTP(ctx, testPhone, "4821", ""); err != nil || res2.IsNewUser {
		t.Fatalf("second verify: %v %+v", err, res2)
	}
	again, _ := h.users.GetPremiumUntil(ctx, res.UserID)
	if !again.Equal(*until) {
		t.Fatalf("second sign-in changed premium_until: %v -> %v", until, again)
	}
}
