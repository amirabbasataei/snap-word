// Package legal renders the public Terms (/terms) and Privacy (/privacy) pages.
//
// The pages are plain server-rendered HTML with inline CSS and a self-hosted
// font, embedded in the binary so they ship with the normal backend deploy and
// work without any third-party request (Google Fonts is unreliable from Iran).
// Everything is rendered once at startup into immutable byte slices.
package legal

import (
	"bytes"
	"crypto/sha256"
	"embed"
	"encoding/base64"
	"fmt"
	"html"
	"html/template"
	"io/fs"
	"regexp"
	"strings"
)

// Document version. Bump Version and Updated* together whenever the text of
// either page changes in a way users should notice; a future re-acceptance
// flow can compare against Version. Updated is the same day in both calendars.
const (
	Version     = "1.0"
	VersionFa   = "۱٫۰"
	UpdatedISO  = "2026-10-27"
	UpdatedJal  = "1405/08/05"
	UpdatedFa   = "۱۴۰۵/۰۸/۰۵"
	OwnerFa     = "امیرعباس عطائی"
	OwnerEn     = "AmirAbbas Ataei"
	ContactMail = "a.ataei1991@gmail.com"
)

// Slugs of the two documents, also their URL paths.
const (
	Terms   = "terms"
	Privacy = "privacy"
)

//go:embed templates/*.html templates/legal.css
var templateFS embed.FS

//go:embed assets/*
var assetFS embed.FS

// Page is a fully rendered document.
type Page struct {
	HTML []byte
	// CSP is the Content-Security-Policy for this page: the stylesheet is
	// inline, so it is allowed by hash instead of 'unsafe-inline'.
	CSP string
}

// Site holds both pages and the font files (plus the font licence) they reference.
type Site struct {
	Pages map[string]Page
	Assets map[string][]byte // file name under /legal/assets/
}

type pageMeta struct {
	Title       string
	Heading     string
	Description string
}

var metas = map[string]pageMeta{
	Terms: {
		Title:       "قوانین و مقررات استفاده",
		Heading:     "قوانین و مقررات استفاده از زنجیر",
		Description: "قوانین و مقررات استفادهٔ زنجیر، بازی زنجیرهٔ کلمات فارسی: حساب کاربری، رفتار مجاز، سکه و جایزه‌ها، اشتراک ویژه و مسدودسازی.",
	},
	Privacy: {
		Title:       "حریم خصوصی",
		Heading:     "سیاست حریم خصوصی زنجیر",
		Description: "سیاست حریم خصوصی زنجیر: چه اطلاعاتی جمع می‌کنیم، چرا، با چه کسانی به اشتراک می‌گذاریم، تا کی نگه می‌داریم و چطور حذفش را بخواهید.",
	},
}

// data is what the body and layout templates see.
type data struct {
	pageMeta
	Slug       string
	VersionFa  string
	UpdatedFa  string
	UpdatedISO string
	Owner      string
	OwnerEn    string
	Email      string
	CSS        template.CSS
	TOC        template.HTML
	Body       template.HTML
}

var h2Re = regexp.MustCompile(`<h2 id="([a-z0-9-]+)">(.+?)</h2>`)

// New renders both pages.
func New() (*Site, error) {
	css, err := fs.ReadFile(templateFS, "templates/legal.css")
	if err != nil {
		return nil, fmt.Errorf("read css: %w", err)
	}
	sum := sha256.Sum256(css)
	csp := "default-src 'none'; style-src 'sha256-" + base64.StdEncoding.EncodeToString(sum[:]) + "'; " +
		"font-src 'self'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

	s := &Site{Pages: map[string]Page{}, Assets: map[string][]byte{}}
	entries, err := fs.ReadDir(assetFS, "assets")
	if err != nil {
		return nil, fmt.Errorf("read assets: %w", err)
	}
	for _, e := range entries {
		b, err := fs.ReadFile(assetFS, "assets/"+e.Name())
		if err != nil {
			return nil, fmt.Errorf("read asset %s: %w", e.Name(), err)
		}
		s.Assets[e.Name()] = b
	}

	for slug, meta := range metas {
		d := data{
			pageMeta: meta, Slug: slug, VersionFa: VersionFa, UpdatedFa: UpdatedFa,
			UpdatedISO: UpdatedISO, Owner: OwnerFa, OwnerEn: OwnerEn, Email: ContactMail,
			CSS: template.CSS(css),
		}
		bodyT, err := template.ParseFS(templateFS, "templates/"+slug+".html")
		if err != nil {
			return nil, fmt.Errorf("parse %s: %w", slug, err)
		}
		var body bytes.Buffer
		if err := bodyT.ExecuteTemplate(&body, "body", d); err != nil {
			return nil, fmt.Errorf("render %s body: %w", slug, err)
		}
		d.Body = template.HTML(body.String())
		d.TOC = buildTOC(body.String())

		layoutT, err := template.ParseFS(templateFS, "templates/layout.html")
		if err != nil {
			return nil, fmt.Errorf("parse layout: %w", err)
		}
		var out bytes.Buffer
		if err := layoutT.ExecuteTemplate(&out, "layout", d); err != nil {
			return nil, fmt.Errorf("render %s: %w", slug, err)
		}
		s.Pages[slug] = Page{HTML: out.Bytes(), CSP: csp}
	}
	return s, nil
}

// buildTOC lists every <h2 id="…"> of the rendered body, so the headings are
// written once, in the content, and the table of contents can never drift.
func buildTOC(body string) template.HTML {
	var b strings.Builder
	b.WriteString("<ol>")
	for _, m := range h2Re.FindAllStringSubmatch(body, -1) {
		fmt.Fprintf(&b, `<li><a href="#%s">%s</a></li>`, m[1], stripTags(m[2]))
	}
	b.WriteString("</ol>")
	return template.HTML(b.String())
}

var tagRe = regexp.MustCompile(`<[^>]*>`)

// stripTags drops markup from heading text and re-escapes what is left.
func stripTags(s string) string {
	return html.EscapeString(html.UnescapeString(tagRe.ReplaceAllString(s, "")))
}
