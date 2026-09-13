package handler_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func newTestRouter() *gin.Engine {
	cfg := &config.Config{
		JWTSecret:         "test-secret-at-least-32-chars-long",
		JWTAccessTTL:      15 * time.Minute,
		JWTRefreshTTL:     720 * time.Hour,
		OTPCodeTTL:        2 * time.Minute,
		OTPResendCooldown: 42 * time.Second,
	}
	// Nil DB — validation errors fire before any DB call in these tests.
	userRepo := repository.NewUserRepository(nil)
	authSvc := service.NewAuthService(userRepo, service.NewKavenegarClient(cfg), nil, cfg)
	authHandler := handler.NewAuthHandler(authSvc, cfg)

	r := gin.New()
	auth := r.Group("/api/v1/auth")
	auth.POST("/send-otp", authHandler.SendOTP)
	auth.POST("/verify-otp", authHandler.VerifyOTP)
	auth.POST("/refresh", authHandler.Refresh)

	protected := r.Group("/api/v1", middleware.RequireAuth(authSvc))
	protected.POST("/referral/redeem", authHandler.RedeemReferral)
	protected.GET("/ping", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"ok": true}) })

	return r
}

func postJSON(r *gin.Engine, path string, body any) *httptest.ResponseRecorder {
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestSendOTP_MissingPhone(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/send-otp", map[string]string{})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestSendOTP_InvalidPhone(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/send-otp", map[string]string{"phone": "not-a-phone"})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
	var resp map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &resp)
	errObj, _ := resp["error"].(map[string]any)
	if errObj["code"] != "invalid_phone" {
		t.Errorf("unexpected error code: %v", errObj["code"])
	}
}

func TestVerifyOTP_MissingFields(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/verify-otp", map[string]string{})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestVerifyOTP_CodeWrongLength(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/verify-otp", map[string]string{
		"phone": "09361234567",
		"code":  "12", // must be exactly 4 digits per binding tag
	})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestVerifyOTP_InvalidPhone(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/verify-otp", map[string]string{
		"phone": "not-a-phone",
		"code":  "1234",
	})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestRefresh_InvalidToken(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/refresh", map[string]string{
		"refresh_token": "not.a.valid.token",
	})
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", w.Code)
	}
}

func TestRedeemReferral_RequiresAuth(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/referral/redeem", map[string]string{"referral_code": "ABC234"})
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401 (never reaches handler body without a token)", w.Code)
	}
}

func TestProtectedRoute_NoToken(t *testing.T) {
	r := newTestRouter()
	req, _ := http.NewRequest(http.MethodGet, "/api/v1/ping", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", w.Code)
	}
}

func TestProtectedRoute_BadToken(t *testing.T) {
	r := newTestRouter()
	req, _ := http.NewRequest(http.MethodGet, "/api/v1/ping", nil)
	req.Header.Set("Authorization", "Bearer invalid.token.here")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", w.Code)
	}
}

func TestProtectedRoute_MalformedHeader(t *testing.T) {
	r := newTestRouter()
	req, _ := http.NewRequest(http.MethodGet, "/api/v1/ping", nil)
	req.Header.Set("Authorization", "NotBearer abc")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", w.Code)
	}
}
