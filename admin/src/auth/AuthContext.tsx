import { useQueryClient } from '@tanstack/react-query'
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { api, setUnauthorizedHandler } from '@/lib/api'
import { ApiError } from '@/lib/errors'

export type AdminRole = 'owner' | 'operator' | 'viewer'

export interface AdminUser {
  id: string
  username: string
  role: AdminRole
  last_login_at: string | null
  via: 'session' | 'key'
}

type Status = 'loading' | 'authed' | 'anon'

interface AuthValue {
  status: Status
  admin: AdminUser | null
  login: (username: string, password: string) => Promise<void>
  logout: () => Promise<void>
}

const Ctx = createContext<AuthValue | null>(null)

export function useAuth(): AuthValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useAuth must be used inside <AuthProvider>')
  return v
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const qc = useQueryClient()
  const [status, setStatus] = useState<Status>('loading')
  const [admin, setAdmin] = useState<AdminUser | null>(null)

  const drop = useCallback(() => {
    setAdmin(null)
    setStatus('anon')
    qc.clear()
  }, [qc])

  // Restore the session from the httpOnly cookie.
  useEffect(() => {
    const ctrl = new AbortController()
    api<{ admin: AdminUser }>('/auth/me', { signal: ctrl.signal, skipUnauthorized: true })
      .then((d) => {
        setAdmin(d.admin)
        setStatus('authed')
      })
      .catch((e) => {
        if (e instanceof DOMException && e.name === 'AbortError') return
        // Any failure (401, 404 when no admin exists, network) → show the login page.
        setStatus('anon')
      })
    return () => ctrl.abort()
  }, [])

  // A 401 from any later request (expired/revoked session) returns to login.
  useEffect(() => {
    setUnauthorizedHandler(drop)
    return () => setUnauthorizedHandler(null)
  }, [drop])

  const login = useCallback(async (username: string, password: string) => {
    const d = await api<{ admin: AdminUser }>('/auth/login', {
      method: 'POST',
      body: { username, password },
      skipUnauthorized: true,
    })
    setAdmin(d.admin)
    setStatus('authed')
  }, [])

  const logout = useCallback(async () => {
    try {
      await api('/auth/logout', { method: 'POST', skipUnauthorized: true })
    } catch (e) {
      // The session may already be gone server-side; the local state is cleared either way.
      if (!(e instanceof ApiError)) throw e
    }
    drop()
  }, [drop])

  const value = useMemo(() => ({ status, admin, login, logout }), [status, admin, login, logout])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}
