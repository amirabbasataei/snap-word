import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { DailyList } from '@/lib/content'
import { mount } from './content/testkit'
import { Daily } from './Daily'

const LIST: DailyList = {
  from: '2026-09-11',
  to: '2026-10-12',
  today: '2026-10-10',
  eligible_letters: ['آ', 'ا', 'ب', 'ت'],
  rows: [
    { date: '2026-10-12', day_number: 647, start_letter: 'ت', generated: false, customized: false, status: 'future', editable: true, players: 0, attempts: 0, best_score: 0 },
    { date: '2026-10-11', day_number: 646, start_letter: 'ب', generated: true, customized: true, status: 'future', editable: true, players: 0, attempts: 0, best_score: 0 },
    { date: '2026-10-10', day_number: 645, start_letter: 'ا', generated: true, customized: false, status: 'today', editable: false, players: 4, attempts: 5, best_score: 1250 },
    { date: '2026-10-09', day_number: 644, start_letter: 'آ', generated: true, customized: false, status: 'past', editable: false, players: 9, attempts: 11, best_score: 900 },
  ],
}

function setup(role: 'viewer' | 'operator' | 'owner') {
  return mount(role, <Daily />, (url, init) => {
    if (url.endsWith('/daily') && (init?.method ?? 'GET') === 'GET') return Response.json({ data: LIST })
  })
}

afterEach(() => vi.unstubAllGlobals())

describe('Daily', () => {
  it('lists days with Persian numbers, status badges and a Jalali date', async () => {
    setup('viewer')
    expect(await screen.findByText('#۶۴۵')).toBeInTheDocument()
    expect(screen.getAllByText('امروز').length).toBeGreaterThan(0)
    expect(screen.getAllByText('دستی').length).toBeGreaterThan(0)
    expect(screen.getAllByText('ساخته‌نشده').length).toBeGreaterThan(0)
    expect(screen.getByText('۱٬۲۵۰')).toBeInTheDocument()
    expect(screen.getByText('۱۴۰۵/۰۷/۱۸')).toBeInTheDocument() // 2026-10-10
  })

  it('only generated days link to a detail page', async () => {
    setup('viewer')
    await screen.findByText('#۶۴۵')
    expect(screen.getByRole('link', { name: /#۶۴۵/ })).toHaveAttribute('href', '/content/daily/2026-10-10')
    expect(screen.queryByRole('link', { name: /#۶۴۷/ })).not.toBeInTheDocument()
  })

  it('offers "change letter" only to operators and only on future days', async () => {
    setup('operator')
    await screen.findByText('#۶۴۵')
    expect(screen.getAllByRole('button', { name: /تغییر حرف شروع چالش/ })).toHaveLength(2)
    expect(screen.queryByRole('button', { name: 'تغییر حرف شروع چالش ۶۴۵' })).not.toBeInTheDocument()
  })

  it('a viewer has no change buttons', async () => {
    setup('viewer')
    await screen.findByText('#۶۴۵')
    expect(screen.queryByRole('button', { name: /تغییر حرف/ })).not.toBeInTheDocument()
  })

  it('changing the letter requires a different letter and a reason, then PATCHes', async () => {
    const calls = setup('owner')
    await screen.findByText('#۶۴۵')
    await userEvent.click(screen.getByRole('button', { name: 'تغییر حرف شروع چالش ۶۴۶' }))
    const dialog = await screen.findByRole('dialog')
    const confirm = within(dialog).getByRole('button', { name: 'ذخیرهٔ حرف' })
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'هماهنگی با رویداد')
    expect(confirm).toBeDisabled() // same letter as now

    await userEvent.click(within(dialog).getByRole('radio', { name: 'ت' }))
    expect(within(dialog).getByRole('radio', { name: 'ت' })).toHaveAttribute('aria-checked', 'true')
    await userEvent.click(confirm)
    await waitFor(() => expect(calls.some((c) => c.init?.method === 'PATCH')).toBe(true))
    const patch = calls.find((c) => c.init?.method === 'PATCH')!
    expect(patch.url).toMatch(/\/daily\/2026-10-11$/)
    expect(patch.body).toEqual({ start_letter: 'ت', reason: 'هماهنگی با رویداد' })
  })

  it('shows a server rejection (day no longer editable) inside the dialog in Persian', async () => {
    mount('owner', <Daily />, (url, init) => {
      if (url.endsWith('/daily') && (init?.method ?? 'GET') === 'GET') return Response.json({ data: LIST })
      if (init?.method === 'PATCH') return Response.json({ error: { code: 'date_not_editable', message: 'only future days' } }, { status: 409 })
    })
    await screen.findByText('#۶۴۵')
    await userEvent.click(screen.getByRole('button', { name: 'تغییر حرف شروع چالش ۶۴۶' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'تلاش دیرهنگام')
    await userEvent.click(within(dialog).getByRole('radio', { name: 'ت' }))
    await userEvent.click(within(dialog).getByRole('button', { name: 'ذخیرهٔ حرف' }))
    expect(await within(dialog).findByRole('alert')).toHaveTextContent('فقط حرف شروع روزهای آینده قابل تغییر است.')
  })
})
