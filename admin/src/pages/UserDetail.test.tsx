import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AuthProvider } from '@/auth/AuthContext'
import { ToastProvider } from '@/components/ui/Toast'
import type { UserDetail as Detail } from '@/lib/users'
import { UserDetail } from './UserDetail'
import { parseWhole } from './users/UserActions'

const ID = '11111111-1111-1111-1111-111111111111'
const USER: Detail = {
  id: ID, username: 'ali_player', phone: '0912*****67', phone_masked: true,
  coins: 12500, xp: 3500, level: 3, total_matches: 42, premium: true, premium_until: '2026-12-01T00:00:00Z',
  avatar_id: 'fox', created_at: '2026-09-20T08:00:00Z', banned: false, banned_at: null,
  referral_code: 'ABC234', ban_reason: '', joined_at: '2026-09-20T08:00:00Z', xp_in_level: 500, xp_for_next: 3000,
  stats: { total_matches: 42, wins: 20, longest_word: 'کتابخانه', best_match_streak: 6, daily_streak: 2, longest_daily_streak: 9, last_played_date: '2026-10-09T00:00:00Z', total_score: 8000 },
  friends_count: 4, device_tokens: 1,
  referrer: { id: '33333333-3333-3333-3333-333333333333', username: 'inviter' },
  referred_count: 1, referred: [{ id: '44444444-4444-4444-4444-444444444444', username: 'friend1', created_at: '2026-10-01T00:00:00Z' }],
  rewards: [
    { id: 'r1', kind: 'admin_gift', detail: '', coins: 50, claimed: false, claimed_at: null, created_at: '2026-10-02T00:00:00Z' },
    { id: 'r2', kind: 'daily_login', detail: '', coins: 10, claimed: true, claimed_at: '2026-10-03T00:00:00Z', created_at: '2026-10-03T00:00:00Z' },
  ],
  matches: [{ id: 'm1', mode: 'classic', status: 'finished', kind: 'versus', score: 120, won: true, at: '2026-10-04T10:00:00Z', ended_at: null, player_count: 2 }],
  daily_attempts: [{ date: '2026-10-05', attempt: 1, score: 300, chain_length: 12, completed_at: '2026-10-05T10:00:00Z' }],
}

function setup(role: 'viewer' | 'operator' | 'owner', detail: Detail = USER, onPost?: (url: string, init: RequestInit) => Response) {
  const calls: { url: string; init?: RequestInit }[] = []
  vi.stubGlobal('fetch', vi.fn(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    if (url.endsWith('/auth/me')) return Response.json({ data: { admin: { id: 'a', username: 'tester', role, last_login_at: null, via: 'session' } } })
    if (init?.method && init.method !== 'GET') return onPost?.(url, init) ?? Response.json({ data: {} })
    if (url.includes(`/users/${ID}`)) return Response.json({ data: detail })
    throw new Error(`unexpected ${url}`)
  }))
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <MemoryRouter initialEntries={[`/users/${ID}`]}>
        <ToastProvider>
          <AuthProvider>
            <Routes>
              <Route path="/users/:id" element={<UserDetail />} />
            </Routes>
          </AuthProvider>
        </ToastProvider>
      </MemoryRouter>
    </QueryClientProvider>,
  )
  return calls
}

afterEach(() => vi.unstubAllGlobals())

describe('parseWhole', () => {
  it('accepts Persian and Latin whole numbers only', () => {
    expect(parseWhole('۱٬۵۰۰')).toBe(1500)
    expect(parseWhole(' 250 ')).toBe(250)
    for (const bad of ['', '12.5', '-3', 'abc', '1e3', '9999999999']) expect(parseWhole(bad)).toBeNaN()
  })
})

describe('UserDetail', () => {
  it('shows the profile in Persian and the masked phone', async () => {
    setup('owner')
    expect(await screen.findByRole('heading', { name: 'ali_player' })).toBeInTheDocument()
    expect(screen.getByText('۰۹۱۲*****۶۷')).toBeInTheDocument()
    expect(screen.getByText('۱۲٬۵۰۰')).toBeInTheDocument()
    expect(screen.getByText('سطح ۳')).toBeInTheDocument()
    expect(screen.getByText('کتابخانه')).toBeInTheDocument()
  })

  it('a viewer sees no action buttons', async () => {
    setup('viewer')
    await screen.findByRole('heading', { name: 'ali_player' })
    expect(await screen.findByText('نقش شما فقط اجازهٔ مشاهده می‌دهد.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /مسدودسازی/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('group', { name: 'اقدامات' })).not.toBeInTheDocument()
  })

  it('an operator bans only with the typed username and a reason, then posts both', async () => {
    const calls = setup('operator')
    await screen.findByRole('heading', { name: 'ali_player' })
    await userEvent.click(await screen.findByRole('button', { name: 'مسدودسازی' }))

    const dialog = await screen.findByRole('dialog')
    const confirm = within(dialog).getByRole('button', { name: 'مسدود کن' })
    expect(confirm).toBeDisabled()

    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'تقلب در بازی')
    expect(confirm).toBeDisabled() // still needs the typed username
    await userEvent.type(within(dialog).getByLabelText(/را تایپ کنید/), 'ali_player')
    expect(confirm).toBeEnabled()
    await userEvent.click(confirm)

    await waitFor(() => expect(calls.some((c) => c.url.endsWith(`/users/${ID}/ban`))).toBe(true))
    const post = calls.find((c) => c.url.endsWith('/ban'))!
    expect(post.init?.method).toBe('POST')
    expect(JSON.parse(String(post.init?.body))).toEqual({ reason: 'تقلب در بازی' })
    expect((post.init?.headers as Record<string, string>)['X-Requested-With']).toBe('zanjir-admin')
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
  })

  it('shows the server error inside the dialog and keeps it open', async () => {
    setup('operator', USER, () => Response.json({ error: { code: 'already_banned' } }, { status: 409 }))
    await screen.findByRole('heading', { name: 'ali_player' })
    await userEvent.click(await screen.findByRole('button', { name: 'مسدودسازی' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'تقلب در بازی')
    await userEvent.type(within(dialog).getByLabelText(/را تایپ کنید/), 'ali_player')
    await userEvent.click(within(dialog).getByRole('button', { name: 'مسدود کن' }))
    expect(await within(dialog).findByRole('alert')).toHaveTextContent('این کاربر از قبل مسدود است.')
  })

  it('a banned user offers unban and shows the reason', async () => {
    setup('operator', { ...USER, banned: true, banned_at: '2026-10-08T00:00:00Z', ban_reason: 'اسپم' })
    expect(await screen.findByText(/این حساب مسدود است/)).toBeInTheDocument()
    expect(screen.getByText('دلیل: اسپم')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'رفع مسدودی' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'مسدودسازی' })).not.toBeInTheDocument()
  })

  it('coins: a deduction above the balance is rejected before submitting', async () => {
    setup('operator')
    await screen.findByRole('heading', { name: 'ali_player' })
    await userEvent.click(await screen.findByRole('button', { name: 'سکه' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'اصلاح موجودی')
    await userEvent.type(within(dialog).getByLabelText('تعداد سکه'), '۱۰۰')
    expect(within(dialog).getByText('موجودی پس از تغییر: ۱۲٬۶۰۰')).toBeInTheDocument()
    expect(within(dialog).getByRole('button', { name: 'ثبت' })).toBeEnabled()
  })

  it('shows 404 for an unknown user', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) =>
      url.endsWith('/auth/me')
        ? Response.json({ data: { admin: { id: 'a', username: 't', role: 'owner', last_login_at: null, via: 'session' } } })
        : Response.json({ error: { code: 'user_not_found' } }, { status: 404 }),
    ))
    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <MemoryRouter initialEntries={[`/users/${ID}`]}>
          <ToastProvider><AuthProvider><Routes><Route path="/users/:id" element={<UserDetail />} /></Routes></AuthProvider></ToastProvider>
        </MemoryRouter>
      </QueryClientProvider>,
    )
    expect(await screen.findByText('صفحه‌ای که دنبالش هستید پیدا نشد.')).toBeInTheDocument()
  })
})
