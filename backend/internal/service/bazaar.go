package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"wordchain/backend/internal/config"
)

// Errors of the store layer.
var (
	// ErrPaymentsUnavailable: Bazaar credentials are not configured.
	ErrPaymentsUnavailable = errors.New("payments_unavailable")
	// ErrPurchaseInvalid: the store does not know the purchase (or it was refunded/cancelled).
	ErrPurchaseInvalid = errors.New("purchase_invalid")
	// ErrStoreUnavailable: the store API failed (network, 5xx, bad credentials); retry later.
	ErrStoreUnavailable = errors.New("store_unavailable")
)

const bazaarDefaultBase = "https://pardakht.cafebazaar.ir"

// BazaarPurchase is the validation of a one-time (consumable) purchase.
type BazaarPurchase struct {
	// Purchased is false for a refunded/cancelled purchase.
	Purchased        bool
	DeveloperPayload string
}

// BazaarSubscription is the validation of a subscription token.
type BazaarSubscription struct {
	ValidUntil time.Time
}

// BazaarAPI is the part of Cafe Bazaar's developer API the server uses.
type BazaarAPI interface {
	ValidatePurchase(ctx context.Context, productID, token string) (*BazaarPurchase, error)
	ValidateSubscription(ctx context.Context, productID, token string) (*BazaarSubscription, error)
	Configured() bool
}

// BazaarClient calls the developer API (OAuth2 refresh-token flow). Endpoint
// shapes follow Bazaar's developer API v2; they were taken from a community
// client because the official docs are not machine-readable — confirm them
// with the first real purchase (see CLAUDE.md § Cafe Bazaar billing).
type BazaarClient struct {
	cfg  *config.Config
	base string
	http *http.Client

	mu          sync.Mutex
	accessToken string
	expiresAt   time.Time
}

func NewBazaarClient(cfg *config.Config) *BazaarClient {
	return &BazaarClient{cfg: cfg, base: bazaarDefaultBase, http: &http.Client{Timeout: 10 * time.Second}}
}

func (b *BazaarClient) Configured() bool {
	return b.cfg.BazaarClientID != "" && b.cfg.BazaarClientSecret != "" && b.cfg.BazaarRefreshToken != ""
}

func (b *BazaarClient) token(ctx context.Context, force bool) (string, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if !force && b.accessToken != "" && time.Now().Before(b.expiresAt.Add(-time.Minute)) {
		return b.accessToken, nil
	}
	form := url.Values{
		"grant_type":    {"refresh_token"},
		"client_id":     {b.cfg.BazaarClientID},
		"client_secret": {b.cfg.BazaarClientSecret},
		"refresh_token": {b.cfg.BazaarRefreshToken},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, b.base+"/devapi/v2/auth/token/", strings.NewReader(form.Encode()))
	if err != nil {
		return "", fmt.Errorf("bazaar token request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := b.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("bazaar token: %w", stripURL(err))
	}
	defer res.Body.Close()
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
		Error       string `json:"error"`
	}
	if err := json.NewDecoder(io.LimitReader(res.Body, 1<<16)).Decode(&out); err != nil {
		return "", fmt.Errorf("bazaar token decode (status %d): %w", res.StatusCode, err)
	}
	if res.StatusCode != http.StatusOK || out.AccessToken == "" {
		// Never log the body: it can echo credentials.
		return "", fmt.Errorf("bazaar token refused (status %d, error %q)", res.StatusCode, out.Error)
	}
	b.accessToken = out.AccessToken
	b.expiresAt = time.Now().Add(time.Duration(out.ExpiresIn) * time.Second)
	return b.accessToken, nil
}

// get performs an authorised GET, refreshing the access token once on 401.
func (b *BazaarClient) get(ctx context.Context, path string, out any) (int, error) {
	if !b.Configured() {
		return 0, ErrPaymentsUnavailable
	}
	for attempt := 0; attempt < 2; attempt++ {
		tok, err := b.token(ctx, attempt > 0)
		if err != nil {
			slog.Error("bazaar auth failed", "error", err)
			return 0, ErrStoreUnavailable
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, b.base+path, nil)
		if err != nil {
			return 0, fmt.Errorf("bazaar request: %w", err)
		}
		req.Header.Set("Authorization", "Bearer "+tok)
		res, err := b.http.Do(req)
		if err != nil {
			slog.Error("bazaar request failed", "error", stripURL(err))
			return 0, ErrStoreUnavailable
		}
		body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<16))
		res.Body.Close()
		if res.StatusCode == http.StatusUnauthorized && attempt == 0 {
			continue
		}
		if res.StatusCode == http.StatusOK && out != nil {
			if err := json.Unmarshal(body, out); err != nil {
				slog.Error("bazaar response undecodable", "error", err)
				return res.StatusCode, ErrStoreUnavailable
			}
		}
		return res.StatusCode, nil
	}
	return 0, ErrStoreUnavailable
}

func (b *BazaarClient) ValidatePurchase(ctx context.Context, productID, token string) (*BazaarPurchase, error) {
	var out struct {
		PurchaseState    int    `json:"purchaseState"`
		DeveloperPayload string `json:"developerPayload"`
	}
	path := fmt.Sprintf("/devapi/v2/api/validate/%s/inapp/%s/purchases/%s/",
		url.PathEscape(b.cfg.BazaarPackageName), url.PathEscape(productID), url.PathEscape(token))
	status, err := b.get(ctx, path, &out)
	if err != nil {
		return nil, err
	}
	switch {
	case status == http.StatusOK:
		return &BazaarPurchase{Purchased: out.PurchaseState == 0, DeveloperPayload: out.DeveloperPayload}, nil
	case status == http.StatusNotFound || status == http.StatusBadRequest:
		return nil, ErrPurchaseInvalid
	default:
		slog.Error("bazaar validate unexpected status", "status", status)
		return nil, ErrStoreUnavailable
	}
}

func (b *BazaarClient) ValidateSubscription(ctx context.Context, productID, token string) (*BazaarSubscription, error) {
	var out struct {
		ValidUntilMsec    int64 `json:"validUntilTimestampMsec"`
		ValidUntilMillis  int64 `json:"validUntilTimeMillis"`
		ValidUntilAltMsec int64 `json:"validUntilTimeMsec"`
	}
	path := fmt.Sprintf("/devapi/v2/api/applications/%s/subscriptions/%s/purchases/%s/",
		url.PathEscape(b.cfg.BazaarPackageName), url.PathEscape(productID), url.PathEscape(token))
	status, err := b.get(ctx, path, &out)
	if err != nil {
		return nil, err
	}
	switch {
	case status == http.StatusOK:
		ms := out.ValidUntilMsec
		if ms == 0 {
			ms = out.ValidUntilMillis
		}
		if ms == 0 {
			ms = out.ValidUntilAltMsec
		}
		if ms == 0 {
			slog.Error("bazaar subscription response has no expiry field")
			return nil, ErrStoreUnavailable
		}
		return &BazaarSubscription{ValidUntil: time.UnixMilli(ms)}, nil
	case status == http.StatusNotFound || status == http.StatusBadRequest:
		return nil, ErrPurchaseInvalid
	default:
		slog.Error("bazaar subscription unexpected status", "status", status)
		return nil, ErrStoreUnavailable
	}
}

// stripURL drops the request URL from a transport error (it carries the
// purchase token).
func stripURL(err error) error {
	var ue *url.Error
	if errors.As(err, &ue) {
		return ue.Err
	}
	return err
}
