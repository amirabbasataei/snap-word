import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { iranDay, type MatchDetail as Detail, type MatchItem } from '@/lib/matches'
import { MatchDetail } from './MatchDetail'
import { Matches, paramsFromUrl } from './Matches'

const A = '11111111-1111-1111-1111-111111111111'
const B = '22222222-2222-2222-2222-222222222222'
const VERSUS: MatchItem = {
  id: '10000000-0000-0000-0000-000000000002', mode: 'classic', status: 'finished', kind: 'versus',
  at: '2026-11-02T10:00:00Z', started_at: '2026-11-02T10:00:00Z', ended_at: '2026-11-02T10:05:00Z',
  duration_sec: 300, chain_length: 7, winner_id: B,
  players: [
    { user_id: A, username: 'ali', score: 40, is_ai: false, continue_used: true },
    { user_id: B, username: 'sara', score: 70, is_ai: false, continue_used: false },
  ],
}
const AI: MatchItem = {
  ...VERSUS, id: '10000000-0000-0000-0000-000000000003', kind: 'ai', winner_id: '', duration_sec: null, chain_length: 0,
  players: [
    { user_id: A, username: 'ali', score: 10, is_ai: false, continue_used: false },
    { user_id: '00000000-0000-0000-0000-000000000001', username: '', score: 0, is_ai: true, continue_used: false },
  ],
}

function wrap(ui: React.ReactNode, url: string) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <MemoryRouter initialEntries={[url]}>{ui}</MemoryRouter>
    </QueryClientProvider>,
  )
}

afterEach(() => vi.unstubAllGlobals())

describe('paramsFromUrl', () => {
  it('defaults and rejects unknown values', () => {
    expect(paramsFromUrl(new URLSearchParams(''))).toEqual({ q: '', kind: 'all', status: 'all', range: 'all', page: 1 })
    expect(paramsFromUrl(new URLSearchParams('kind=hax&status=x&range=y&page=-1&q=ali'))).toEqual({
      q: 'ali', kind: 'all', status: 'all', range: 'all', page: 1,
    })
    expect(paramsFromUrl(new URLSearchParams('kind=versus&status=finished&range=7d&page=3'))).toMatchObject({ kind: 'versus', range: '7d', page: 3 })
  })
})

describe('iranDay', () => {
  it('uses the Iran calendar day (UTC+3:30)', () => {
    // 21:00 UTC on Nov 1 is already 00:30 on Nov 2 in Tehran.
    expect(iranDay(0, new Date('2026-11-01T21:00:00Z'))).toBe('2026-11-02')
    expect(iranDay(0, new Date('2026-11-01T20:00:00Z'))).toBe('2026-11-01')
    expect(iranDay(6, new Date('2026-11-01T20:00:00Z'))).toBe('2026-10-26')
  })
})

describe('Matches page', () => {
  it('lists matches with players, winner and links, and sends filters to the API', async () => {
    const fetchMock = vi.fn(async () => Response.json({ data: { items: [VERSUS, AI], total: 2, page: 1, page_size: 25 } }))
    vi.stubGlobal('fetch', fetchMock)
    wrap(<Matches />, '/matches?kind=versus&status=finished')

    expect(await screen.findByRole('link', { name: 'sara' })).toHaveAttribute('href', `/users/${B}`)
    expect(screen.getAllByText('برنده')).toHaveLength(1)
    expect(screen.getByText('ادامه')).toBeInTheDocument()
    expect(screen.getByText('هوش مصنوعی')).toBeInTheDocument()
    expect(screen.getAllByRole('link', { name: /جزئیات مسابقه/ })[0]).toHaveAttribute('href', `/matches/${VERSUS.id}`)

    const url = String((fetchMock.mock.calls[0] as unknown[])[0])
    expect(url).toContain('kind=versus')
    expect(url).toContain('status=finished')
    expect(url).not.toContain('from=')
  })

  it('shows a retryable error', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(Response.json({ error: { code: 'internal_error', message: 'x' } }, { status: 500 }))
      .mockResolvedValue(Response.json({ data: { items: [VERSUS], total: 1, page: 1, page_size: 25 } }))
    vi.stubGlobal('fetch', fetchMock)
    wrap(<Matches />, '/matches')
    await userEvent.click(await screen.findByRole('button', { name: /تلاش دوباره/ }))
    expect(await screen.findByRole('link', { name: 'sara' })).toBeInTheDocument()
  })

  it('says so when a filter matches nothing', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ data: { items: [], total: 0, page: 1, page_size: 25 } })))
    wrap(<Matches />, '/matches?q=zzz')
    expect(await screen.findByText('مسابقه‌ای با این مشخصات پیدا نشد.')).toBeInTheDocument()
  })
})

describe('MatchDetail page', () => {
  const detail: Detail = { ...VERSUS, word_chain: ['کتاب', 'بهار', 'رود'] }
  function open(id: string) {
    return wrap(
      <Routes><Route path="/matches/:id" element={<MatchDetail />} /></Routes>,
      `/matches/${id}`,
    )
  }

  it('renders the chain as ordered chips', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ data: detail })))
    open(detail.id)
    const chain = await screen.findByRole('list', { name: 'زنجیر کلمه‌ها' })
    expect(chain.querySelectorAll('li')).toHaveLength(3)
    expect(chain).toHaveTextContent('کتاب')
    expect(screen.getByRole('link', { name: 'ali' })).toHaveAttribute('href', `/users/${A}`)
  })

  it('handles a match without a stored chain and a draw', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ data: { ...AI, word_chain: [] } })))
    open(AI.id)
    expect(await screen.findByText('زنجیری برای این مسابقه ذخیره نشده است.')).toBeInTheDocument()
    expect(screen.getByText('برنده‌ای ثبت نشده (مساوی).')).toBeInTheDocument()
  })

  it('shows not-found for an unknown id', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ error: { code: 'match_not_found', message: 'x' } }, { status: 404 })))
    open('99999999-0000-0000-0000-000000000009')
    await waitFor(() => expect(screen.queryByRole('list', { name: 'زنجیر کلمه‌ها' })).not.toBeInTheDocument())
    expect(await screen.findByText('۴۰۴')).toBeInTheDocument()
  })
})
