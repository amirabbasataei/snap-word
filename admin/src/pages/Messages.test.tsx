import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { PlayerMessage } from '@/lib/messages'
import { Messages, paramsFromUrl } from './Messages'

const A = '11111111-1111-1111-1111-111111111111'
const B = '22222222-2222-2222-2222-222222222222'
const M = '10000000-0000-0000-0000-000000000002'
const CUSTOM: PlayerMessage = {
  id: 'm1', at: '2026-11-02T10:00:00Z', kind: 'custom', taunt_id: '', text: 'سلام رفیق، آماده‌ای؟',
  match_id: M, sender_id: A, sender_name: 'ali', sender_banned: true, opponent_id: B, opponent_name: 'sara',
}
const PRESET: PlayerMessage = {
  ...CUSTOM, id: 'm2', kind: 'preset', taunt_id: 'hurry_up', text: 'زود باش!', match_id: '', opponent_id: '', opponent_name: '',
}

function wrap(url: string) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <MemoryRouter initialEntries={[url]}><Messages /></MemoryRouter>
    </QueryClientProvider>,
  )
}

afterEach(() => vi.unstubAllGlobals())

describe('paramsFromUrl', () => {
  it('defaults and rejects unknown values', () => {
    expect(paramsFromUrl(new URLSearchParams(''))).toEqual({ q: '', kind: 'all', range: 'all', page: 1 })
    expect(paramsFromUrl(new URLSearchParams('kind=x&range=y&page=0&q=ali'))).toEqual({ q: 'ali', kind: 'all', range: 'all', page: 1 })
    expect(paramsFromUrl(new URLSearchParams('kind=custom&range=7d&page=2'))).toMatchObject({ kind: 'custom', range: '7d', page: 2 })
  })
})

describe('Messages page', () => {
  it('lists messages with sender, opponent and match link, and sends filters to the API', async () => {
    const fetchMock = vi.fn(async () => Response.json({ data: { items: [CUSTOM, PRESET], total: 2, page: 1, page_size: 25 } }))
    vi.stubGlobal('fetch', fetchMock)
    wrap('/messages?kind=custom&q=ali')

    expect(await screen.findByText('سلام رفیق، آماده‌ای؟')).toBeInTheDocument()
    expect(screen.getAllByRole('link', { name: 'ali' })[0]).toHaveAttribute('href', `/users/${A}`)
    expect(screen.getByRole('link', { name: 'sara' })).toHaveAttribute('href', `/users/${B}`)
    expect(screen.getAllByText('مسدود')).toHaveLength(2)
    expect(screen.getByRole('link', { name: /مسابقهٔ پیام/ })).toHaveAttribute('href', `/matches/${M}`)

    const url = String((fetchMock.mock.calls[0] as unknown[])[0])
    expect(url).toContain('kind=custom')
    expect(url).toContain('q=ali')
    expect(url).not.toContain('from=')
  })

  it('shows a retryable error', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(Response.json({ error: { code: 'internal_error', message: 'x' } }, { status: 500 }))
      .mockResolvedValue(Response.json({ data: { items: [PRESET], total: 1, page: 1, page_size: 25 } }))
    vi.stubGlobal('fetch', fetchMock)
    wrap('/messages')
    await userEvent.click(await screen.findByRole('button', { name: /تلاش دوباره/ }))
    expect(await screen.findByText('زود باش!')).toBeInTheDocument()
  })

  it('says so when nothing matches, and when nothing was ever sent', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ data: { items: [], total: 0, page: 1, page_size: 25 } })))
    const first = wrap('/messages?q=zzz')
    expect(await screen.findByText('پیامی با این مشخصات پیدا نشد.')).toBeInTheDocument()
    first.unmount()
    wrap('/messages')
    expect(await screen.findByText('هنوز پیامی فرستاده نشده است.')).toBeInTheDocument()
  })
})
