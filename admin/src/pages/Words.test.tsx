import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { mount } from './content/testkit'
import { Words } from './Words'

const NOW = new Date().toISOString()
const sug = (over: Record<string, unknown>) => ({
  id: 1, word: 'آزمونک', kind: 'add', status: 'pending', outcome: '', reporters: 3, not_a_word: 0, inappropriate: 0,
  review_note: '', reviewed_by: '', reviewed_at: null, created_at: NOW, last_reported_at: NOW,
  in_dictionary: false, ai_blocked: false, known_rejected: false, warnings: [], ...over,
})
const ADD = [
  sug({ id: 1, word: 'آزمونک', reporters: 3 }),
  sug({ id: 2, word: 'کتاب‌ها', reporters: 1, warnings: ['suffix_of_known'] }),
]
const REMOVE = [sug({ id: 7, word: 'بدواژه', kind: 'remove', reporters: 2, inappropriate: 2 })]
const queue = (items: unknown[]) => ({ items, total: items.length, page: 1, page_size: 50, pending: { add: 2, remove: 1 } })

function setup(role: 'viewer' | 'operator' | 'owner') {
  return mount(role, <Words />, (url, init) => {
    if ((init?.method ?? 'GET') !== 'GET') return Response.json({ data: { done: 2, failed: [] } })
    if (url.includes('/words/suggestions?') && url.includes('kind=add')) return Response.json({ data: queue(ADD) })
    if (url.includes('/words/suggestions?') && url.includes('kind=remove')) return Response.json({ data: queue(REMOVE) })
    if (url.includes('/dictionary/misses')) return Response.json({ data: { items: [{ word: 'ناموجود', count: 12, in_dictionary: false, known_rejected: false, warnings: [] }] } })
    if (url.includes('/dictionary/lookup')) {
      return Response.json({ data: { word: 'کتاب', in_dictionary: true, in_base: true, ai_blocked: false, known_rejected: false, warnings: [], suggestions: [] } })
    }
  })
}

afterEach(() => vi.unstubAllGlobals())

describe('Words', () => {
  it('lists pending suggestions with counts and warnings; a viewer gets no actions', async () => {
    setup('viewer')
    expect(await screen.findByText('آزمونک')).toBeInTheDocument()
    expect(screen.getByText('شکل جمع/صفتِ یک کلمهٔ موجود')).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: /پیشنهاد افزودن \(۲\)/ })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /تأیید/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
  })

  it('approving one suggestion posts approve with the optional note', async () => {
    const calls = setup('operator')
    await screen.findByText('آزمونک')
    await userEvent.click(screen.getByRole('button', { name: 'تأیید «آزمونک»' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.type(within(dialog).getByLabelText(/یادداشت/), 'در فرهنگ هست')
    await userEvent.click(within(dialog).getByRole('button', { name: 'تأیید' }))

    await waitFor(() => expect(calls.some((c) => c.url.endsWith('/words/suggestions/1/approve'))).toBe(true))
    const post = calls.find((c) => c.url.endsWith('/words/suggestions/1/approve'))!
    expect(post.init?.method).toBe('POST')
    expect(post.body).toEqual({ outcome: '', note: 'در فرهنگ هست' })
  })

  it('a short note is refused but an empty one is fine', async () => {
    setup('operator')
    await screen.findByText('آزمونک')
    await userEvent.click(screen.getByRole('button', { name: 'تأیید «آزمونک»' }))
    const dialog = await screen.findByRole('dialog')
    const confirm = within(dialog).getByRole('button', { name: 'تأیید' })
    expect(confirm).toBeEnabled()
    await userEvent.type(within(dialog).getByLabelText(/یادداشت/), 'ab')
    expect(confirm).toBeDisabled()
  })

  it('bulk: "select all without warnings" skips flagged rows and posts one bulk call', async () => {
    const calls = setup('operator')
    await screen.findByText('آزمونک')
    await userEvent.click(screen.getByRole('button', { name: 'انتخاب همهٔ بدون هشدار' }))
    expect(screen.getByRole('checkbox', { name: 'انتخاب «آزمونک»' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'انتخاب «کتاب‌ها»' })).not.toBeChecked()
    await userEvent.click(screen.getByRole('checkbox', { name: 'انتخاب «کتاب‌ها»' }))

    await userEvent.click(screen.getByRole('button', { name: 'تأیید انتخاب‌شده‌ها' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'تأیید' }))
    await waitFor(() => expect(calls.some((c) => c.url.endsWith('/words/bulk'))).toBe(true))
    expect(calls.find((c) => c.url.endsWith('/words/bulk'))!.body).toEqual({ ids: [1, 2], action: 'approve', note: '' })
  })

  it('rejecting posts reject', async () => {
    const calls = setup('operator')
    await screen.findByText('آزمونک')
    await userEvent.click(screen.getByRole('button', { name: 'رد «آزمونک»' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'رد' }))
    await waitFor(() => expect(calls.some((c) => c.url.endsWith('/words/suggestions/1/reject'))).toBe(true))
  })

  it('removal: AI-only block needs no reason; dictionary removal needs reason + typed word', async () => {
    const calls = setup('operator')
    await userEvent.click(await screen.findByRole('tab', { name: /گزارش حذف/ }))
    expect(await screen.findByText('بدواژه')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'مسدود برای هوش مصنوعی «بدواژه»' }))
    let dialog = await screen.findByRole('dialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'مسدود کردن' }))
    await waitFor(() => expect(calls.some((c) => c.url.endsWith('/words/suggestions/7/approve'))).toBe(true))
    expect(calls.find((c) => c.url.endsWith('/words/suggestions/7/approve'))!.body).toEqual({ outcome: 'ai_block', note: '' })

    await userEvent.click(screen.getByRole('button', { name: 'حذف «بدواژه» از دیکشنری' }))
    dialog = await screen.findByRole('dialog')
    const confirm = within(dialog).getByRole('button', { name: 'حذف از دیکشنری' })
    expect(confirm).toBeDisabled()
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'کلمه نیست')
    expect(confirm).toBeDisabled() // typed confirmation still missing
    await userEvent.type(within(dialog).getByLabelText(/را تایپ کنید/), 'بدواژه')
    await userEvent.click(confirm)
    await waitFor(() => {
      const removes = calls.filter((c) => c.url.endsWith('/words/suggestions/7/approve'))
      expect(removes.length).toBe(2)
    })
    const last = calls.filter((c) => c.url.endsWith('/words/suggestions/7/approve')).at(-1)!
    expect(last.body).toEqual({ outcome: 'remove', note: 'کلمه نیست' })
  })

  it('misses tab adds a word directly with a reason', async () => {
    const calls = setup('operator')
    await userEvent.click(await screen.findByRole('tab', { name: 'ردشده‌ها در بازی' }))
    expect(await screen.findByText('ناموجود')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'افزودن «ناموجود» به دیکشنری' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'پرکاربرد است')
    await userEvent.click(within(dialog).getByRole('button', { name: 'افزودن' }))
    await waitFor(() => expect(calls.some((c) => c.url.endsWith('/dictionary/words'))).toBe(true))
    expect(calls.find((c) => c.url.endsWith('/dictionary/words'))!.body).toEqual({ word: 'ناموجود', action: 'add', reason: 'پرکاربرد است' })
  })

  it('editor looks a word up and offers the matching actions', async () => {
    setup('operator')
    await userEvent.click(await screen.findByRole('tab', { name: 'ویرایش مستقیم' }))
    await userEvent.type(screen.getByLabelText('کلمه'), 'کتاب')
    await userEvent.click(screen.getByRole('button', { name: 'بررسی' }))
    expect(await screen.findByText('در دیکشنری هست')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'حذف از دیکشنری' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'مسدود برای هوش مصنوعی' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'افزودن' })).not.toBeInTheDocument()
  })
})
