import { ApiError } from './errors'

const BASE = '/api/v1/admin'
const CSRF_HEADER = 'X-Requested-With'
const CSRF_VALUE = 'zanjir-admin'

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'

let onUnauthorized: (() => void) | null = null

/** AuthProvider registers this so a 401 anywhere drops back to the login page. */
export function setUnauthorizedHandler(fn: (() => void) | null) {
  onUnauthorized = fn
}

interface Options {
  method?: Method
  body?: unknown
  signal?: AbortSignal
  /** Skip the global 401 → login redirect (used by login and the `me` probe). */
  skipUnauthorized?: boolean
}

/**
 * Same-origin fetch wrapper for /api/v1/admin/*. Sends the session cookie,
 * adds the CSRF header on every request (harmless on GET), unwraps the
 * `{data}` envelope and turns failures into `ApiError`.
 */
export async function api<T>(path: string, opts: Options = {}): Promise<T> {
  const { method = 'GET', body, signal, skipUnauthorized } = opts
  const headers: Record<string, string> = { [CSRF_HEADER]: CSRF_VALUE }
  let payload: BodyInit | undefined
  if (body instanceof FormData) {
    payload = body
  } else if (body !== undefined) {
    headers['Content-Type'] = 'application/json'
    payload = JSON.stringify(body)
  }

  let res: Response
  try {
    res = await fetch(`${BASE}${path}`, { method, headers, body: payload, credentials: 'include', signal })
  } catch (e) {
    if (e instanceof DOMException && e.name === 'AbortError') throw e
    throw new ApiError(0, 'network_error')
  }

  if (res.ok) {
    if (res.status === 204) return undefined as T
    const json = (await res.json().catch(() => null)) as { data?: T } | null
    return (json && 'data' in json ? json.data : json) as T
  }

  const json = (await res.json().catch(() => null)) as { error?: { code?: string } } | null
  const code = json?.error?.code ?? (res.status >= 500 ? 'internal_error' : 'unknown_error')
  const ra = Number(res.headers.get('Retry-After'))
  if (res.status === 401 && !skipUnauthorized) onUnauthorized?.()
  throw new ApiError(res.status, code, Number.isFinite(ra) && ra > 0 ? ra : undefined)
}
