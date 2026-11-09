package handler_test

import (
	"net/http"
	"testing"

	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// Matches are read-only, so a viewer reaches them; bad filters are a 400 and an
// unknown or malformed id is a 404 (neither needs the database).
func TestAdminMatches_Validation(t *testing.T) {
	e := newAdminEnv(t, "", true)
	h := handler.NewAdminMatchesHandler(service.NewAdminMatchService(nil))
	e.router.GET("/api/v1/admin/matches", middleware.RequireAdmin("", e.auth), h.List)
	e.router.GET("/api/v1/admin/matches/:id", middleware.RequireAdmin("", e.auth), h.Get)
	viewer := e.login(t, "peek")

	for _, q := range []string{"?kind=nope", "?status=nope", "?from=2026-99-01", "?page=abc"} {
		w := e.do(call{method: "GET", path: "/api/v1/admin/matches" + q, cookie: viewer})
		if w.Code != http.StatusBadRequest || errCode(t, w) != "validation_error" {
			t.Errorf("%s: %d %s", q, w.Code, w.Body)
		}
	}
	w := e.do(call{method: "GET", path: "/api/v1/admin/matches/not-a-uuid", cookie: viewer})
	if w.Code != http.StatusNotFound || errCode(t, w) != "match_not_found" {
		t.Errorf("bad id: %d %s", w.Code, w.Body)
	}
	if w := e.do(call{method: "GET", path: "/api/v1/admin/matches"}); w.Code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", w.Code)
	}
}
