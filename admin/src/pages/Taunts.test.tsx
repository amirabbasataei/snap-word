import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { mount } from './content/testkit'
import { Taunts } from './Taunts'

const LIST = {
  items: [
    { id: 'hurry_up', text: 'زود باش!', sort_order: 1 },
    { id: 'lucky', text: 'شانس آوردی!', sort_order: 2 },
    { id: 'oops', text: 'ای وای! 😅', sort_order: 3 },
  ],
  max_text_runes: 60,
}

function setup(role: 'viewer' | 'operator' | 'owner') {
  return mount(role, <Taunts />, (url, init) => {
    if (url.endsWith('/taunts') && (init?.method ?? 'GET') === 'GET') return Response.json({ data: LIST })
  })
}

afterEach(() => vi.unstubAllGlobals())

describe('Taunts', () => {
  it('lists the taunts with Persian numbering; a viewer gets no controls', async () => {
    setup('viewer')
    expect(await screen.findByText('زود باش!')).toBeInTheDocument()
    expect(screen.getByText('فهرست تیکه‌ها (۳)')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'افزودن' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /انتقال به/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /حذف تیکه/ })).not.toBeInTheDocument()
  })

  it('moving a taunt shows an unsaved bar; saving needs a reason and posts the new order', async () => {
    const calls = setup('operator')
    await screen.findByText('زود باش!')
    const down = screen.getAllByRole('button', { name: 'انتقال به پایین' })
    await userEvent.click(down[0])
    expect(await screen.findByText('ترتیب تغییر کرده و هنوز ذخیره نشده است.')).toBeInTheDocument()
    // editing other things is locked until the order is saved or cancelled
    expect(screen.getByRole('button', { name: 'افزودن' })).toBeDisabled()

    await userEvent.click(screen.getByRole('button', { name: 'ذخیرهٔ ترتیب' }))
    const dialog = await screen.findByRole('dialog')
    const confirm = within(dialog).getByRole('button', { name: 'ذخیرهٔ ترتیب' })
    expect(confirm).toBeDisabled()
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'مرتب‌سازی دوباره')
    await userEvent.click(confirm)

    await waitFor(() => expect(calls.some((c) => c.url.endsWith('/taunts/reorder'))).toBe(true))
    const post = calls.find((c) => c.url.endsWith('/taunts/reorder'))!
    expect(post.init?.method).toBe('POST')
    expect(post.body).toEqual({ ids: ['lucky', 'hurry_up', 'oops'], reason: 'مرتب‌سازی دوباره' })
  })

  it('cancel drops the local reorder', async () => {
    setup('operator')
    await screen.findByText('زود باش!')
    await userEvent.click(screen.getAllByRole('button', { name: 'انتقال به پایین' })[0])
    await userEvent.click(await screen.findByRole('button', { name: 'لغو' }))
    expect(screen.queryByText('ترتیب تغییر کرده و هنوز ذخیره نشده است.')).not.toBeInTheDocument()
  })

  it('add validates the id and counts characters against the limit before enabling submit', async () => {
    const calls = setup('operator')
    await screen.findByText('زود باش!')
    await userEvent.click(screen.getByRole('button', { name: 'افزودن' }))
    const dialog = await screen.findByRole('dialog')
    const submit = within(dialog).getByRole('button', { name: 'افزودن' })

    await userEvent.type(within(dialog).getByLabelText('شناسه'), 'Bad Id')
    expect(within(dialog).getByText(/فقط حرف کوچک انگلیسی/)).toBeInTheDocument()
    await userEvent.clear(within(dialog).getByLabelText('شناسه'))
    await userEvent.type(within(dialog).getByLabelText('شناسه'), 'lucky')
    expect(within(dialog).getByText('این شناسه از قبل وجود دارد.')).toBeInTheDocument()
    await userEvent.clear(within(dialog).getByLabelText('شناسه'))
    await userEvent.type(within(dialog).getByLabelText('شناسه'), 'good_luck')

    const text = within(dialog).getByLabelText('متن تیکه')
    await userEvent.type(text, 'ا'.repeat(61))
    expect(within(dialog).getByText('۶۱ از ۶۰ نویسه — متن بلندتر از حد مجاز است.')).toBeInTheDocument()
    expect(submit).toBeDisabled()
    await userEvent.clear(text)
    await userEvent.type(text, 'موفق باشی 🍀')
    expect(within(dialog).getByText('۱۱ از ۶۰ نویسه')).toBeInTheDocument() // the emoji counts once

    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'تیکهٔ تازه')
    expect(submit).toBeEnabled()
    await userEvent.click(submit)
    await waitFor(() => expect(calls.some((c) => c.init?.method === 'PUT')).toBe(true))
    const put = calls.find((c) => c.init?.method === 'PUT')!
    expect(put.url).toMatch(/\/taunts\/good_luck$/)
    expect(put.body).toEqual({ text: 'موفق باشی 🍀', reason: 'تیکهٔ تازه' })
  })

  it('delete needs the typed id', async () => {
    const calls = setup('owner')
    await screen.findByText('زود باش!')
    await userEvent.click(screen.getByRole('button', { name: 'حذف تیکهٔ شانس آوردی!' }))
    const dialog = await screen.findByRole('dialog')
    const confirm = within(dialog).getByRole('button', { name: 'حذف' })
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'نامناسب بود')
    expect(confirm).toBeDisabled()
    await userEvent.type(within(dialog).getByLabelText(/را تایپ کنید/), 'lucky')
    expect(confirm).toBeEnabled()
    await userEvent.click(confirm)
    await waitFor(() => expect(calls.some((c) => c.init?.method === 'DELETE')).toBe(true))
    expect(calls.find((c) => c.init?.method === 'DELETE')!.body).toEqual({ reason: 'نامناسب بود' })
  })
})
