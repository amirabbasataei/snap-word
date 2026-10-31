package service_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

// otpHarness wires AuthService to a real Postgres, a fake Kavenegar server
// that counts sends, and the SMS switch.
type otpHarness struct {
	auth     *service.AuthService
	settings *service.SettingsService
	users    *repository.UserRepository
	sends    *atomic.Int32
	failWith *atomic.Int32 // non-zero: the fake Kavenegar answers with this HTTP/status code
}

func newOTPHarness(t *testing.T, providerConfigured bool) *otpHarness {
	t.Helper()
	db := testutil.NewPostgres(t)
	var sends, failWith atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sends.Add(1)
		if code := int(failWith.Load()); code != 0 {
			w.WriteHeader(code)
			w.Write([]byte(`{"return":{"status":424,"message":"x"}}`))
			return
		}
		w.Write([]byte(`{"return":{"status":200,"message":"ok"}}`))
	}))
	t.Cleanup(srv.Close)

	cfg := &config.Config{
		JWTSecret:            "test-secret-at-least-32-chars-long",
		JWTAccessTTL:         15 * time.Minute,
		JWTRefreshTTL:        720 * time.Hour,
		OTPCodeTTL:           2 * time.Minute,
		OTPResendCooldown:    120 * time.Second,
		KavenegarOTPTemplate: "zanjir",
	}
	if providerConfigured {
		cfg.KavenegarAPIKey = "KEY"
	}
	kav := service.NewKavenegarClient(cfg)
	kav.SetBaseURL(srv.URL)
	users := repository.NewUserRepository(db)
	settings := service.NewSettingsService(repository.NewSettingsRepository(db),
		service.NewAuditService(testutil.NewFakeAdminStore()), kav.Configured)
	return &otpHarness{
		auth:     service.NewAuthService(users, kav, nil, cfg).WithSettings(settings),
		settings: settings, users: users, sends: &sends, failWith: &failWith,
	}
}

const testPhone = "09121112233"

func TestOTP_SMSOn_RealCodeRequired(t *testing.T) {
	h := newOTPHarness(t, true)
	ctx := context.Background()
	if err := h.auth.SendOTP(ctx, testPhone); err != nil {
		t.Fatal(err)
	}
	if h.sends.Load() != 1 {
		t.Fatalf("sends = %d, want 1", h.sends.Load())
	}
	// Pin the stored code so the assertion below cannot collide with 1111.
	u, _ := h.users.GetUserByPhone(ctx, testPhone)
	if err := h.users.SetOTP(ctx, u.ID, "4821", time.Now().Add(time.Minute), time.Now()); err != nil {
		t.Fatal(err)
	}
	if _, _, err := h.auth.VerifyOTP(ctx, testPhone, "1111", ""); !errors.Is(err, service.ErrInvalidOTP) {
		t.Fatalf("1111 with SMS on: got %v, want ErrInvalidOTP", err)
	}
	if _, _, err := h.auth.VerifyOTP(ctx, testPhone, "4821", ""); err != nil {
		t.Fatalf("real code: %v", err)
	}
}

func TestOTP_SMSOff_NoSendAndDevCodeAccepted(t *testing.T) {
	h := newOTPHarness(t, true)
	ctx := context.Background()
	if _, err := h.settings.SetOTPSMSEnabled(ctx, service.AuditActor{Name: "o"}, false, "تست"); err != nil {
		t.Fatal(err)
	}
	if err := h.auth.SendOTP(ctx, testPhone); err != nil {
		t.Fatal(err)
	}
	if h.sends.Load() != 0 {
		t.Fatalf("SMS off must not call Kavenegar, sends = %d", h.sends.Load())
	}
	// Any other code is still wrong (checked first: a successful verify clears the code).
	if _, _, err := h.auth.VerifyOTP(ctx, testPhone, "2222", ""); !errors.Is(err, service.ErrInvalidOTP) {
		t.Fatalf("2222: got %v, want ErrInvalidOTP", err)
	}
	pair, res, err := h.auth.VerifyOTP(ctx, testPhone, "1111", "")
	if err != nil || pair == nil || !res.IsNewUser {
		t.Fatalf("1111 with SMS off: %v %+v", err, res)
	}
}

func TestOTP_SMSOff_DevCodeBeatsEarlierRealCode(t *testing.T) {
	h := newOTPHarness(t, true)
	ctx := context.Background()
	// A real code was sent while SMS was on, then the switch went off.
	if err := h.auth.SendOTP(ctx, testPhone); err != nil {
		t.Fatal(err)
	}
	if _, err := h.settings.SetOTPSMSEnabled(ctx, service.AuditActor{Name: "o"}, false, "تست"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := h.auth.VerifyOTP(ctx, testPhone, "1111", ""); err != nil {
		t.Fatalf("1111 after switching off: %v", err)
	}
	// Switching back on closes the bypass again.
	if _, err := h.settings.SetOTPSMSEnabled(ctx, service.AuditActor{Name: "o"}, true, "تمام"); err != nil {
		t.Fatal(err)
	}
	u, _ := h.users.GetUserByPhone(ctx, testPhone)
	_ = h.users.SetOTP(ctx, u.ID, "4821", time.Now().Add(time.Minute), time.Now())
	if _, _, err := h.auth.VerifyOTP(ctx, testPhone, "1111", ""); !errors.Is(err, service.ErrInvalidOTP) {
		t.Fatalf("1111 after switching on: got %v, want ErrInvalidOTP", err)
	}
}

func TestOTP_NoProvider_DevCodeWithoutSwitch(t *testing.T) {
	h := newOTPHarness(t, false)
	ctx := context.Background()
	if err := h.auth.SendOTP(ctx, testPhone); err != nil {
		t.Fatal(err)
	}
	if _, _, err := h.auth.VerifyOTP(ctx, testPhone, "1111", ""); err != nil {
		t.Fatalf("1111 with no provider: %v", err)
	}
}

func TestOTP_SMSFailure_ClearsCooldownSoPlayerCanRetry(t *testing.T) {
	h := newOTPHarness(t, true)
	ctx := context.Background()
	h.failWith.Store(424)
	if err := h.auth.SendOTP(ctx, testPhone); !errors.Is(err, service.ErrSMSFailed) {
		t.Fatalf("got %v, want ErrSMSFailed", err)
	}
	h.failWith.Store(0)
	if err := h.auth.SendOTP(ctx, testPhone); err != nil {
		t.Fatalf("retry right after a failed send: %v", err)
	}
}
