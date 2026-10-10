package handler_test

import (
	"net/http"
	"strings"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// contentEnv mounts the content + catalogue routes exactly as cmd/server/main.go
// does. Both services have no store: every case below must be decided before
// a store is reached (authorisation, CSRF, reason, input validation).
func contentEnv(t *testing.T) *adminEnv {
	t.Helper()
	e := newAdminEnv(t, "k3y", true)
	audit := service.NewAuditService(e.store)
	content, err := service.NewAdminContentService(nil, nil, nil, nil, nil, audit, &config.Config{GameEpochDate: "2025-01-01"})
	if err != nil {
		t.Fatal(err)
	}
	h := handler.NewAdminContentHandler(content)
	cat := handler.NewCatalogHandler(service.NewCatalogService(nil), audit)

	admin := e.router.Group("/api/v1/admin", middleware.RequireAdmin("k3y", e.auth))
	admin.GET("/daily", h.DailyList)
	admin.GET("/daily/:date", h.DailyDetail)
	admin.GET("/leaderboards/weekly", h.WeeklyBoard)
	admin.GET("/leaderboards/alltime", h.AllTimeBoard)
	admin.GET("/leaderboards/rewards", h.WeeklyRewards)
	op := admin.Group("", middleware.RequireRole(service.AdminRoleOperator))
	op.PATCH("/daily/:date", h.SetStartLetter)
	op.POST("/taunts/reorder", cat.ReorderTaunts)
	op.PUT("/taunts/:id", cat.PutTaunt)
	op.DELETE("/taunts/:id", cat.DeleteTaunt)
	op.PUT("/avatars/:id", cat.PutAvatar)
	op.DELETE("/avatars/:id", cat.DeleteAvatar)
	return e
}

func TestAdminContent_ViewerCannotMutate(t *testing.T) {
	e := contentEnv(t)
	viewer := e.login(t, "peek")
	for _, c := range []struct{ method, path string }{
		{"PATCH", "/daily/2099-01-01"},
		{"POST", "/taunts/reorder"},
		{"PUT", "/taunts/hurry_up"},
		{"DELETE", "/taunts/hurry_up"},
		{"PUT", "/avatars/lion"},
		{"DELETE", "/avatars/lion"},
	} {
		w := e.do(call{method: c.method, path: "/api/v1/admin" + c.path, cookie: viewer, csrf: true, body: `{"reason":"because"}`})
		if w.Code != http.StatusForbidden || errCode(t, w) != "insufficient_role" {
			t.Errorf("%s %s: %d %s", c.method, c.path, w.Code, w.Body)
		}
	}
	for _, a := range e.store.AuditActions() {
		if !strings.HasPrefix(a, "auth.") {
			t.Errorf("denied request wrote audit row %q", a)
		}
	}
}

func TestAdminContent_MutationNeedsCSRFHeader(t *testing.T) {
	e := contentEnv(t)
	owner := e.login(t, "boss")
	for _, c := range []struct{ method, path string }{
		{"PATCH", "/daily/2099-01-01"}, {"DELETE", "/taunts/hurry_up"}, {"POST", "/taunts/reorder"},
	} {
		w := e.do(call{method: c.method, path: "/api/v1/admin" + c.path, cookie: owner, body: `{"reason":"because"}`})
		if w.Code != http.StatusForbidden || errCode(t, w) != "csrf_required" {
			t.Errorf("%s %s: %d %s", c.method, c.path, w.Code, w.Body)
		}
	}
}

func TestAdminContent_ErrorMapping(t *testing.T) {
	e := contentEnv(t)
	owner := e.login(t, "boss")
	viewer := e.login(t, "peek")
	key := "k3y"
	soon := time.Now().AddDate(0, 0, 3).Format("2006-01-02")

	cases := []struct {
		name   string
		call   call
		status int
		code   string
	}{
		{"letter: reason required", call{method: "PATCH", path: "/daily/2099-01-01", cookie: owner, csrf: true, body: `{"start_letter":"ب"}`}, 400, "reason_required"},
		{"letter: bad json", call{method: "PATCH", path: "/daily/2099-01-01", cookie: owner, csrf: true, body: `nope`}, 400, "validation_error"},
		{"letter: bad date", call{method: "PATCH", path: "/daily/not-a-date", cookie: owner, csrf: true, body: `{"start_letter":"ب","reason":"دلیل"}`}, 400, "invalid_date"},
		{"letter: past day locked", call{method: "PATCH", path: "/daily/2020-01-01", cookie: owner, csrf: true, body: `{"start_letter":"ب","reason":"دلیل"}`}, 409, "date_not_editable"},
		{"letter: invalid letter", call{method: "PATCH", path: "/daily/" + soon, cookie: owner, csrf: true, body: `{"start_letter":"a","reason":"دلیل"}`}, 400, "invalid_letter"},
		{"letter: beyond the horizon", call{method: "PATCH", path: "/daily/2099-01-01", cookie: owner, csrf: true, body: `{"start_letter":"ب","reason":"دلیل"}`}, 400, "invalid_date"},
		{"taunt put: session needs reason", call{method: "PUT", path: "/taunts/hurry_up", cookie: owner, csrf: true, body: `{"text":"زود باش"}`}, 400, "reason_required"},
		{"taunt put: script reason too short", call{method: "PUT", path: "/taunts/hurry_up", key: key, body: `{"text":"زود باش","reason":"x"}`}, 400, "reason_required"},
		{"taunt delete: session needs reason", call{method: "DELETE", path: "/taunts/hurry_up", cookie: owner, csrf: true}, 400, "reason_required"},
		{"avatar delete: session needs reason", call{method: "DELETE", path: "/avatars/lion", cookie: owner, csrf: true, body: `{}`}, 400, "reason_required"},
		{"avatar put: session needs reason", call{method: "PUT", path: "/avatars/lion", cookie: owner, csrf: true}, 400, "reason_required"},
		{"reorder: empty list", call{method: "POST", path: "/taunts/reorder", cookie: owner, csrf: true, body: `{"ids":[],"reason":"دلیل"}`}, 400, "validation_error"},
		{"reorder: reason required", call{method: "POST", path: "/taunts/reorder", cookie: owner, csrf: true, body: `{"ids":["a_b"]}`}, 400, "reason_required"},
		{"daily list: bad from", call{method: "GET", path: "/daily?from=x", cookie: viewer}, 400, "invalid_date"},
		{"board: bad limit", call{method: "GET", path: "/leaderboards/weekly?limit=abc", cookie: viewer}, 400, "validation_error"},
		{"board: limit out of range", call{method: "GET", path: "/leaderboards/alltime?limit=5000", cookie: viewer}, 400, "validation_error"},
		{"rewards: weeks out of range", call{method: "GET", path: "/leaderboards/rewards?weeks=0x", cookie: viewer}, 400, "validation_error"},
		{"daily detail: bad date", call{method: "GET", path: "/daily/xx", cookie: viewer}, 400, "invalid_date"},
		{"anonymous", call{method: "GET", path: "/daily"}, 401, "admin_unauthorized"},
	}
	for _, tc := range cases {
		tc.call.path = "/api/v1/admin" + tc.call.path
		w := e.do(tc.call)
		if w.Code != tc.status || errCode(t, w) != tc.code {
			t.Errorf("%s: %d %s (want %d %s)", tc.name, w.Code, w.Body, tc.status, tc.code)
		}
	}
}
