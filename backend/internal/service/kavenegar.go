package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"log/slog"

	"wordchain/backend/internal/config"
)

// KavenegarClient sends OTP codes via Kavenegar's Verify Lookup API
// (https://kavenegar.com/rest.html#sms-Lookup): GET
// /v1/{API-KEY}/verify/lookup.json?receptor=&token=&template=&type=sms
// delivers the panel-approved template with %token replaced by the code, at
// the provider's highest priority. If no API key is configured, sends are
// no-ops with a log line — mirrors NotificationService's FCM fallback.
type KavenegarClient struct {
	apiKey      string
	otpTemplate string
	baseURL     string
	httpClient  *http.Client
}

const kavenegarBaseURL = "https://api.kavenegar.com"

func NewKavenegarClient(cfg *config.Config) *KavenegarClient {
	return &KavenegarClient{
		apiKey:      cfg.KavenegarAPIKey,
		otpTemplate: cfg.KavenegarOTPTemplate,
		baseURL:     kavenegarBaseURL,
		httpClient:  &http.Client{Timeout: 10 * time.Second},
	}
}

// Configured reports whether a Kavenegar API key is set. When false, SendOTP
// is a no-op and AuthService issues the fixed dev code (1111) instead.
func (k *KavenegarClient) Configured() bool {
	return k.apiKey != ""
}

// KavenegarError is a non-200 answer from Kavenegar. Code is the provider's
// status (e.g. 424 template not found or not yet approved, 418 no credit,
// 403 invalid API key, 411 invalid receptor, 451 rate limited by IP).
type KavenegarError struct {
	Code int
}

func (e *KavenegarError) Error() string { return fmt.Sprintf("kavenegar: status %d", e.Code) }

// lookupResponse is the part of the Lookup reply we read. `entries` echoes the
// receptor and message text (which contains the code), so it is never decoded.
type lookupResponse struct {
	Return struct {
		Status int `json:"status"`
	} `json:"return"`
}

// SendOTP delivers code to phone by SMS through the verify-lookup template.
func (k *KavenegarClient) SendOTP(ctx context.Context, phone, code string) error {
	if !k.Configured() {
		slog.Info("kavenegar not configured, skipping otp send", "phone", maskPhone(phone))
		return nil
	}

	params := url.Values{}
	params.Set("receptor", phone)
	params.Set("token", code)
	params.Set("template", k.otpTemplate)
	params.Set("type", "sms")

	apiURL := fmt.Sprintf("%s/v1/%s/verify/lookup.json?%s", k.baseURL, url.PathEscape(k.apiKey), params.Encode())

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, apiURL, nil)
	if err != nil {
		// The URL embeds the API key; never wrap the url.Error that carries it.
		return fmt.Errorf("SendOTP new request: %w", errors.New("invalid request"))
	}

	resp, err := k.httpClient.Do(req)
	if err != nil {
		// *url.Error includes the full URL (API key and token) — keep only the cause.
		var uerr *url.Error
		if errors.As(err, &uerr) {
			err = uerr.Err
		}
		return fmt.Errorf("SendOTP http: %w", err)
	}
	defer resp.Body.Close()

	// Kavenegar answers with the status both as the HTTP code and in
	// return.status; failures (424, 418, …) arrive as non-200 HTTP codes.
	var body lookupResponse
	if derr := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&body); derr != nil && resp.StatusCode == http.StatusOK {
		return fmt.Errorf("SendOTP decode response: %w", derr)
	}
	status := body.Return.Status
	if status == 0 {
		status = resp.StatusCode
	}
	if resp.StatusCode != http.StatusOK || status != http.StatusOK {
		slog.Error("kavenegar otp send rejected", "phone", maskPhone(phone), "http", resp.StatusCode, "kavenegarStatus", status)
		return &KavenegarError{Code: status}
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
