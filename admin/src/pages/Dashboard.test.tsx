import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { DashboardDay, DashboardSummary } from '@/lib/dashboard'
import { Dashboard } from './Dashboard'

// jsdom has no canvas; the chart options are covered by chartOptions.test.ts.
vi.mock('@/components/charts/EChart', () => ({
  EChart: ({ label }: { label: string }) => <div role="img" aria-label={label} />,
}))

const SUMMARY: DashboardSummary = {
  generated_at: '2026-10-10T12:00:00Z',
  users: { total: 1234, new_today: 3, new_7d: 20, premium_active: 5 },
  coins_in_circulation: 98765,
  matches_today: { solo: 4, versus: 2, ai_online: 1, daily: 3, total: 10 },
  daily_participants_today: 6,
  unclaimed_rewards: { count: 8, coins: 240 },
  live: { rooms: 3, waiting_rooms: 1, active_rooms: 2, connected_players: 4, queue_length: 2 },
  fcm_configured: false,
}

const DAYS: DashboardDay[] = Array.from({ length: 30 }, (_, i) => ({
  date: `2026-09-${String(i + 1).padStart(2, '0')}`,
  signups: 1,
  matches_solo: 2,
  matches_versus: 1,
  matches_ai_online: 0,
  matches_daily: 1,
  daily_attempts: 1,
  coins_claimed: 10,
}))

function renderPage() {
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <Dashboard />
    </QueryClientProvider>,
  )
}

function stub(handlers: Record<string, () => Response>) {
  vi.stubGlobal('fetch', vi.fn(async (url: string) => {
    const key = Object.keys(handlers).find((k) => url.includes(k))
    if (!key) throw new Error(`unexpected ${url}`)
    return handlers[key]()
  }))
}

afterEach(() => vi.unstubAllGlobals())

describe('Dashboard', () => {
  it('shows Persian-formatted numbers from the API', async () => {
    stub({
      '/dashboard/summary': () => Response.json({ data: SUMMARY }),
      '/dashboard/timeseries': () => Response.json({ data: { days: DAYS } }),
    })
    renderPage()
    expect(await screen.findByText('۱٬۲۳۴')).toBeInTheDocument() // total users
    expect(screen.getByText('۹۸٬۷۶۵')).toBeInTheDocument() // coins in circulation
    expect(screen.getByText('پیکربندی نشده')).toBeInTheDocument() // FCM flag
    expect(screen.getByText('۱۰')).toBeInTheDocument() // matches today
    expect(await screen.findByRole('img', { name: /نمودار فعالیت روزانه/ })).toBeInTheDocument()
    expect(document.body.textContent).not.toMatch(/[0-9]/) // no ASCII digits anywhere
  })

  it('shows a retryable error when the summary fails, but still draws the charts', async () => {
    let calls = 0
    stub({
      '/dashboard/summary': () => {
        calls++
        return calls === 1
          ? Response.json({ error: { code: 'internal_error' } }, { status: 500 })
          : Response.json({ data: SUMMARY })
      },
      '/dashboard/timeseries': () => Response.json({ data: { days: DAYS } }),
    })
    renderPage()
    const alerts = await screen.findAllByRole('alert')
    expect(alerts.length).toBeGreaterThan(0)
    expect(alerts[0]).toHaveTextContent('خطای داخلی سرور')
    expect(await screen.findByRole('img', { name: /نمودار فعالیت روزانه/ })).toBeInTheDocument()

    await userEvent.setup().click(screen.getAllByRole('button', { name: 'تلاش دوباره' })[0])
    expect(await screen.findByText('۱٬۲۳۴')).toBeInTheDocument()
  })

  it('shows skeletons while loading', () => {
    vi.stubGlobal('fetch', vi.fn(() => new Promise(() => {})))
    renderPage()
    expect(screen.queryByText('۱٬۲۳۴')).not.toBeInTheDocument()
    expect(document.querySelectorAll('[aria-hidden].animate-pulse').length).toBeGreaterThan(5)
  })
})
