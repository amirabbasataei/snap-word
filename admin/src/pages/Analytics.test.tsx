import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { AnalyticsOverview, RetentionResult } from '@/lib/analytics'
import { Analytics } from './Analytics'
import { Timeline } from './analytics/Timeline'

// jsdom has no canvas; chart options are plain data.
vi.mock('@/components/charts/EChart', () => ({
  EChart: ({ label }: { label: string }) => <div role="img" aria-label={label} />,
}))

const OVERVIEW: AnalyticsOverview = {
  generated_at: '2026-10-27T10:00:00Z',
  dau: 120, wau: 400, mau: 900, stickiness: 0.133,
  new_installs_today: 12, new_installs_7d: 80, avg_session_ms: 83_000,
  total_installs: 2500, linked_installs: 700,
  days: Array.from({ length: 7 }, (_, i) => ({
    day: `2026-10-${String(21 + i).padStart(2, '0')}`, active: 100 + i, active_users: 30, new_installs: 10, sessions: 150,
  })),
}

const RETENTION: RetentionResult = {
  by: 'install',
  cohorts: [{ cohort: '2026-10-20', size: 50, retained: [50, 20, 10, ...Array(28).fill(null)] }],
}

function renderPage(ui: React.ReactElement) {
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <MemoryRouter>{ui}</MemoryRouter>
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

describe('Analytics', () => {
  it('shows the headline numbers in Persian digits', async () => {
    stub({ '/analytics/overview': () => Response.json({ data: OVERVIEW }) })
    renderPage(<Analytics />)
    expect(await screen.findByText('۴۰۰')).toBeInTheDocument() // WAU
    expect(screen.getByText('۹۰۰')).toBeInTheDocument() // MAU
    expect(screen.getByText('۱ دقیقه و ۲۳ ثانیه')).toBeInTheDocument()
    expect(screen.getByText('۱۳٪')).toBeInTheDocument() // stickiness
    expect(await screen.findByRole('img', { name: /کاربران فعال روزانه/ })).toBeInTheDocument()
    expect(document.body.textContent).not.toMatch(/[0-9]/)
  })

  it('draws the retention heat map with per-day percentages and an average row', async () => {
    stub({
      '/analytics/overview': () => Response.json({ data: OVERVIEW }),
      '/analytics/retention': () => Response.json({ data: RETENTION }),
    })
    renderPage(<Analytics />)
    await userEvent.setup().click(await screen.findByRole('tab', { name: 'بازگشت کاربران' }))
    const table = await screen.findByRole('table', { name: 'جدول بازگشت کاربران' })
    const row = within(table).getByText('۵۰').closest('tr') as HTMLElement
    expect(within(row).getByText('۴۰')).toBeInTheDocument() // D1: 20 of 50
    expect(within(row).getByText('۲۰')).toBeInTheDocument() // D2: 10 of 50
    expect(within(table).getByText('میانگین وزنی')).toBeInTheDocument()
  })

  it('shows a retryable error when the overview fails', async () => {
    stub({ '/analytics/overview': () => Response.json({ error: { code: 'internal_error' } }, { status: 500 }) })
    renderPage(<Analytics />)
    expect(await screen.findByRole('alert')).toHaveTextContent('خطای داخلی سرور')
  })
})

describe('Timeline', () => {
  it('lists events newest first with labels, screens and props', async () => {
    stub({
      '/timeline': () =>
        Response.json({
          data: {
            installs: [{ install_id: 'aaaaaaaa-0000-4000-8000-000000000001', user_id: 'u', first_seen: '2026-10-20', last_seen: '2026-10-27', platform: 'android', app_version: '1.0.0' }],
            events: [
              { ts: '2026-10-27T10:05:00Z', name: 'game_end', screen: '/game', props: { score: 340, result: 'loss' }, install_id: 'aaaaaaaa-0000-4000-8000-000000000001' },
              { ts: '2026-10-27T10:00:00Z', name: 'app_open', install_id: 'aaaaaaaa-0000-4000-8000-000000000001' },
            ],
          },
        }),
    })
    renderPage(<Timeline kind="users" id="u" />)
    const items = await screen.findAllByRole('listitem')
    const texts = items.map((i) => i.textContent ?? '')
    const endIdx = texts.findIndex((t) => t.includes('پایان بازی'))
    const openIdx = texts.findIndex((t) => t.includes('باز کردن برنامه'))
    expect(endIdx).toBeGreaterThanOrEqual(0)
    expect(endIdx).toBeLessThan(openIdx)
    expect(texts[endIdx]).toContain('score: ۳۴۰')
    expect(screen.getByText('وصل به حساب')).toBeInTheDocument()
  })
})
