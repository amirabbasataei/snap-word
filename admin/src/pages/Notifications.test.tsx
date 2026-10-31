import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { mount } from './content/testkit'
import { Notifications } from './Notifications'

const PREVIEW = {
  recipients: 120, fcm_configured: true,
  push: { deliverable: 70, granted: 60, unknown: 10, denied: 20, not_determined: 25, none: 5 },
}
const REACH = {
  fcm_configured: true, users: 120, deliverable: 70, granted: 60, unknown: 10, denied: 20, not_determined: 25, none: 5,
  devices: [{ platform: 'android', permission: 'granted', count: 55 }, { platform: 'ios', permission: 'denied', count: 20 }],
}
const CAMPAIGN = {
  id: 'c1', title: 'جشن هفته', body: 'جایزه بگیر', route: '/daily', push: true, inapp: true,
  audience: { type: 'all' }, created_by: 'tester', created_at: '2026-10-30T10:00:00Z',
  recipients: 120, inapp_delivered: 120, inapp_read: 30, push_status: 'done',
  push_users: 70, push_devices: 80, push_sent: 78, push_failed: 2, push_removed: 1, push_finished_at: '2026-10-30T10:01:00Z',
}

function setup(role: 'viewer' | 'operator' | 'owner', opts: { fcm?: boolean } = {}) {
  const preview = { ...PREVIEW, fcm_configured: opts.fcm ?? true }
  return mount(role, <Notifications />, (url, init) => {
    if (url.endsWith('/notifications/preview')) return Response.json({ data: preview })
    if (url.endsWith('/notifications/reach')) return Response.json({ data: REACH })
    if (url.includes('/notifications?')) return Response.json({ data: { items: [CAMPAIGN], total: 1, page: 1, page_size: 20 } })
    if (url.endsWith('/notifications/c1')) return Response.json({ data: { ...CAMPAIGN, users: [] } })
    if (url.includes('/users?')) {
      return Response.json({ data: { items: [{ id: '11111111-1111-1111-1111-111111111111', username: 'ali', banned: false }], total: 1, page: 1, page_size: 25 } })
    }
    if (url.endsWith('/notifications') && init?.method === 'POST') return Response.json({ data: CAMPAIGN })
  })
}

// jsdom lacks the pointer-capture and scroll APIs Radix Select calls when opening.
beforeAll(() => {
  Element.prototype.hasPointerCapture ??= () => false
  Element.prototype.setPointerCapture ??= () => undefined
  Element.prototype.releasePointerCapture ??= () => undefined
  Element.prototype.scrollIntoView ??= () => undefined
})

afterEach(() => vi.unstubAllGlobals())

async function fill(title = 'سلام', body = 'متن آزمایشی') {
  await userEvent.type(await screen.findByLabelText('عنوان'), title)
  await userEvent.type(screen.getByLabelText('متن پیام'), body)
}

describe('Notifications — compose', () => {
  it('sizes the audience and spells out who can receive a push', async () => {
    setup('operator')
    expect(await screen.findByText(/۱۲۰/)).toBeInTheDocument()
    // 70 of 120 can be pushed; the rest only see the in-app message.
    expect(await screen.findByText(/اعلان فوری برای/)).toHaveTextContent('۷۰')
    expect(screen.getByText(/۲۰ نفر رد کرده‌اند، ۲۵ نفر هنوز پرسیده نشده و ۵ نفر دستگاهی/)).toBeInTheDocument()
  })

  it('sending to everyone needs a typed confirmation and posts the right body', async () => {
    const calls = setup('operator')
    await fill()
    await userEvent.click(screen.getByRole('button', { name: /ارسال…/ }))
    const dialog = await screen.findByRole('dialog')
    const confirm = within(dialog).getByRole('button', { name: 'ارسال' })
    expect(confirm).toBeDisabled()
    await userEvent.type(within(dialog).getByLabelText(/را تایپ کنید/), 'ارسال')
    await userEvent.click(confirm)

    await waitFor(() => expect(calls.some((c) => c.url.endsWith('/notifications') && c.init?.method === 'POST')).toBe(true))
    const post = calls.find((c) => c.url.endsWith('/notifications') && c.init?.method === 'POST')!
    expect(post.body).toEqual({
      title: 'سلام', body: 'متن آزمایشی', route: '', channels: ['push', 'inapp'], audience: { type: 'all' },
    })
  })

  it('a group send carries the segment filters', async () => {
    const calls = setup('operator')
    await fill()
    await userEvent.click(screen.getByRole('radio', { name: /یک گروه/ }))
    await userEvent.click(screen.getByRole('combobox', { name: 'فعالیت' }))
    await userEvent.click(await screen.findByRole('option', { name: /بازی نکرده/ }))
    const days = screen.getByLabelText('تعداد روز')
    await userEvent.clear(days)
    await userEvent.type(days, '14')
    await userEvent.click(screen.getByRole('button', { name: /ارسال…/ }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'ارسال' }))

    await waitFor(() => expect(calls.some((c) => c.url.endsWith('/notifications') && c.init?.method === 'POST')).toBe(true))
    const post = calls.find((c) => c.url.endsWith('/notifications') && c.init?.method === 'POST')!
    expect((post.body as { audience: unknown }).audience).toEqual({
      type: 'segment',
      segment: { premium: 'any', activity: 'inactive', days: 14, joined_within_days: 0, push: 'any' },
    })
  })

  it('specific users: pick from search results, then send in-app only', async () => {
    const calls = setup('operator')
    await fill()
    await userEvent.click(screen.getByRole('radio', { name: /کاربران مشخص/ }))
    expect(screen.getByRole('button', { name: /ارسال…/ })).toBeDisabled()
    await userEvent.type(screen.getByLabelText('جست‌وجوی کاربر'), 'al')
    await userEvent.click(await screen.findByRole('button', { name: /ali/ }))
    await userEvent.click(screen.getByLabelText(/اعلان فوری \(Push\)/))
    await userEvent.click(screen.getByRole('button', { name: /ارسال…/ }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'ارسال' })) // no typed confirmation for named users

    await waitFor(() => expect(calls.some((c) => c.url.endsWith('/notifications') && c.init?.method === 'POST')).toBe(true))
    const post = calls.find((c) => c.url.endsWith('/notifications') && c.init?.method === 'POST')!
    expect(post.body).toMatchObject({
      channels: ['inapp'],
      audience: { type: 'users', user_ids: ['11111111-1111-1111-1111-111111111111'] },
    })
  })

  it('warns and blocks push while the server has no FCM key', async () => {
    setup('operator', { fcm: false })
    await fill()
    expect(await screen.findByText(/روی سرور تنظیم نشده است/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /ارسال…/ })).toBeDisabled()
  })

  it('a viewer can read but not send', async () => {
    setup('viewer')
    expect(await screen.findByText('فقط اپراتور و مالک می‌توانند اعلان ارسال کنند.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /ارسال…/ })).not.toBeInTheDocument()
  })
})

describe('Notifications — history and reach', () => {
  it('lists past sends with delivery results', async () => {
    setup('viewer')
    await userEvent.click(await screen.findByRole('tab', { name: 'سابقهٔ ارسال' }))
    expect(await screen.findByText('جشن هفته')).toBeInTheDocument()
    expect(screen.getByText('۷۸ از ۸۰ دستگاه')).toBeInTheDocument()
    expect(screen.getByText('۳۰ از ۱۲۰')).toBeInTheDocument()
  })

  it('shows how many accounts allowed, denied or were never asked about push', async () => {
    setup('viewer')
    await userEvent.click(await screen.findByRole('tab', { name: 'وضعیت مجوز اعلان' }))
    expect(await screen.findByText('اعلان مجاز')).toBeInTheDocument()
    expect(screen.getByText('رد کرده‌اند')).toBeInTheDocument()
    expect(screen.getByText('هنوز پرسیده نشده')).toBeInTheDocument()
    expect(screen.getByText(/۷۰/, { selector: 'b' })).toBeInTheDocument()
  })
})
