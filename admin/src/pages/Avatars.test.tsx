import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { mount } from './content/testkit'
import { Avatars, validateAvatarFile } from './Avatars'

const LIST = {
  items: [
    { id: 'lion', sort_order: 1, content_type: 'image/png', bytes: 40_960, updated_at: '2026-10-01T10:00:00Z', users: 3, active_users: 2 },
    { id: 'fox', sort_order: 2, content_type: 'image/webp', bytes: 2_048, updated_at: '2026-10-02T10:00:00Z', users: 0, active_users: 0 },
  ],
  max_bytes: 262_144,
  types: ['image/png', 'image/jpeg', 'image/webp'],
}

function setup(role: 'viewer' | 'operator' | 'owner') {
  return mount(role, <Avatars />, (url, init) => {
    if (url.endsWith('/avatars') && (init?.method ?? 'GET') === 'GET') return Response.json({ data: LIST })
    if (url.endsWith('/avatars/lion/usage')) return Response.json({ data: { id: 'lion', users: 3, active_users: 2 } })
    if (init?.method === 'DELETE') return Response.json({ data: { id: 'lion', users_cleared: 3 } })
  })
}

afterEach(() => vi.unstubAllGlobals())

describe('validateAvatarFile', () => {
  const limits = { max_bytes: 262_144, types: LIST.types }
  it('accepts allowed types within the limit (boundary included)', () => {
    expect(validateAvatarFile({ type: 'image/png', size: 262_144 }, limits)).toBeNull()
    expect(validateAvatarFile({ type: 'image/webp', size: 1 }, limits)).toBeNull()
  })
  it('rejects wrong types, empty files and oversized files with a Persian reason', () => {
    expect(validateAvatarFile({ type: 'image/gif', size: 10 }, limits)).toMatch(/PNG/)
    expect(validateAvatarFile({ type: '', size: 10 }, limits)).toMatch(/PNG/)
    expect(validateAvatarFile({ type: 'image/png', size: 0 }, limits)).toMatch(/خالی/)
    const big = validateAvatarFile({ type: 'image/png', size: 262_145 }, limits)
    expect(big).toMatch(/۲۵۶ کیلوبایت/)
    expect(big).toMatch(/۲۵۶/)
  })
})

describe('Avatars', () => {
  it('shows the grid with sizes and usage; a viewer cannot change anything', async () => {
    setup('viewer')
    expect(await screen.findByAltText('آواتار lion')).toBeInTheDocument()
    expect(screen.getByText('۳ کاربر')).toBeInTheDocument()
    expect(screen.getByText('۴۰ کیلوبایت · PNG')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'آواتار جدید' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /حذف آواتار/ })).not.toBeInTheDocument()
  })

  it('the delete dialog shows the live usage count and needs the typed id', async () => {
    const calls = setup('operator')
    await screen.findByAltText('آواتار lion')
    await userEvent.click(screen.getByRole('button', { name: 'حذف آواتار lion' }))
    const dialog = await screen.findByRole('dialog')
    expect(await within(dialog).findByText(/۳ کاربر این آواتار را انتخاب کرده‌اند \(۲ نفر با اشتراک فعال/)).toBeInTheDocument()

    const confirm = within(dialog).getByRole('button', { name: 'حذف' })
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'تصویر نامناسب')
    expect(confirm).toBeDisabled()
    await userEvent.type(within(dialog).getByLabelText(/را تایپ کنید/), 'lion')
    await userEvent.click(confirm)
    await waitFor(() => expect(calls.some((c) => c.init?.method === 'DELETE')).toBe(true))
    expect(calls.find((c) => c.init?.method === 'DELETE')!.body).toEqual({ reason: 'تصویر نامناسب' })
  })

  it('upload rejects a wrong type and an oversized file before any request, and sends a valid one as multipart', async () => {
    const calls = setup('operator')
    await screen.findByAltText('آواتار lion')
    await userEvent.click(screen.getByRole('button', { name: 'آواتار جدید' }))
    const dialog = await screen.findByRole('dialog')
    const file = within(dialog).getByLabelText('تصویر') as HTMLInputElement
    await userEvent.type(within(dialog).getByLabelText('شناسه'), 'panda')
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'آواتار جدید')
    const submit = within(dialog).getByRole('button', { name: 'بارگذاری' })

    fireEvent.change(file, { target: { files: [new File(['GIF89a'], 'a.gif', { type: 'image/gif' })] } })
    expect(await within(dialog).findByRole('alert')).toHaveTextContent('فقط تصویر PNG، JPEG یا WebP')
    expect(submit).toBeDisabled()

    const huge = new File([new Uint8Array(262_145)], 'big.png', { type: 'image/png' })
    fireEvent.change(file, { target: { files: [huge] } })
    expect(await within(dialog).findByRole('alert')).toHaveTextContent('حداکثر مجاز ۲۵۶ کیلوبایت')
    expect(submit).toBeDisabled()
    expect(calls.some((c) => c.init?.method === 'PUT')).toBe(false)

    URL.createObjectURL = vi.fn(() => 'blob:preview')
    URL.revokeObjectURL = vi.fn()
    const ok = new File([new Uint8Array(1000)], 'ok.png', { type: 'image/png' })
    fireEvent.change(file, { target: { files: [ok] } })
    await waitFor(() => expect(submit).toBeEnabled())
    await userEvent.click(submit)
    await waitFor(() => expect(calls.some((c) => c.init?.method === 'PUT')).toBe(true))
    const put = calls.find((c) => c.init?.method === 'PUT')!
    expect(put.url).toMatch(/\/avatars\/panda$/)
    expect(put.init?.body).toBeInstanceOf(FormData)
    expect((put.body as Record<string, unknown>).reason).toBe('آواتار جدید')
    expect((put.body as Record<string, unknown>).image).toBeInstanceOf(File)
  })
})
