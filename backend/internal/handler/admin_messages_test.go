package handler_test

import (
	"net/http"
	"testing"

	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// Messages are read-only (a viewer reaches them); bad filters are a 400 before
// any database call, and anonymous callers are refused.
func TestAdminMessages_Validation(t *testing.T) {
	e := newAdminEnv(t, "", true)
	h := handler.NewAdminMessagesHandler(service.NewAdminMessageService(nil))
	e.router.GET("/api/v1/admin/messages", middleware.RequireAdmin("", e.auth), h.List)
	viewer := e.login(t, "peek")

	for _, q := range []string{"?kind=nope", "?from=2026-99-01", "?from=2026-11-05&to=2026-11-01", "?page=abc"} {
		w := e.do(call{method: "GET", path: "/api/v1/admin/messages" + q, cookie: viewer})
		if w.Code != http.StatusBadRequest || errCode(t, w) != "validation_error" {
			t.Errorf("%s: %d %s", q, w.Code, w.Body)
		}
	}
	if w := e.do(call{method: "GET", path: "/api/v1/admin/messages"}); w.Code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", w.Code)
	}
}
