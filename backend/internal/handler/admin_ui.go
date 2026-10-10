package handler

import (
	"bytes"
	"io/fs"
	"log/slog"
	"mime"
	"net/http"
	"path"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
)

// adminCSP: the panel is a same-origin SPA with no third-party resources.
// style-src allows inline styles because Radix positions popovers with them.
const adminCSP = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " +
	"img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; " +
	"frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"

const panelNotBuiltPage = `<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">` +
	`<meta name="viewport" content="width=device-width, initial-scale=1"><title>پنل ساخته نشده است</title></head>` +
	`<body style="font-family:system-ui,sans-serif;max-width:32rem;margin:4rem auto;padding:0 1rem">` +
	`<h1>پنل مدیریت ساخته نشده است</h1>` +
	`<p>برای ساخت پنل دستور <code dir="ltr">pnpm -C admin build</code> را اجرا و سرور را دوباره بسازید.</p></body></html>`

// AdminUIHandler serves the embedded admin SPA under /admin with an
// index.html fallback for client-side routes.
type AdminUIHandler struct {
	files   fs.FS
	index   []byte
	enabled func(c *gin.Context) bool
}

// NewAdminUIHandler reads index.html once at startup. `enabled` mirrors the
// admin API's 404-when-unconfigured rule so a bare server exposes nothing.
func NewAdminUIHandler(files fs.FS, enabled func(c *gin.Context) bool) *AdminUIHandler {
	h := &AdminUIHandler{files: files, enabled: enabled}
	if b, err := fs.ReadFile(files, "index.html"); err == nil {
		h.index = b
	} else {
		slog.Warn("admin panel not built: dist/index.html missing", "error", err)
	}
	return h
}

// Serve handles GET/HEAD /admin and /admin/*filepath.
func (h *AdminUIHandler) Serve(c *gin.Context) {
	if h.enabled != nil && !h.enabled(c) {
		c.Status(http.StatusNotFound)
		return
	}
	setAdminUIHeaders(c)

	if h.index == nil {
		c.Data(http.StatusServiceUnavailable, "text/html; charset=utf-8", []byte(panelNotBuiltPage))
		return
	}

	name := strings.TrimPrefix(path.Clean("/"+c.Param("filepath")), "/")
	if name != "" && name != "index.html" {
		if h.serveFile(c, name) {
			return
		}
		// A missing file with an extension is a broken asset link, not a route.
		if path.Ext(name) != "" {
			c.Status(http.StatusNotFound)
			return
		}
	}

	c.Header("Cache-Control", "no-cache")
	c.Data(http.StatusOK, "text/html; charset=utf-8", h.index)
}

func (h *AdminUIHandler) serveFile(c *gin.Context, name string) bool {
	f, err := h.files.Open(name)
	if err != nil {
		return false
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || info.IsDir() {
		return false
	}
	data, err := fs.ReadFile(h.files, name)
	if err != nil {
		return false
	}

	ctype := mime.TypeByExtension(path.Ext(name))
	if ctype == "" {
		ctype = http.DetectContentType(data)
	}
	// Vite fingerprints everything under assets/; other files (fonts, icon) can change.
	if strings.HasPrefix(name, "assets/") {
		c.Header("Cache-Control", "public, max-age=31536000, immutable")
	} else {
		c.Header("Cache-Control", "public, max-age=86400")
	}
	c.Header("Content-Type", ctype)
	http.ServeContent(c.Writer, c.Request, name, time.Time{}, bytes.NewReader(data))
	return true
}

func setAdminUIHeaders(c *gin.Context) {
	h := c.Writer.Header()
	h.Set("Content-Security-Policy", adminCSP)
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("X-Frame-Options", "DENY")
	h.Set("Referrer-Policy", "no-referrer")
}

// AdminUIRoutes mounts the panel on the router.
func AdminUIRoutes(r *gin.Engine, h *AdminUIHandler, allowlist string) {
	g := r.Group("", middleware.RequireAdminIP(allowlist))
	g.GET("/admin", h.Serve)
	g.HEAD("/admin", h.Serve)
	g.GET("/admin/*filepath", h.Serve)
	g.HEAD("/admin/*filepath", h.Serve)
}
