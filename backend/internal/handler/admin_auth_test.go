package handler_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

const adminPassword = "correct horse battery"

type adminEnv struct {
	router *gin.Engine
	auth   *service.AdminAuthService
	store  *testutil.FakeAdminStore
}

// newAdminEnv wires the same admin route shape as cmd/server/main.go, with a
// stand-in operator-only route so role denial can be exercised.
func newAdminEnv(t *testing.T, apiKey string, seedAdmin bool) *adminEnv {
	t.Helper()
	_, rdb := testutil.NewRedis(t)
	store := testutil.NewFakeAdminStore()
	cfg := &config.Config{AdminSessionTTL: 2 * time.Hour, AdminAPIKey: apiKey}
	auth := service.NewAdminAuthService(store, rdb, cfg)
	audit := service.NewAuditService(store)
	h := handler.NewAdminAuthHandler(auth, audit, apiKey)

	r := gin.New()
	adminAPI := r.Group("/api/v1/admin")
	adminAPI.POST("/auth/login", middleware.RequireCSRFHeader(), h.Login)
	admin := adminAPI.Group("", middleware.RequireAdmin(apiKey, auth))
	admin.POST("/auth/logout", h.Logout)
	admin.GET("/auth/me", h.Me)
	admin.PUT("/operator-thing", middleware.RequireRole(service.AdminRoleOperator), func(c *gin.Context) { c.Status(http.StatusOK) })

	env := &adminEnv{router: r, auth: auth, store: store}
	if seedAdmin {
		for name, role := range map[string]string{"boss": "owner", "peek": "viewer"} {
			if _, err := auth.CreateAdmin(t.Context(), name, adminPassword, role); err != nil {
				t.Fatal(err)
			}
		}
	}
	return env
}

type call struct {
	method, path, body, cookie, key string
	csrf                            bool
}

func (e *adminEnv) do(c call) *httptest.ResponseRecorder {
	req := httptest.NewRequest(c.method, c.path, bytes.NewReader([]byte(c.body)))
	req.Header.Set("Content-Type", "application/json")
	if c.csrf {
		req.Header.Set("X-Requested-With", config.AdminCSRFHeaderValue)
	}
	if c.key != "" {
		req.Header.Set("X-Admin-Key", c.key)
	}
	if c.cookie != "" {
		req.AddCookie(&http.Cookie{Name: config.AdminCookieName, Value: c.cookie})
	}
	w := httptest.NewRecorder()
	e.router.ServeHTTP(w, req)
	return w
}

func (e *adminEnv) login(t *testing.T, user string) string {
	t.Helper()
	w := e.do(call{method: "POST", path: "/api/v1/admin/auth/login", csrf: true,
		body: `{"username":"` + user + `","password":"` + adminPassword + `"}`})
	if w.Code != http.StatusOK {
		t.Fatalf("login %s: %d %s", user, w.Code, w.Body)
	}
	for _, c := range w.Result().Cookies() {
		if c.Name == config.AdminCookieName {
			return c.Value
		}
	}
	t.Fatal("login set no session cookie")
	return ""
}

func errCode(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var out struct {
		Error struct{ Code string } `json:"error"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return out.Error.Code
}

func TestAdminLogin_CookieAttributes(t *testing.T) {
	e := newAdminEnv(t, "", true)
	w := e.do(call{method: "POST", path: "/api/v1/admin/auth/login", csrf: true, body: `{"username":"boss","password":"` + adminPassword + `"}`})
	var cookie *http.Cookie
	for _, c := range w.Result().Cookies() {
		if c.Name == config.AdminCookieName {
			cookie = c
		}
	}
	if cookie == nil {
		t.Fatal("no cookie")
	}
	if !cookie.HttpOnly || cookie.SameSite != http.SameSiteStrictMode || cookie.Path != "/" || cookie.MaxAge <= 0 {
		t.Errorf("weak cookie: %+v", cookie)
	}
	if len(cookie.Value) != 64 {
		t.Errorf("token length %d", len(cookie.Value))
	}
}

func TestAdminLogin_FailuresAndValidation(t *testing.T) {
	e := newAdminEnv(t, "", true)
	login := func(body string, csrf bool) *httptest.ResponseRecorder {
		return e.do(call{method: "POST", path: "/api/v1/admin/auth/login", csrf: csrf, body: body})
	}
	if w := login(`{"username":"boss","password":"wrong-password"}`, true); w.Code != http.StatusUnauthorized || errCode(t, w) != "invalid_credentials" {
		t.Errorf("wrong password: %d %s", w.Code, w.Body)
	}
	if w := login(`{"username":"boss"}`, true); w.Code != http.StatusBadRequest {
		t.Errorf("missing password: %d", w.Code)
	}
	if w := login(`{"username":"boss","password":"`+adminPassword+`"}`, false); w.Code != http.StatusForbidden || errCode(t, w) != "csrf_required" {
		t.Errorf("login without CSRF header: %d %s", w.Code, w.Body)
	}
}

func TestAdminLogin_RateLimited(t *testing.T) {
	e := newAdminEnv(t, "", true)
	bad := call{method: "POST", path: "/api/v1/admin/auth/login", csrf: true, body: `{"username":"boss","password":"nope-nope-nope"}`}
	for i := 0; i < config.AdminLoginMaxFailsIP; i++ {
		e.do(bad)
	}
	w := e.do(call{method: "POST", path: "/api/v1/admin/auth/login", csrf: true, body: `{"username":"boss","password":"` + adminPassword + `"}`})
	if w.Code != http.StatusTooManyRequests || errCode(t, w) != "rate_limited" || w.Header().Get("Retry-After") == "" {
		t.Errorf("got %d %s", w.Code, w.Body)
	}
}

func TestAdminLogin_HiddenUntilConfigured(t *testing.T) {
	e := newAdminEnv(t, "", false)
	w := e.do(call{method: "POST", path: "/api/v1/admin/auth/login", csrf: true, body: `{"username":"boss","password":"` + adminPassword + `"}`})
	if w.Code != http.StatusNotFound {
		t.Errorf("no admin and no key: got %d", w.Code)
	}
}

func TestAdminSessionLifecycle_MeAndLogout(t *testing.T) {
	e := newAdminEnv(t, "", true)
	tok := e.login(t, "boss")

	w := e.do(call{method: "GET", path: "/api/v1/admin/auth/me", cookie: tok})
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"username":"boss"`) || !strings.Contains(w.Body.String(), `"role":"owner"`) {
		t.Fatalf("me: %d %s", w.Code, w.Body)
	}
	if w := e.do(call{method: "GET", path: "/api/v1/admin/auth/me"}); w.Code != http.StatusUnauthorized {
		t.Errorf("me without session: %d", w.Code)
	}

	if w := e.do(call{method: "POST", path: "/api/v1/admin/auth/logout", cookie: tok}); w.Code != http.StatusForbidden {
		t.Errorf("logout without CSRF header: %d", w.Code)
	}
	w = e.do(call{method: "POST", path: "/api/v1/admin/auth/logout", cookie: tok, csrf: true})
	if w.Code != http.StatusOK {
		t.Fatalf("logout: %d %s", w.Code, w.Body)
	}
	cleared := false
	for _, c := range w.Result().Cookies() {
		cleared = cleared || (c.Name == config.AdminCookieName && c.MaxAge < 0)
	}
	if !cleared {
		t.Error("logout did not clear the cookie")
	}
	if w := e.do(call{method: "GET", path: "/api/v1/admin/auth/me", cookie: tok}); w.Code != http.StatusUnauthorized {
		t.Errorf("session still valid after logout: %d", w.Code)
	}

	got := strings.Join(e.store.AuditActions(), ",")
	if got != "auth.login,auth.logout" {
		t.Errorf("audit trail = %q", got)
	}
}

func TestAdminRoleDenial(t *testing.T) {
	e := newAdminEnv(t, "", true)
	viewer, owner := e.login(t, "peek"), e.login(t, "boss")

	w := e.do(call{method: "PUT", path: "/api/v1/admin/operator-thing", cookie: viewer, csrf: true})
	if w.Code != http.StatusForbidden || errCode(t, w) != "insufficient_role" {
		t.Errorf("viewer: %d %s", w.Code, w.Body)
	}
	if w := e.do(call{method: "PUT", path: "/api/v1/admin/operator-thing", cookie: owner, csrf: true}); w.Code != http.StatusOK {
		t.Errorf("owner: %d", w.Code)
	}
}

func TestAdminKeyFallback(t *testing.T) {
	e := newAdminEnv(t, "s3cret", false)
	w := e.do(call{method: "GET", path: "/api/v1/admin/auth/me", key: "s3cret"})
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"username":"script"`) || !strings.Contains(w.Body.String(), `"via":"key"`) {
		t.Errorf("me via key: %d %s", w.Code, w.Body)
	}
	// Scripts send no CSRF header and must still be able to write.
	if w := e.do(call{method: "PUT", path: "/api/v1/admin/operator-thing", key: "s3cret"}); w.Code != http.StatusOK {
		t.Errorf("key write: %d", w.Code)
	}
	if w := e.do(call{method: "GET", path: "/api/v1/admin/auth/me", key: "wrong"}); w.Code != http.StatusUnauthorized || errCode(t, w) != "invalid_admin_key" {
		t.Errorf("wrong key: %d %s", w.Code, w.Body)
	}
}
