// Package adminui embeds the built admin panel (admin/ → `pnpm -C admin build`).
package adminui

import (
	"embed"
	"io/fs"
)

// dist holds the Vite build output. Only dist/.gitkeep is committed, so a
// checkout without a panel build still compiles; the handler then serves a
// "panel not built" page.
//
//go:embed all:dist
var dist embed.FS

// FS returns the built panel rooted at its index.html.
func FS() fs.FS {
	sub, err := fs.Sub(dist, "dist")
	if err != nil {
		// Unreachable: "dist" is guaranteed to exist by the embed directive.
		panic(err)
	}
	return sub
}
