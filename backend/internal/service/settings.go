package service

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"wordchain/backend/internal/repository"
)

// SettingOTPSMSEnabled is the app_settings key behind the panel's
// «ارسال پیامک کد ورود» switch.
const SettingOTPSMSEnabled = "otp_sms_enabled"

// DevOTPCode is the fixed code accepted while real SMS delivery is off.
const DevOTPCode = "1111"

// settingsCacheTTL bounds how stale a read can be if another instance wrote
// the row; this instance's own writes refresh the cache at once.
const settingsCacheTTL = 5 * time.Second

type settingsStore interface {
	Get(ctx context.Context, key string) (*repository.Setting, error)
	Set(ctx context.Context, key, value, updatedBy string) error
}

// OTPStatus is what the admin panel shows about OTP delivery.
type OTPStatus struct {
	SMSEnabled         bool       `json:"sms_enabled"`         // the switch
	ProviderConfigured bool       `json:"provider_configured"` // a Kavenegar API key is set
	BypassActive       bool       `json:"bypass_active"`       // codes are NOT sent and DevCode is accepted
	DevCode            string     `json:"dev_code"`
	UpdatedAt          *time.Time `json:"updated_at"`
	UpdatedBy          string     `json:"updated_by"`
}

// SettingsService serves runtime switches with a short in-memory cache.
type SettingsService struct {
	store settingsStore
	audit *AuditService
	// providerConfigured reports whether Kavenegar has an API key (for status).
	providerConfigured func() bool

	mu      sync.Mutex
	smsOn   bool
	smsAt   time.Time
	smsRead bool
	smsMeta *repository.Setting
}

func NewSettingsService(store settingsStore, audit *AuditService, providerConfigured func() bool) *SettingsService {
	return &SettingsService{store: store, audit: audit, providerConfigured: providerConfigured}
}

// OTPSMSEnabled reports whether OTP codes are delivered by SMS (default true).
// On a database error it keeps the last known value, or true when there is
// none — failing toward real SMS never opens the 1111 bypass by accident.
func (s *SettingsService) OTPSMSEnabled(ctx context.Context) bool {
	on, _ := s.readSMS(ctx)
	return on
}

func (s *SettingsService) readSMS(ctx context.Context) (bool, *repository.Setting) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.smsRead && time.Since(s.smsAt) < settingsCacheTTL {
		return s.smsOn, s.smsMeta
	}
	row, err := s.store.Get(ctx, SettingOTPSMSEnabled)
	if err != nil {
		slog.Error("read otp_sms_enabled failed", "error", err)
		if s.smsRead {
			return s.smsOn, s.smsMeta
		}
		return true, nil
	}
	s.smsOn = row == nil || row.Value != "false"
	s.smsMeta = row
	s.smsAt = time.Now()
	s.smsRead = true
	return s.smsOn, s.smsMeta
}

// OTPStatus returns the current OTP delivery state for the panel.
func (s *SettingsService) OTPStatus(ctx context.Context) OTPStatus {
	on, meta := s.readSMS(ctx)
	configured := s.providerConfigured != nil && s.providerConfigured()
	st := OTPStatus{
		SMSEnabled:         on,
		ProviderConfigured: configured,
		BypassActive:       !on || !configured,
		DevCode:            DevOTPCode,
	}
	if meta != nil {
		t := meta.UpdatedAt
		st.UpdatedAt = &t
		st.UpdatedBy = meta.UpdatedBy
	}
	return st
}

// SetOTPSMSEnabled flips the switch and writes an audit row. Turning SMS off
// lets anyone who knows the phone number sign in with DevOTPCode, so the
// caller (handler) restricts this to owners and requires a reason.
func (s *SettingsService) SetOTPSMSEnabled(ctx context.Context, actor AuditActor, enabled bool, reason string) (OTPStatus, error) {
	reason, err := cleanReason(reason)
	if err != nil {
		return OTPStatus{}, err
	}
	value := "true"
	if !enabled {
		value = "false"
	}
	if err := s.store.Set(ctx, SettingOTPSMSEnabled, value, actor.Name); err != nil {
		return OTPStatus{}, fmt.Errorf("SettingsService.SetOTPSMSEnabled: %w", err)
	}
	s.mu.Lock()
	s.smsRead = false // next read reloads the row, including updated_at/by
	s.mu.Unlock()
	s.audit.LogRecord(ctx, actor, "settings.otp_sms", AuditTarget{Type: "setting", ID: SettingOTPSMSEnabled},
		map[string]any{"enabled": enabled, "reason": reason})
	return s.OTPStatus(ctx), nil
}
