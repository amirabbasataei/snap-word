/**
 * Public URL prefix the panel is mounted under (e.g. `/zanjir` behind a
 * reverse proxy that strips it), derived from Vite's `base` (`<prefix>/admin/`).
 * Empty when served straight from the Go server at `/admin/`.
 */
export const PREFIX = import.meta.env.BASE_URL.replace(/admin\/?$/, '').replace(/\/+$/, '')

/** Router basename: `<prefix>/admin`. */
export const ROUTER_BASENAME = `${PREFIX}/admin`

/** Prefixes an absolute API path (`/api/v1/...`) with the public prefix. */
export const withPrefix = (path: string) => `${PREFIX}${path}`
