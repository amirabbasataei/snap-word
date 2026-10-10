import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AuthProvider } from '@/auth/AuthContext'
import { errorMessageFor } from '@/lib/errors'
import { Login } from './Login'

const ADMIN = { id: '1', username: 'tester', role: 'owner', last_login_at: null, via: 'session' }

function stubFetch(handlers: Record<string, () => Response>) {
  vi.stubGlobal('fetch', vi.fn(async (url: string) => {
    const h = handlers[url]
    if (!h) throw new Error(`unexpected ${url}`)
    return h()
  }))
}

function setup() {
  render(
    <QueryClientProvider client={new QueryClient()}>
      <MemoryRouter initialEntries={['/login']}>
        <AuthProvider>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/" element={<p>داشبورد</p>} />
          </Routes>
        </AuthProvider>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

const meUnauthorized = () => Response.json({ error: { code: 'admin_unauthorized' } }, { status: 401 })

afterEach(() => vi.unstubAllGlobals())

describe('Login', () => {
  it('signs in and navigates to the dashboard', async () => {
    stubFetch({
      '/api/v1/admin/auth/me': meUnauthorized,
      '/api/v1/admin/auth/login': () => Response.json({ data: { admin: ADMIN } }),
    })
    setup()
    const user = userEvent.setup()
    await user.type(await screen.findByLabelText('نام کاربری'), 'tester')
    await user.type(screen.getByLabelText('گذرواژه'), 'test-pass-12345')
    await user.click(screen.getByRole('button', { name: 'ورود' }))
    expect(await screen.findByText('داشبورد')).toBeInTheDocument()
  })

  it('shows the Persian message for wrong credentials', async () => {
    stubFetch({
      '/api/v1/admin/auth/me': meUnauthorized,
      '/api/v1/admin/auth/login': () => Response.json({ error: { code: 'invalid_credentials' } }, { status: 401 }),
    })
    setup()
    const user = userEvent.setup()
    await user.type(await screen.findByLabelText('نام کاربری'), 'tester')
    await user.type(screen.getByLabelText('گذرواژه'), 'wrong-password')
    await user.click(screen.getByRole('button', { name: 'ورود' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(errorMessageFor('invalid_credentials'))
  })

  it('locks the form with a Persian countdown on rate_limited', async () => {
    stubFetch({
      '/api/v1/admin/auth/me': meUnauthorized,
      '/api/v1/admin/auth/login': () =>
        Response.json({ error: { code: 'rate_limited' } }, { status: 429, headers: { 'Retry-After': '900' } }),
    })
    setup()
    const user = userEvent.setup()
    await user.type(await screen.findByLabelText('نام کاربری'), 'tester')
    await user.type(screen.getByLabelText('گذرواژه'), 'x')
    await user.click(screen.getByRole('button', { name: 'ورود' }))
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(errorMessageFor('rate_limited'))
    expect(alert).toHaveTextContent('۱۵:۰۰')
    await waitFor(() => expect(screen.getByRole('button', { name: 'ورود' })).toBeDisabled())
  })
})
