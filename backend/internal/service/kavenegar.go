package service

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"log/slog"

	"wordchain/backend/internal/config"
)

// KavenegarClient sends OTP codes via Kavenegar's Verify Lookup API, which
// delivers a pre-approved template with a token by SMS or voice call
// (https://kavenegar.com — same endpoint for both, switched by `type`).
// If no API key is configured, sends are no-ops with a log line — mirrors
// NotificationService's FCM-not-configured fallback.
type KavenegarClient struct {
	apiKey      string
	otpTemplate string
	httpClient  *http.Client
}

func NewKavenegarClient(cfg *config.Config) *KavenegarClient {
	return &KavenegarClient{
		apiKey:      cfg.KavenegarAPIKey,
		otpTemplate: cfg.KavenegarOTPTemplate,
		httpClient:  &http.Client{Timeout: 10 * time.Second},
	}
}

// Configured reports whether a Kavenegar API key is set. When false, SendOTP
// is a no-op and AuthService issues a fixed dev OTP instead of a random one.
func (k *KavenegarClient) Configured() bool {
	return k.apiKey != ""
}

// SendOTP delivers code to phone by SMS, or by voice call if voice is true.
func (k *KavenegarClient) SendOTP(ctx context.Context, phone, code string, voice bool) error {
	if !k.Configured() {
		slog.Info("kavenegar not configured, skipping otp send", "phone", maskPhone(phone), "voice", voice)
		return nil
	}

	deliveryType := "sms"
	if voice {
		deliveryType = "call"
	}

	params := url.Values{}
	params.Set("receptor", phone)
	params.Set("token", code)
	params.Set("template", k.otpTemplate)
	params.Set("type", deliveryType)

	apiURL := fmt.Sprintf("https://api.kavenegar.com/v1/%s/verify/lookup.json?%s", k.apiKey, params.Encode())

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, apiURL, nil)
	if err != nil {
		return fmt.Errorf("SendOTP new request: %w", err)
	}

	resp, err := k.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("SendOTP http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		// Drain but never log the body — Kavenegar echoes the receptor/token back.
		_, _ = io.Copy(io.Discard, resp.Body)
		return fmt.Errorf("kavenegar: status %d", resp.StatusCode)
	}
	return nil
}

// maskPhone redacts the middle digits of a normalized 09XXXXXXXXX phone for
// safe logging — never log a full phone number or the OTP code itself.
func maskPhone(phone string) string {
	if len(phone) != 11 {
		return "***"
	}
	return phone[:4] + "***" + phone[8:]
}
