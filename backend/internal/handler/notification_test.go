package handler_test

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/repository"
)

func newNotificationRouter() *gin.Engine {
	// nil DB — validation fires before any DB access in these tests.
	notifRepo := repository.NewNotificationRepository(nil)
	notifHandler := handler.NewNotificationHandler(notifRepo)

	r := gin.New()
	r.POST("/api/v1/notifications/token", notifHandler.RegisterToken)
	r.DELETE("/api/v1/notifications/token", notifHandler.DeregisterToken)
	return r
}

func deleteJSON(r *gin.Engine, path string, body []byte) *httptest.ResponseRecorder {
	req, _ := http.NewRequest(http.MethodDelete, path, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestRegisterToken_MissingBody(t *testing.T) {
	r := newNotificationRouter()
	w := postJSON(r, "/api/v1/notifications/token", map[string]string{})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestRegisterToken_InvalidPlatform(t *testing.T) {
	r := newNotificationRouter()
	w := postJSON(r, "/api/v1/notifications/token", map[string]string{
		"token":    "fcm-token-abc",
		"platform": "windows",
	})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestRegisterToken_MissingToken(t *testing.T) {
	r := newNotificationRouter()
	w := postJSON(r, "/api/v1/notifications/token", map[string]string{
		"platform": "ios",
	})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestDeregisterToken_MissingToken(t *testing.T) {
	r := newNotificationRouter()
	w := deleteJSON(r, "/api/v1/notifications/token", []byte(`{}`))
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestDeregisterToken_EmptyBody(t *testing.T) {
	r := newNotificationRouter()
	w := deleteJSON(r, "/api/v1/notifications/token", []byte(``))
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}
