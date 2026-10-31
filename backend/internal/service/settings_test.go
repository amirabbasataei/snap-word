package service_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

type memSettings struct {
	rows map[string]*repository.Setting
}

func (m *memSettings) Get(_ context.Context, key string) (*repository.Setting, error) {
	return m.rows[key], nil
}
func (m *memSettings) Set(_ context.Context, key, value, by string) error {
	m.rows[key] = &repository.Setting{Value: value, UpdatedAt: time.Now(), UpdatedBy: by}
	return nil
}

func newSettings(t *testing.T, configured bool) (*service.SettingsService, *testutil.FakeAdminStore) {
	t.Helper()
	store := testutil.NewFakeAdminStore()
	svc := service.NewSettingsService(&memSettings{rows: map[string]*repository.Setting{}},
		service.NewAuditService(store), func() bool { return configured })
	return svc, store
}

func TestSettings_DefaultIsSMSOn(t *testing.T) {
	svc, _ := newSettings(t, true)
	st := svc.OTPStatus(context.Background())
	if !st.SMSEnabled || st.BypassActive || st.UpdatedAt != nil {
		t.Fatalf("default status = %+v", st)
	}
}

func TestSettings_TurnOffAndOn(t *testing.T) {
	svc, store := newSettings(t, true)
	ctx := context.Background()
	actor := service.AuditActor{Name: "owner1"}

	st, err := svc.SetOTPSMSEnabled(ctx, actor, false, "تست محلی")
	if err != nil {
		t.Fatal(err)
	}
	if st.SMSEnabled || !st.BypassActive || st.UpdatedBy != "owner1" || st.DevCode != "1111" {
		t.Fatalf("after off: %+v", st)
	}
	if svc.OTPSMSEnabled(ctx) {
		t.Fatal("OTPSMSEnabled must read the new value immediately")
	}
	if _, err := svc.SetOTPSMSEnabled(ctx, actor, true, "پایان تست"); err != nil {
		t.Fatal(err)
	}
	if !svc.OTPSMSEnabled(ctx) {
		t.Fatal("should be back on")
	}
	acts := store.AuditActions()
	if len(acts) != 2 || acts[0] != "settings.otp_sms" {
		t.Errorf("audit actions = %v", acts)
	}
}

func TestSettings_ReasonRequired(t *testing.T) {
	svc, store := newSettings(t, true)
	_, err := svc.SetOTPSMSEnabled(context.Background(), service.AuditActor{Name: "o"}, false, " x ")
	if !errors.Is(err, service.ErrReasonRequired) {
		t.Fatalf("got %v", err)
	}
	if !svc.OTPSMSEnabled(context.Background()) || len(store.AuditActions()) != 0 {
		t.Error("a rejected change must not apply or be audited")
	}
}

func TestSettings_NoProviderMeansBypass(t *testing.T) {
	svc, _ := newSettings(t, false)
	st := svc.OTPStatus(context.Background())
	if !st.SMSEnabled || st.ProviderConfigured || !st.BypassActive {
		t.Fatalf("status without API key = %+v", st)
	}
}
