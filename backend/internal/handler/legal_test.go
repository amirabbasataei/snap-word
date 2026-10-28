package handler_test

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/legal"
)

func newLegalRouter(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	site, err := legal.New()
	if err != nil {
		t.Fatalf("legal.New: %v", err)
	}
	r := gin.New()
	handler.LegalRoutes(r, handler.NewLegalHandler(site))
	// Stand-ins for the routes that must not collide with the legal pages.
	r.GET("/api/v1/ping", func(c *gin.Context) { c.String(http.StatusOK, "api") })
	r.GET("/admin/*filepath", func(c *gin.Context) { c.String(http.StatusOK, "admin") })
	return r
}

func legalGet(r *gin.Engine, method, path string, hdr ...string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(method, path, nil)
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	r.ServeHTTP(w, req)
	return w
}

func TestLegal_PagesServedPublicly(t *testing.T) {
	r := newLegalRouter(t)
	cases := []struct {
		path string
		want []string
	}{
		{"/terms", []string{"قوانین و مقررات استفاده از زنجیر", "سکه اعتبار مجازی", legal.ContactMail}},
		{"/privacy", []string{"سیاست حریم خصوصی زنجیر", "تپسل", "Kavenegar", "هنوز دکمهٔ «حذف حساب»", legal.ContactMail}},
	}
	for _, tc := range cases {
		w := legalGet(r, http.MethodGet, tc.path)
		if w.Code != http.StatusOK {
			t.Fatalf("%s: status %d", tc.path, w.Code)
		}
		if ct := w.Header().Get("Content-Type"); ct != "text/html; charset=utf-8" {
			t.Errorf("%s: Content-Type = %q", tc.path, ct)
		}
		body := w.Body.String()
		for _, frag := range append([]string{`<html lang="fa" dir="rtl">`, "<title>", `name="description"`, legal.UpdatedFa, legal.VersionFa}, tc.want...) {
			if !strings.Contains(body, frag) {
				t.Errorf("%s: body missing %q", tc.path, frag)
			}
		}
		csp := w.Header().Get("Content-Security-Policy")
		if !strings.Contains(csp, "default-src 'none'") || !strings.Contains(csp, "frame-ancestors 'none'") || strings.Contains(csp, "unsafe-inline") {
			t.Errorf("%s: CSP = %q", tc.path, csp)
		}
		if w.Header().Get("X-Content-Type-Options") != "nosniff" {
			t.Errorf("%s: missing nosniff", tc.path)
		}
	}
}

func TestLegal_NoExternalResources(t *testing.T) {
	r := newLegalRouter(t)
	external := regexp.MustCompile(`(?i)(src|href)="https?://[^"]*"`)
	for _, p := range []string{"/terms", "/privacy"} {
		body := legalGet(r, http.MethodGet, p).Body.String()
		for _, m := range external.FindAllString(body, -1) {
			// The only allowed absolute links are plain <a> to Tapsell's policy.
			if !strings.Contains(m, "play.tapsell.ir") {
				t.Errorf("%s: unexpected external reference %s", p, m)
			}
		}
		for _, bad := range []string{"<script", "fonts.googleapis", "gstatic"} {
			if strings.Contains(body, bad) {
				t.Errorf("%s: contains %q", p, bad)
			}
		}
	}
}

func TestLegal_TOCMatchesHeadings(t *testing.T) {
	r := newLegalRouter(t)
	heading := regexp.MustCompile(`<h2 id="([a-z0-9-]+)">`)
	for _, p := range []string{"/terms", "/privacy"} {
		body := legalGet(r, http.MethodGet, p).Body.String()
		ids := heading.FindAllStringSubmatch(body, -1)
		if len(ids) < 8 {
			t.Fatalf("%s: only %d headings", p, len(ids))
		}
		for _, m := range ids {
			if !strings.Contains(body, `href="#`+m[1]+`"`) {
				t.Errorf("%s: no TOC entry for #%s", p, m[1])
			}
		}
	}
	// Terms and Privacy link to each other.
	if !strings.Contains(legalGet(r, http.MethodGet, "/terms").Body.String(), `href="/privacy"`) {
		t.Error("terms does not link to privacy")
	}
	if !strings.Contains(legalGet(r, http.MethodGet, "/privacy").Body.String(), `href="/terms"`) {
		t.Error("privacy does not link to terms")
	}
}

func TestLegal_HeadAndConditionalGet(t *testing.T) {
	r := newLegalRouter(t)
	first := legalGet(r, http.MethodGet, "/terms")
	etag := first.Header().Get("ETag")
	if etag == "" {
		t.Fatal("no ETag")
	}
	if w := legalGet(r, http.MethodGet, "/terms", "If-None-Match", etag); w.Code != http.StatusNotModified {
		t.Errorf("conditional GET = %d, want 304", w.Code)
	}
	if w := legalGet(r, http.MethodHead, "/privacy"); w.Code != http.StatusOK || w.Body.Len() != 0 {
		t.Errorf("HEAD = %d with %d body bytes", w.Code, w.Body.Len())
	}
	if w := legalGet(r, http.MethodPost, "/terms"); w.Code != http.StatusNotFound {
		t.Errorf("POST /terms = %d, want 404", w.Code)
	}
}

func TestLegal_Assets(t *testing.T) {
	r := newLegalRouter(t)
	w := legalGet(r, http.MethodGet, "/legal/assets/vazirmatn-400.woff2")
	if w.Code != http.StatusOK || w.Header().Get("Content-Type") != "font/woff2" || w.Body.Len() < 1000 {
		t.Errorf("font: %d %q %d bytes", w.Code, w.Header().Get("Content-Type"), w.Body.Len())
	}
	if w := legalGet(r, http.MethodGet, "/legal/assets/OFL.txt"); w.Code != http.StatusOK || w.Header().Get("Content-Type") != "text/plain; charset=utf-8" {
		t.Errorf("licence: %d %q", w.Code, w.Header().Get("Content-Type"))
	}
	if w := legalGet(r, http.MethodGet, "/legal/assets/nope.woff2"); w.Code != http.StatusNotFound {
		t.Errorf("missing asset = %d", w.Code)
	}
	// Every font the stylesheet and layout reference must exist.
	page := legalGet(r, http.MethodGet, "/terms").Body.String()
	for _, f := range regexp.MustCompile(`/legal/assets/[a-z0-9.-]+`).FindAllString(page, -1) {
		if legalGet(r, http.MethodGet, f).Code != http.StatusOK {
			t.Errorf("page references missing %s", f)
		}
	}
}

func TestLegal_DoesNotTouchOtherRoutes(t *testing.T) {
	r := newLegalRouter(t)
	for p, want := range map[string]string{"/api/v1/ping": "api", "/admin/users": "admin"} {
		if w := legalGet(r, http.MethodGet, p); w.Code != http.StatusOK || w.Body.String() != want {
			t.Errorf("%s = %d %q", p, w.Code, w.Body.String())
		}
	}
	// Unknown paths keep the router's default 404.
	for _, p := range []string{"/termsx", "/legal", "/legal/other", "/privacy/x"} {
		if w := legalGet(r, http.MethodGet, p); w.Code != http.StatusNotFound {
			t.Errorf("%s = %d, want 404", p, w.Code)
		}
	}
}
