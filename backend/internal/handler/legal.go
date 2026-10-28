package handler

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"mime"
	"net/http"
	"path"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/legal"
)

type legalDoc struct {
	html []byte
	csp  string
	etag string
}

type legalAsset struct {
	data  []byte
	ctype string
	etag  string
}

// LegalHandler serves the public Terms and Privacy pages and the font files
// they use. Both pages are rendered once at startup (internal/legal).
type LegalHandler struct {
	docs   map[string]legalDoc
	assets map[string]legalAsset
}

func NewLegalHandler(site *legal.Site) *LegalHandler {
	h := &LegalHandler{docs: map[string]legalDoc{}, assets: map[string]legalAsset{}}
	for slug, p := range site.Pages {
		h.docs[slug] = legalDoc{html: p.HTML, csp: p.CSP, etag: etagOf(p.HTML)}
	}
	for name, b := range site.Assets {
		ct := mime.TypeByExtension(path.Ext(name))
		// The runtime image has no MIME database, so name the types explicitly.
		switch path.Ext(name) {
		case ".woff2":
			ct = "font/woff2"
		case ".txt":
			ct = "text/plain; charset=utf-8"
		}
		if ct == "" {
			ct = "application/octet-stream"
		}
		h.assets[name] = legalAsset{data: b, ctype: ct, etag: etagOf(b)}
	}
	return h
}

func etagOf(b []byte) string {
	sum := sha256.Sum256(b)
	return `"` + hex.EncodeToString(sum[:8]) + `"`
}

// Page serves one document.
func (h *LegalHandler) Page(slug string) gin.HandlerFunc {
	return func(c *gin.Context) {
		d, ok := h.docs[slug]
		if !ok {
			c.Status(http.StatusNotFound)
			return
		}
		hd := c.Writer.Header()
		hd.Set("Content-Type", "text/html; charset=utf-8")
		hd.Set("Content-Language", "fa")
		hd.Set("Content-Security-Policy", d.csp)
		hd.Set("X-Content-Type-Options", "nosniff")
		hd.Set("X-Frame-Options", "DENY")
		hd.Set("Referrer-Policy", "no-referrer")
		hd.Set("Cache-Control", "public, max-age=3600")
		hd.Set("ETag", d.etag)
		http.ServeContent(c.Writer, c.Request, "", time.Time{}, bytes.NewReader(d.html))
	}
}

// Asset serves a font or licence file from /legal/assets/:name.
func (h *LegalHandler) Asset(c *gin.Context) {
	a, ok := h.assets[c.Param("name")]
	if !ok {
		c.Status(http.StatusNotFound)
		return
	}
	hd := c.Writer.Header()
	hd.Set("Content-Type", a.ctype)
	hd.Set("X-Content-Type-Options", "nosniff")
	hd.Set("Cache-Control", "public, max-age=86400")
	// Fonts are fetched with CORS mode by <link rel=preload crossorigin>.
	hd.Set("Access-Control-Allow-Origin", "*")
	hd.Set("ETag", a.etag)
	http.ServeContent(c.Writer, c.Request, "", time.Time{}, bytes.NewReader(a.data))
}

// LegalRoutes mounts /terms, /privacy and /legal/assets/:name. They sit outside
// /api/v1 and /admin, and need no login.
func LegalRoutes(r *gin.Engine, h *LegalHandler) {
	get := []string{http.MethodGet, http.MethodHead}
	r.Match(get, "/"+legal.Terms, h.Page(legal.Terms))
	r.Match(get, "/"+legal.Privacy, h.Page(legal.Privacy))
	r.Match(get, "/legal/assets/:name", h.Asset)
}
