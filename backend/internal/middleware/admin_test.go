package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/service"
)

// fakeSessions implements AdminSessions with a fixed token table.
type fakeSessions struct {
	enabled  bool
	sessions map[string]*service.AdminSession
}

func (f *fakeSessions) Enabled(context.Context) bool { return f.enabled }

func (f *fakeSessions) Authenticate(_ context.Context, token string) (*service.AdminSession, error) {
	if s, ok := f.sessions[token]; ok {
		return s, nil
	}
	return nil, service.ErrAdminSessionInvalid
}

func newSessions() *fakeSessions {
	return &fakeSessions{enabled: true, sessions: map[string]*service.AdminSession{
		"owner-tok":  {Token: "owner-tok", AdminID: "a1", Username: "boss", Role: service.AdminRoleOwner},
		"viewer-tok": {Token: "viewer-tok", AdminID: "a2", Username: "peek", Role: service.AdminRoleViewer},
	}}
}

type adminReq struct {
	method, cookie, key, csrf string
}

func doAdmin(configuredKey string, sessions AdminSessions, minRole string, r adminReq) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	e := gin.New()
	handlers := []gin.HandlerFunc{RequireAdmin(configuredKey, sessions)}
	if minRole != "" {
		handlers = append(handlers, RequireRole(minRole))
	}
	handlers = append(handlers, func(c *gin.Context) { c.String(http.StatusOK, AdminActor(c).Name) })
	e.Any("/x", handlers...)

	method := r.method
	if method == "" {
		method = http.MethodGet
	}
	req := httptest.NewRequest(method, "/x", nil)
	if r.cookie != "" {
		req.AddCookie(&http.Cookie{Name: config.AdminCookieName, Value: r.cookie})
	}
	if r.key != "" {
		req.Header.Set("X-Admin-Key", r.key)
	}
	if r.csrf != "" {
		req.Header.Set("X-Requested-With", r.csrf)
	}
	w := httptest.NewRecorder()
	e.ServeHTTP(w, req)
	return w
}

func TestRequireAdmin_Key(t *testing.T) {
	for name, tc := range map[string]struct {
		configured string
		sessions   AdminSessions
		key        string
		want       int
	}{
		"nothing configured hides the routes": {"", nil, "anything", http.StatusNotFound},
		"no admins and no key hides them":     {"", &fakeSessions{}, "", http.StatusNotFound},
		"missing credentials":                 {"s3cret", nil, "", http.StatusUnauthorized},
		"wrong key":                           {"s3cret", nil, "wrong", http.StatusUnauthorized},
		"right key":                           {"s3cret", nil, "s3cret", http.StatusOK},
		"key sent but none configured":        {"", newSessions(), "guess", http.StatusUnauthorized},
	} {
		if got := doAdmin(tc.configured, tc.sessions, "", adminReq{key: tc.key}).Code; got != tc.want {
			t.Errorf("%s: got %d, want %d", name, got, tc.want)
		}
	}
}

func TestRequireAdmin_KeyActsAsOwnerScript(t *testing.T) {
	w := doAdmin("s3cret", nil, service.AdminRoleOwner, adminReq{key: "s3cret"})
	if w.Code != http.StatusOK || w.Body.String() != AdminScriptActor {
		t.Errorf("got %d %q", w.Code, w.Body.String())
	}
}

func TestRequireAdmin_KeyNeedsNoCSRFHeader(t *testing.T) {
	if got := doAdmin("s3cret", nil, "", adminReq{method: http.MethodPut, key: "s3cret"}).Code; got != http.StatusOK {
		t.Errorf("key-authenticated PUT: got %d", got)
	}
}

func TestRequireAdmin_PanelEnabledByAdminUserAlone(t *testing.T) {
	w := doAdmin("", newSessions(), "", adminReq{cookie: "owner-tok"})
	if w.Code != http.StatusOK || w.Body.String() != "boss" {
		t.Errorf("got %d %q", w.Code, w.Body.String())
	}
}

func TestRequireAdmin_Cookie(t *testing.T) {
	s := newSessions()
	if got := doAdmin("", s, "", adminReq{cookie: "bogus"}).Code; got != http.StatusUnauthorized {
		t.Errorf("unknown session: got %d", got)
	}
	if got := doAdmin("", s, "", adminReq{}).Code; got != http.StatusUnauthorized {
		t.Errorf("no credentials: got %d", got)
	}
	if got := doAdmin("", s, "", adminReq{cookie: "owner-tok"}).Code; got != http.StatusOK {
		t.Errorf("valid GET: got %d", got)
	}
}

func TestRequireAdmin_CSRFGuardOnCookieWrites(t *testing.T) {
	s := newSessions()
	for _, m := range []string{http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete} {
		if got := doAdmin("", s, "", adminReq{method: m, cookie: "owner-tok"}).Code; got != http.StatusForbidden {
			t.Errorf("%s without header: got %d, want 403", m, got)
		}
		if got := doAdmin("", s, "", adminReq{method: m, cookie: "owner-tok", csrf: "XMLHttpRequest"}).Code; got != http.StatusForbidden {
			t.Errorf("%s with wrong header value: got %d, want 403", m, got)
		}
		if got := doAdmin("", s, "", adminReq{method: m, cookie: "owner-tok", csrf: config.AdminCSRFHeaderValue}).Code; got != http.StatusOK {
			t.Errorf("%s with header: got %d, want 200", m, got)
		}
	}
}

func TestRequireRole(t *testing.T) {
	s := newSessions()
	if got := doAdmin("", s, service.AdminRoleOperator, adminReq{cookie: "viewer-tok"}).Code; got != http.StatusForbidden {
		t.Errorf("viewer on operator route: got %d", got)
	}
	if got := doAdmin("", s, service.AdminRoleViewer, adminReq{cookie: "viewer-tok"}).Code; got != http.StatusOK {
		t.Errorf("viewer on viewer route: got %d", got)
	}
	if got := doAdmin("", s, service.AdminRoleOperator, adminReq{cookie: "owner-tok"}).Code; got != http.StatusOK {
		t.Errorf("owner on operator route: got %d", got)
	}
}

func TestRequireAdminIP(t *testing.T) {
	gin.SetMode(gin.TestMode)
	probe := func(allow, remote string) int {
		e := gin.New()
		e.Use(RequireAdminIP(allow))
		e.GET("/x", func(c *gin.Context) { c.Status(http.StatusOK) })
		req := httptest.NewRequest(http.MethodGet, "/x", nil)
		req.RemoteAddr = remote + ":1234"
		w := httptest.NewRecorder()
		e.ServeHTTP(w, req)
		return w.Code
	}
	if got := probe("", "9.9.9.9"); got != http.StatusOK {
		t.Errorf("empty allowlist: got %d", got)
	}
	if got := probe("10.0.0.0/8, 203.0.113.7", "10.1.2.3"); got != http.StatusOK {
		t.Errorf("CIDR match: got %d", got)
	}
	if got := probe("10.0.0.0/8, 203.0.113.7", "203.0.113.7"); got != http.StatusOK {
		t.Errorf("single IP match: got %d", got)
	}
	if got := probe("10.0.0.0/8", "9.9.9.9"); got != http.StatusNotFound {
		t.Errorf("outside allowlist: got %d", got)
	}
}
