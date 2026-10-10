package handler_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/handler"
)

func newUIRouter(files fstest.MapFS, enabled bool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	h := handler.NewAdminUIHandler(files, func(*gin.Context) bool { return enabled })
	handler.AdminUIRoutes(r, h, "")
	return r
}

func uiGet(r *gin.Engine, path string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
	return w
}

func builtPanel() fstest.MapFS {
	return fstest.MapFS{
		"index.html":       {Data: []byte("<html>panel</html>")},
		"assets/app.js":    {Data: []byte("console.log(1)")},
		"fonts/font.woff2": {Data: []byte("font")},
	}
}

func TestAdminUI_ServesIndexAndSPAFallback(t *testing.T) {
	r := newUIRouter(builtPanel(), true)
	for _, p := range []string{"/admin", "/admin/", "/admin/users/42", "/admin/login"} {
		w := uiGet(r, p)
		if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), "panel") {
			t.Errorf("%s: got %d %q", p, w.Code, w.Body.String())
		}
		if got := w.Header().Get("Cache-Control"); got != "no-cache" {
			t.Errorf("%s: index Cache-Control = %q", p, got)
		}
		if !strings.Contains(w.Header().Get("Content-Security-Policy"), "frame-ancestors 'none'") {
			t.Errorf("%s: missing CSP", p)
		}
		if w.Header().Get("X-Frame-Options") != "DENY" {
			t.Errorf("%s: missing X-Frame-Options", p)
		}
	}
}

func TestAdminUI_AssetsCachingAndMissing(t *testing.T) {
	r := newUIRouter(builtPanel(), true)

	w := uiGet(r, "/admin/assets/app.js")
	if w.Code != http.StatusOK || !strings.Contains(w.Header().Get("Cache-Control"), "immutable") {
		t.Errorf("asset: %d cache=%q", w.Code, w.Header().Get("Cache-Control"))
	}
	if !strings.Contains(w.Header().Get("Content-Type"), "javascript") {
		t.Errorf("asset content-type = %q", w.Header().Get("Content-Type"))
	}
	if w := uiGet(r, "/admin/fonts/font.woff2"); w.Code != http.StatusOK || strings.Contains(w.Header().Get("Cache-Control"), "immutable") {
		t.Errorf("font: %d cache=%q", w.Code, w.Header().Get("Cache-Control"))
	}
	// A missing file with an extension is a 404, not the SPA shell.
	if w := uiGet(r, "/admin/assets/gone.js"); w.Code != http.StatusNotFound {
		t.Errorf("missing asset: got %d", w.Code)
	}
	// Directory traversal cannot escape the embedded FS.
	if w := uiGet(r, "/admin/..%2f..%2fgo.mod"); w.Code == http.StatusOK && strings.Contains(w.Body.String(), "module") {
		t.Error("traversal leaked a file")
	}
}

func TestAdminUI_DisabledIs404(t *testing.T) {
	r := newUIRouter(builtPanel(), false)
	if w := uiGet(r, "/admin"); w.Code != http.StatusNotFound {
		t.Errorf("disabled: got %d", w.Code)
	}
}

func TestAdminUI_NotBuiltFallback(t *testing.T) {
	r := newUIRouter(fstest.MapFS{".gitkeep": {}}, true)
	w := uiGet(r, "/admin")
	if w.Code != http.StatusServiceUnavailable || !strings.Contains(w.Body.String(), "pnpm -C admin build") {
		t.Errorf("not built: %d %q", w.Code, w.Body.String())
	}
}
