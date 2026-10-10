import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { UserItem } from '@/lib/users'
import { paramsFromUrl, Users } from './Users'

const USER: UserItem = {
  id: '11111111-1111-1111-1111-111111111111',
  username: 'ali_player',
  phone: '0912*****67',
  phone_masked: true,
  coins: 12500,
  xp: 3500,
  level: 3,
  total_matches: 42,
  premium: true,
  premium_until: '2026-12-01T00:00:00Z',
  avatar_id: '',
  created_at: '2026-09-20T08:00:00Z',
  banned: false,
  banned_at: null,
}
const BANNED: UserItem = { ...USER, id: '22222222-2222-2222-2222-222222222222', username: 'cheater', phone: '0935*****11', coins: 700, premium: false, banned: true, banned_at: '2026-10-01T00:00:00Z' }

function Where() {
  const l = useLocation()
  return <output data-testid="where">{l.pathname + l.search}</output>
}

function setup(url: string) {
  const fetchMock = vi.fn(async (u: string) => {
    if (u.includes('/users?')) return Response.json({ data: { items: [USER, BANNED], total: 57, page: 1, page_size: 25 } })
    throw new Error(`unexpected ${u}`)
  })
  vi.stubGlobal('fetch', fetchMock)
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <MemoryRouter initialEntries={[url]}>
        <Users />
        <Where />
      </MemoryRouter>
    </QueryClientProvider>,
  )
  return fetchMock
}

afterEach(() => vi.unstubAllGlobals())

describe('paramsFromUrl', () => {
  it('defaults and rejects unknown values', () => {
    expect(paramsFromUrl(new URLSearchParams(''))).toEqual({ q: '', filter: 'all', sort: 'created', order: 'desc', page: 1 })
    expect(paramsFromUrl(new URLSearchParams('filter=hax&sort=otp_code&page=-2&order=asc&q=ali'))).toEqual({
      q: 'ali', filter: 'all', sort: 'created', order: 'asc', page: 1,
    })
    expect(paramsFromUrl(new URLSearchParams('filter=banned&sort=coins&page=3')).page).toBe(3)
  })
})

describe('Users page', () => {
  it('passes the URL query to the API and renders rows with Persian formatting', async () => {
    const fetchMock = setup('/users?q=ali&filter=premium&sort=coins&order=asc&page=2')
    expect(await screen.findByText('ali_player')).toBeInTheDocument()

    const url = String(fetchMock.mock.calls[0][0])
    expect(url).toContain('q=ali')
    expect(url).toContain('filter=premium')
    expect(url).toContain('sort=coins')
    expect(url).toContain('order=asc')
    expect(url).toContain('page=2')
    expect(url).toContain('page_size=25')

    expect(screen.getByText('۱۲٬۵۰۰')).toBeInTheDocument() // coins
    expect(screen.getByText('۰۹۱۲*****۶۷')).toBeInTheDocument() // masked phone, Persian digits
    expect(screen.getByText('ویژه')).toBeInTheDocument()
    expect(screen.getByText('مسدود')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /ali_player/ })).toHaveAttribute('href', `/users/${USER.id}`)
    expect(screen.getByText(/۵۷ مورد/)).toBeInTheDocument()
    expect(document.querySelector('table')?.textContent).not.toMatch(/[0-9]/)
  })

  it('clicking a sortable header flips the order in the URL and resets to page 1', async () => {
    setup('/users?sort=coins&order=desc&page=2')
    await screen.findByText('ali_player')
    await userEvent.click(screen.getByRole('button', { name: 'سکه' }))
    await waitFor(() => expect(screen.getByTestId('where').textContent).toBe('/users?sort=coins&order=asc'))
  })

  it('debounces typing into ?q=', async () => {
    setup('/users')
    await screen.findByText('ali_player')
    await userEvent.type(screen.getByLabelText('جستجوی کاربر'), 'cheat')
    await waitFor(() => expect(screen.getByTestId('where').textContent).toBe('/users?q=cheat'))
  })

  it('shows a retryable error', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ error: { code: 'internal_error' } }, { status: 500 })))
    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={['/users']}>
          <Users />
        </MemoryRouter>
      </QueryClientProvider>,
    )
    expect(await screen.findByRole('alert')).toHaveTextContent('خطای داخلی سرور')
    expect(screen.getByRole('button', { name: 'تلاش دوباره' })).toBeInTheDocument()
  })
})
