package service

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

type serviceAccountKey struct {
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
}

type oauthTokenResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int    `json:"expires_in"`
}

// NotificationService sends push notifications via FCM HTTP v1 API.
// If FCM credentials are not configured, all sends are no-ops with a log line.
type NotificationService struct {
	cfg       *config.Config
	notifRepo *repository.NotificationRepository

	mu          sync.Mutex
	cachedToken string
	tokenExpiry time.Time

	saKey *serviceAccountKey
}

func NewNotificationService(cfg *config.Config, notifRepo *repository.NotificationRepository) *NotificationService {
	svc := &NotificationService{cfg: cfg, notifRepo: notifRepo}
	if cfg.FCMServiceAccount != "" {
		key, err := parseServiceAccount(cfg.FCMServiceAccount)
		if err != nil {
			slog.Error("notification: failed to parse FCM service account", "error", err)
		} else {
			svc.saKey = key
		}
	}
	return svc
}

// SendToUser fetches all device tokens for userID and sends a push notification to each.
func (s *NotificationService) SendToUser(ctx context.Context, userID, title, body string) error {
	if !s.configured() {
		slog.Info("notification.SendToUser (FCM not configured)", "userID", userID, "title", title)
		return nil
	}
	tokens, err := s.notifRepo.GetTokensForUser(ctx, userID)
	if err != nil {
		return fmt.Errorf("SendToUser: %w", err)
	}
	var lastErr error
	for _, token := range tokens {
		if err := s.sendToToken(ctx, token, title, body); err != nil {
			slog.Warn("notification: send failed", "userID", userID, "error", err)
			lastErr = err
		}
	}
	return lastErr
}

// SendToAll sends a notification to every registered device token.
// Used by the scheduler for broadcast events like the daily challenge reminder.
func (s *NotificationService) SendToAll(ctx context.Context, title, body string) error {
	if !s.configured() {
		slog.Info("notification.SendToAll (FCM not configured)", "title", title)
		return nil
	}
	allTokens, err := s.notifRepo.GetAllTokens(ctx)
	if err != nil {
		return fmt.Errorf("SendToAll: %w", err)
	}
	for _, dt := range allTokens {
		if err := s.sendToToken(ctx, dt.Token, title, body); err != nil {
			slog.Warn("notification: SendToAll failed for token", "userID", dt.UserID, "error", err)
		}
	}
	return nil
}

func (s *NotificationService) configured() bool {
	return s.saKey != nil && s.cfg.FCMProjectID != ""
}

func (s *NotificationService) sendToToken(ctx context.Context, token, title, body string) error {
	accessToken, err := s.getAccessToken(ctx)
	if err != nil {
		return fmt.Errorf("sendToToken: get access token: %w", err)
	}

	type fcmNotification struct {
		Title string `json:"title"`
		Body  string `json:"body"`
	}
	type fcmMessage struct {
		Token        string           `json:"token"`
		Notification *fcmNotification `json:"notification"`
	}
	type fcmRequest struct {
		Message *fcmMessage `json:"message"`
	}

	payload := fcmRequest{Message: &fcmMessage{
		Token:        token,
		Notification: &fcmNotification{Title: title, Body: body},
	}}

	raw, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("sendToToken marshal: %w", err)
	}

	apiURL := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", s.cfg.FCMProjectID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, apiURL, bytes.NewReader(raw))
	if err != nil {
		return fmt.Errorf("sendToToken new request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("sendToToken http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("FCM error %d: %s", resp.StatusCode, string(respBody))
	}
	return nil
}

// getAccessToken returns a valid OAuth2 access token, re-fetching when the cached one expires.
func (s *NotificationService) getAccessToken(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.cachedToken != "" && time.Now().Before(s.tokenExpiry) {
		return s.cachedToken, nil
	}

	jwt, err := s.buildJWT()
	if err != nil {
		return "", fmt.Errorf("getAccessToken buildJWT: %w", err)
	}

	data := url.Values{}
	data.Set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
	data.Set("assertion", jwt)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.saKey.TokenURI,
		strings.NewReader(data.Encode()))
	if err != nil {
		return "", fmt.Errorf("getAccessToken new request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("getAccessToken http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("token exchange %d: %s", resp.StatusCode, string(respBody))
	}

	var tr oauthTokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tr); err != nil {
		return "", fmt.Errorf("getAccessToken decode: %w", err)
	}

	s.cachedToken = tr.AccessToken
	// Refresh 5 minutes before actual expiry to avoid edge cases at the boundary.
	s.tokenExpiry = time.Now().Add(time.Duration(tr.ExpiresIn-300) * time.Second)
	return s.cachedToken, nil
}

// buildJWT creates a signed RS256 JWT for the Google OAuth2 token exchange endpoint.
func (s *NotificationService) buildJWT() (string, error) {
	now := time.Now().Unix()

	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"RS256","typ":"JWT"}`))

	claimsJSON, err := json.Marshal(map[string]any{
		"iss":   s.saKey.ClientEmail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   s.saKey.TokenURI,
		"exp":   now + 3600,
		"iat":   now,
	})
	if err != nil {
		return "", fmt.Errorf("buildJWT claims: %w", err)
	}
	claims := base64.RawURLEncoding.EncodeToString(claimsJSON)
	signingInput := header + "." + claims

	privateKey, err := parseRSAPrivateKey(s.saKey.PrivateKey)
	if err != nil {
		return "", fmt.Errorf("buildJWT parse key: %w", err)
	}

	digest := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(rand.Reader, privateKey, crypto.SHA256, digest[:])
	if err != nil {
		return "", fmt.Errorf("buildJWT sign: %w", err)
	}

	return signingInput + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}

// parseRSAPrivateKey decodes a PEM-encoded RSA private key (PKCS1 or PKCS8).
func parseRSAPrivateKey(pemStr string) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(pemStr))
	if block == nil {
		return nil, fmt.Errorf("no PEM block found in private key")
	}
	switch block.Type {
	case "RSA PRIVATE KEY":
		return x509.ParsePKCS1PrivateKey(block.Bytes)
	case "PRIVATE KEY":
		key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("ParsePKCS8PrivateKey: %w", err)
		}
		rsaKey, ok := key.(*rsa.PrivateKey)
		if !ok {
			return nil, fmt.Errorf("service account key is not RSA")
		}
		return rsaKey, nil
	default:
		return nil, fmt.Errorf("unexpected PEM block type: %s", block.Type)
	}
}

// parseServiceAccount reads the service account JSON from an inline string or file path.
func parseServiceAccount(value string) (*serviceAccountKey, error) {
	var key serviceAccountKey
	// Try inline JSON first.
	if err := json.Unmarshal([]byte(value), &key); err == nil {
		if key.ClientEmail != "" && key.PrivateKey != "" {
			return &key, nil
		}
	}
	// Fall back to treating value as a file path.
	data, err := os.ReadFile(value)
	if err != nil {
		return nil, fmt.Errorf("FCM_SERVICE_ACCOUNT_JSON is not valid JSON and not a readable file: %w", err)
	}
	if err := json.Unmarshal(data, &key); err != nil {
		return nil, fmt.Errorf("parse service account file: %w", err)
	}
	return &key, nil
}
