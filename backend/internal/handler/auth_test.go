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
		JWTSecret:     "test-secret-at-least-32-chars-long",
		JWTAccessTTL:  15 * time.Minute,
		JWTRefreshTTL: 720 * time.Hour,
	}
	// Nil DB — validation errors fire before any DB call in these tests.
	userRepo := repository.NewUserRepository(nil)
	authSvc := service.NewAuthService(userRepo, cfg)
	authHandler := handler.NewAuthHandler(authSvc)

	r := gin.New()
	auth := r.Group("/api/v1/auth")
	auth.POST("/register", authHandler.Register)
	auth.POST("/login", authHandler.Login)
	auth.POST("/refresh", authHandler.Refresh)

	protected := r.Group("/api/v1/protected", middleware.RequireAuth(authSvc))
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

func TestRegister_MissingFields(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/register", map[string]string{})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestRegister_WeakPassword(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/register", map[string]string{
		"username": "alice",
		"email":    "alice@example.com",
		"password": "short",
	})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
	var resp map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &resp)
	errObj, _ := resp["error"].(map[string]any)
	if errObj["code"] != "weak_password" {
		t.Errorf("unexpected error code: %v", errObj["code"])
	}
}

func TestRegister_InvalidUsername(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/register", map[string]string{
		"username": "a b",             // space in username
		"email":    "a@example.com",
		"password": "Valid1pass",
	})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestLogin_MissingFields(t *testing.T) {
	r := newTestRouter()
	w := postJSON(r, "/api/v1/auth/login", map[string]string{})
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

func TestProtectedRoute_NoToken(t *testing.T) {
	r := newTestRouter()
	req, _ := http.NewRequest(http.MethodGet, "/api/v1/protected/ping", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", w.Code)
	}
}

func TestProtectedRoute_BadToken(t *testing.T) {
	r := newTestRouter()
	req, _ := http.NewRequest(http.MethodGet, "/api/v1/protected/ping", nil)
	req.Header.Set("Authorization", "Bearer invalid.token.here")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", w.Code)
	}
}

func TestProtectedRoute_MalformedHeader(t *testing.T) {
	r := newTestRouter()
	req, _ := http.NewRequest(http.MethodGet, "/api/v1/protected/ping", nil)
	req.Header.Set("Authorization", "NotBearer abc")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", w.Code)
	}
}
