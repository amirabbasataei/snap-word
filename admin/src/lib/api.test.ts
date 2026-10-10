import { afterEach, describe, expect, it, vi } from 'vitest'
import { api, setUnauthorizedHandler } from './api'
import { ApiError } from './errors'

function mockFetch(res: Response | Error) {
  const fn = vi.fn(async () => {
    if (res instanceof Error) throw res
    return res
  })
  vi.stubGlobal('fetch', fn)
  return fn
}

afterEach(() => {
  vi.unstubAllGlobals()
  setUnauthorizedHandler(null)
})

describe('api()', () => {
  it('sends cookies and the CSRF header, and unwraps {data}', async () => {
    const f = mockFetch(Response.json({ data: { ok: true } }))
    await expect(api('/auth/me')).resolves.toEqual({ ok: true })
    const [url, init] = f.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe('/api/v1/admin/auth/me')
    expect(init.credentials).toBe('include')
    expect((init.headers as Record<string, string>)['X-Requested-With']).toBe('zanjir-admin')
  })

  it('JSON-encodes bodies on POST', async () => {
    const f = mockFetch(Response.json({ data: {} }))
    await api('/auth/login', { method: 'POST', body: { username: 'a', password: 'b' } })
    const init = (f.mock.calls[0] as unknown as [string, RequestInit])[1]
    expect(init.method).toBe('POST')
    expect(init.body).toBe('{"username":"a","password":"b"}')
    expect((init.headers as Record<string, string>)['Content-Type']).toBe('application/json')
  })

  it('maps error envelopes to ApiError with Retry-After', async () => {
    mockFetch(Response.json({ error: { code: 'rate_limited', message: 'x' } }, { status: 429, headers: { 'Retry-After': '900' } }))
    const err = await api('/auth/login', { method: 'POST' }).catch((e) => e)
    expect(err).toBeInstanceOf(ApiError)
    expect(err).toMatchObject({ status: 429, code: 'rate_limited', retryAfter: 900 })
  })

  it('calls the unauthorized handler on 401 unless skipped', async () => {
    const handler = vi.fn()
    setUnauthorizedHandler(handler)
    mockFetch(Response.json({ error: { code: 'admin_unauthorized' } }, { status: 401 }))
    await api('/x').catch(() => {})
    expect(handler).toHaveBeenCalledTimes(1)

    mockFetch(Response.json({ error: { code: 'invalid_credentials' } }, { status: 401 }))
    await api('/auth/login', { method: 'POST', skipUnauthorized: true }).catch(() => {})
    expect(handler).toHaveBeenCalledTimes(1)
  })

  it('reports network failures with a Persian-mapped code', async () => {
    mockFetch(new TypeError('Failed to fetch'))
    await expect(api('/x')).rejects.toMatchObject({ status: 0, code: 'network_error' })
  })

  it('treats a 5xx with a non-JSON body as internal_error', async () => {
    mockFetch(new Response('<html>bad gateway</html>', { status: 502 }))
    await expect(api('/x')).rejects.toMatchObject({ status: 502, code: 'internal_error' })
  })
})
