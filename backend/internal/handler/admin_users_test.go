package handler_test

import (
	"net/http"
	"strings"
	"testing"

	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

const someUser = "11111111-1111-1111-1111-111111111111"

// usersEnv mounts the users routes exactly as cmd/server/main.go does. The
// service has no store: every case here must be decided before it is reached.
func usersEnv(t *testing.T) *adminEnv {
	t.Helper()
	e := newAdminEnv(t, "", true)
	h := handler.NewAdminUsersHandler(service.NewAdminUserService(nil, nil, nil, service.NewAuditService(e.store)))
	admin := e.router.Group("/api/v1/admin", middleware.RequireAdmin("", e.auth))
	admin.GET("/users", h.List)
	admin.GET("/users/:id", h.Get)
	op := admin.Group("", middleware.RequireRole(service.AdminRoleOperator))
	op.POST("/users/:id/coins", h.Coins)
	op.POST("/users/:id/premium", h.Premium)
	op.PATCH("/users/:id/username", h.Rename)
	op.POST("/users/:id/avatar/clear", h.ClearAvatar)
	op.POST("/users/:id/ban", h.Ban)
	op.POST("/users/:id/unban", h.Unban)
	return e
}

func TestAdminUsers_ViewerCannotMutate(t *testing.T) {
	e := usersEnv(t)
	viewer := e.login(t, "peek")
	for _, c := range []struct{ method, path string }{
		{"POST", "/users/" + someUser + "/coins"},
		{"POST", "/users/" + someUser + "/premium"},
		{"PATCH", "/users/" + someUser + "/username"},
		{"POST", "/users/" + someUser + "/avatar/clear"},
		{"POST", "/users/" + someUser + "/ban"},
		{"POST", "/users/" + someUser + "/unban"},
	} {
		w := e.do(call{method: c.method, path: "/api/v1/admin" + c.path, cookie: viewer, csrf: true, body: `{"reason":"because"}`})
		if w.Code != http.StatusForbidden || errCode(t, w) != "insufficient_role" {
			t.Errorf("%s %s: %d %s", c.method, c.path, w.Code, w.Body)
		}
	}
	for _, a := range e.store.AuditActions() {
		if strings.HasPrefix(a, "user.") {
			t.Errorf("denied request wrote audit row %q", a)
		}
	}
}

func TestAdminUsers_MutationNeedsCSRFHeader(t *testing.T) {
	e := usersEnv(t)
	owner := e.login(t, "boss")
	w := e.do(call{method: "POST", path: "/api/v1/admin/users/" + someUser + "/ban", cookie: owner, body: `{"reason":"cheating"}`})
	if w.Code != http.StatusForbidden || errCode(t, w) != "csrf_required" {
		t.Errorf("%d %s", w.Code, w.Body)
	}
}

func TestAdminUsers_ErrorMapping(t *testing.T) {
	e := usersEnv(t)
	owner := e.login(t, "boss")
	viewer := e.login(t, "peek")

	cases := []struct {
		name   string
		call   call
		status int
		code   string
	}{
		{"reason required", call{method: "POST", path: "/users/" + someUser + "/ban", cookie: owner, csrf: true, body: `{"reason":"x"}`}, 400, "reason_required"},
		{"missing reason", call{method: "POST", path: "/users/" + someUser + "/unban", cookie: owner, csrf: true, body: `{}`}, 400, "reason_required"},
		{"bad json", call{method: "POST", path: "/users/" + someUser + "/ban", cookie: owner, csrf: true, body: `nope`}, 400, "validation_error"},
		{"unknown premium action", call{method: "POST", path: "/users/" + someUser + "/premium", cookie: owner, csrf: true, body: `{"action":"gift","reason":"abc"}`}, 400, "validation_error"},
		{"bad amount", call{method: "POST", path: "/users/" + someUser + "/coins", cookie: owner, csrf: true, body: `{"mode":"direct","amount":0,"reason":"abc"}`}, 400, "invalid_amount"},
		{"bad days", call{method: "POST", path: "/users/" + someUser + "/premium", cookie: owner, csrf: true, body: `{"action":"grant","days":0,"reason":"abc"}`}, 400, "invalid_days"},
		{"malformed id", call{method: "POST", path: "/users/nope/ban", cookie: owner, csrf: true, body: `{"reason":"cheating"}`}, 404, "user_not_found"},
		{"detail malformed id", call{method: "GET", path: "/users/nope", cookie: viewer}, 404, "user_not_found"},
		{"bad sort (viewer may read)", call{method: "GET", path: "/users?sort=otp_code", cookie: viewer}, 400, "validation_error"},
		{"bad filter", call{method: "GET", path: "/users?filter=all", cookie: viewer}, 400, "validation_error"},
		{"bad page", call{method: "GET", path: "/users?page=abc", cookie: viewer}, 400, "validation_error"},
		{"anonymous", call{method: "GET", path: "/users"}, 401, "admin_unauthorized"},
	}
	for _, tc := range cases {
		tc.call.path = "/api/v1/admin" + tc.call.path
		w := e.do(tc.call)
		if w.Code != tc.status || errCode(t, w) != tc.code {
			t.Errorf("%s: %d %s (want %d %s)", tc.name, w.Code, w.Body, tc.status, tc.code)
		}
	}
}
