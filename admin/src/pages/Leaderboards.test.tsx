import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { mount } from './content/testkit'
import { Leaderboards } from './Leaderboards'

function setup(entry = '/content/leaderboards') {
  return mount('viewer', <Leaderboards />, (url) => {
    if (url.includes('/leaderboards/weekly')) {
      return Response.json({ data: { limit: 50, resets_at: '2026-10-17T00:00:00+03:30', entries: [
        { rank: 1, user_id: 'u1', username: 'pro2', score: 4300, avatar_id: '' },
        { rank: 2, user_id: 'u2', username: 'tttt', score: 251, avatar_id: 'lion' },
      ] } })
    }
    if (url.includes('/leaderboards/alltime')) return Response.json({ data: { limit: 50, entries: [{ rank: 1, user_id: 'u9', username: 'legend', score: 99000, avatar_id: '' }] } })
    if (url.includes('/leaderboards/rewards')) {
      return Response.json({ data: { prizes: [500, 300, 100], weeks: [{ payout_date: '2026-10-03', rewards: [
        { rank: 1, user_id: 'u1', username: 'pro2', coins: 500, awarded_at: '2026-10-02T20:30:00Z', banned: false },
        { rank: 2, user_id: 'u3', username: 'gone', coins: 300, awarded_at: '2026-10-02T20:30:00Z', banned: true },
      ] }] } })
    }
  }, { path: '/content/leaderboards', entry })
}

afterEach(() => vi.unstubAllGlobals())

describe('Leaderboards', () => {
  it('shows the weekly board with Persian digits and the next reset, read-only', async () => {
    setup()
    expect(await screen.findByText('pro2')).toBeInTheDocument()
    expect(screen.getByText('۴٬۳۰۰')).toBeInTheDocument()
    expect(screen.getByText(/پایان هفته: ۱۴۰۵\/۰۷\/۲۵ ۰۰:۰۰/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /حذف|ویرایش|ذخیره/ })).not.toBeInTheDocument()
  })

  it('switches to the all-time board and the reward history (banned winners are labelled)', async () => {
    setup()
    await screen.findByText('pro2')
    await userEvent.click(screen.getByRole('tab', { name: 'همیشه' }))
    expect(await screen.findByText('legend')).toBeInTheDocument()
    expect(screen.getByText('۹۹٬۰۰۰')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('tab', { name: 'جایزه‌های هفتگی' }))
    expect(await screen.findByText('پرداخت ۱۴۰۵/۰۷/۱۱')).toBeInTheDocument()
    expect(screen.getByText('مسدود')).toBeInTheDocument()
    expect(screen.getByText(/۵۰۰، ۳۰۰، ۱۰۰ سکه/)).toBeInTheDocument()
  })
})
