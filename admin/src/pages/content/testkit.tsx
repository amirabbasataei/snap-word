import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render } from '@testing-library/react'
import type { ReactNode } from 'react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { vi } from 'vitest'
import { AuthProvider } from '@/auth/AuthContext'
import { ToastProvider } from '@/components/ui/Toast'

export interface Call {
  url: string
  init?: RequestInit
  body?: unknown
}

/** Stubs fetch: /auth/me answers with `role`; other requests go to `handler` (return undefined → 200 `{data:{}}`). */
export function mount(
  role: 'viewer' | 'operator' | 'owner',
  ui: ReactNode,
  handler: (url: string, init?: RequestInit) => Response | undefined,
  { path = '/', entry = '/' }: { path?: string; entry?: string } = {},
) {
  const calls: Call[] = []
  vi.stubGlobal('fetch', vi.fn(async (url: string, init?: RequestInit) => {
    let body: unknown
    if (typeof init?.body === 'string') body = JSON.parse(init.body)
    else if (init?.body instanceof FormData) body = Object.fromEntries(init.body.entries())
    calls.push({ url, init, body })
    if (url.endsWith('/auth/me')) {
      return Response.json({ data: { admin: { id: 'a', username: 'tester', role, last_login_at: null, via: 'session' } } })
    }
    return handler(url, init) ?? Response.json({ data: {} })
  }))
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <MemoryRouter initialEntries={[entry]}>
        <ToastProvider>
          <AuthProvider>
            <Routes>
              <Route path={path} element={ui} />
            </Routes>
          </AuthProvider>
        </ToastProvider>
      </MemoryRouter>
    </QueryClientProvider>,
  )
  return calls
}
