import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { mount } from './content/testkit'
import { Settings } from './Settings'
import type { OtpStatus } from '@/lib/settings'

const ON: OtpStatus = {
  sms_enabled: true, provider_configured: true, bypass_active: false, dev_code: '1111', updated_at: null, updated_by: '',
}
const OFF: OtpStatus = { ...ON, sms_enabled: false, bypass_active: true, updated_at: '2026-10-31T10:00:00Z', updated_by: 'amirabbas' }

function setup(role: 'viewer' | 'operator' | 'owner', initial = ON) {
  let current = initial
  const calls = mount(role, <Settings />, (url, init) => {
    if (!url.endsWith('/settings/otp')) return undefined
    if (init?.method === 'PUT') {
      const body = JSON.parse(String(init.body)) as { sms_enabled: boolean }
      current = body.sms_enabled ? ON : OFF
    }
    return Response.json({ data: current })
  })
  return calls
}

afterEach(() => vi.unstubAllGlobals())

describe('Settings — OTP SMS', () => {
  it('shows the live state; only an owner gets the button', async () => {
    setup('operator')
    expect(await screen.findByText('پیامک فعال (کاوه‌نگار)')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'غیرفعال‌کردن ارسال پیامک' })).not.toBeInTheDocument()
    expect(screen.getByText('فقط مالک می‌تواند این تنظیم را تغییر دهد.')).toBeInTheDocument()
  })

  it('turning SMS off needs the typed word and a reason, then PUTs', async () => {
    const calls = setup('owner')
    await userEvent.click(await screen.findByRole('button', { name: 'غیرفعال‌کردن ارسال پیامک' }))
    const dialog = await screen.findByRole('dialog')
    const confirm = within(dialog).getByRole('button', { name: 'غیرفعال‌کردن' })
    expect(confirm).toBeDisabled()
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'تست ورود محلی')
    expect(confirm).toBeDisabled() // still needs the typed confirmation
    await userEvent.type(within(dialog).getByLabelText(/را تایپ کنید/), 'غیرفعال')
    await userEvent.click(confirm)

    await waitFor(() => expect(calls.some((c) => c.init?.method === 'PUT')).toBe(true))
    expect(calls.find((c) => c.init?.method === 'PUT')!.body).toEqual({ sms_enabled: false, reason: 'تست ورود محلی' })
    expect(await screen.findByText(/پیامک غیرفعال — کد ۱۱۱۱ پذیرفته می‌شود/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'فعال‌کردن ارسال پیامک' })).toBeInTheDocument()
  })

  it('turning it back on only needs a reason', async () => {
    const calls = setup('owner', OFF)
    await userEvent.click(await screen.findByRole('button', { name: 'فعال‌کردن ارسال پیامک' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.type(within(dialog).getByLabelText(/دلیل/), 'پایان آزمایش')
    await userEvent.click(within(dialog).getByRole('button', { name: 'فعال‌کردن' }))
    await waitFor(() => expect(calls.find((c) => c.init?.method === 'PUT')?.body).toEqual({ sms_enabled: true, reason: 'پایان آزمایش' }))
  })
})
