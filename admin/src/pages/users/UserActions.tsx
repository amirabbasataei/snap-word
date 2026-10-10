import { useState } from 'react'
import { Input } from '@/components/ui/Input'
import { ReasonDialog } from '@/components/ui/ReasonDialog'
import { Select } from '@/components/ui/Select'
import { useToast } from '@/components/ui/Toast'
import { formatJalaliDateTime, formatNumber, fromFa } from '@/lib/fa'
import { useUserAction, type UserAction, type UserDetail } from '@/lib/users'

export type ActionKind = 'coins' | 'premium' | 'premium_revoke' | 'rename' | 'avatar_clear' | 'ban' | 'unban'

interface Props {
  user: UserDetail
  action: ActionKind | null
  onClose: () => void
}

const MAX_COINS = 1_000_000

/** Parses an operator-typed whole number (Persian or Latin digits); NaN if it is not one. */
export function parseWhole(raw: string): number {
  const t = fromFa(raw.trim())
  return /^\d{1,9}$/.test(t) ? Number(t) : NaN
}

/** One dialog per audited action; only the one named by `action` is open. */
export function UserActions({ user, action, onClose }: Props) {
  const run = useUserAction(user.id)
  const { toast } = useToast()

  // Wraps the mutation so the dialog can show a failure and close on success.
  const submit = async (done: string, payload: UserAction) => {
    await run.mutateAsync(payload)
    toast({ title: done })
  }
  const open = (k: ActionKind) => action === k
  const onOpenChange = (o: boolean) => {
    if (!o) onClose()
  }

  return (
    <>
      <CoinsDialog user={user} open={open('coins')} onOpenChange={onOpenChange} run={run.mutateAsync} onDone={(m) => toast({ title: m })} />
      <PremiumDialog user={user} open={open('premium')} onOpenChange={onOpenChange} run={run.mutateAsync} onDone={(m) => toast({ title: m })} />
      <RenameDialog user={user} open={open('rename')} onOpenChange={onOpenChange} run={run.mutateAsync} onDone={(m) => toast({ title: m })} />

      <ReasonDialog
        open={open('premium_revoke')}
        onOpenChange={onOpenChange}
        title="لغو اشتراک ویژه"
        description="اشتراک ویژهٔ کاربر همین حالا پایان می‌یابد."
        confirmLabel="لغو اشتراک"
        danger
        requireText={user.username}
        onSubmit={(reason) => submit('اشتراک ویژه لغو شد.', { type: 'premium_revoke', reason })}
      />
      <ReasonDialog
        open={open('avatar_clear')}
        onOpenChange={onOpenChange}
        title="حذف آواتار"
        description="آواتار انتخابی کاربر برداشته می‌شود و حرف اول نامش نمایش داده می‌شود."
        confirmLabel="حذف آواتار"
        danger
        onSubmit={(reason) => submit('آواتار حذف شد.', { type: 'avatar_clear', reason })}
      />
      <ReasonDialog
        open={open('ban')}
        onOpenChange={onOpenChange}
        title="مسدودسازی کاربر"
        description="کاربر نمی‌تواند وارد شود، بازی آنلاین کند یا چالش بفرستد و از جدول‌ها حذف می‌شود. نشست‌های فعال با اولین درخواست بعدی قطع می‌شوند."
        confirmLabel="مسدود کن"
        danger
        requireText={user.username}
        onSubmit={(reason) => submit('کاربر مسدود شد.', { type: 'ban', reason })}
      />
      <ReasonDialog
        open={open('unban')}
        onOpenChange={onOpenChange}
        title="رفع مسدودی"
        description="کاربر دوباره می‌تواند وارد شود و بازی کند."
        confirmLabel="رفع مسدودی"
        onSubmit={(reason) => submit('مسدودی برداشته شد.', { type: 'unban', reason })}
      />
    </>
  )
}

interface DialogProps {
  user: UserDetail
  open: boolean
  onOpenChange: (open: boolean) => void
  run: ReturnType<typeof useUserAction>['mutateAsync']
  onDone: (message: string) => void
}

function CoinsDialog({ user, open, onOpenChange, run, onDone }: DialogProps) {
  const [mode, setMode] = useState<'direct' | 'reward'>('direct')
  const [sign, setSign] = useState<'add' | 'sub'>('add')
  const [raw, setRaw] = useState('')

  const n = parseWhole(raw)
  const amount = Number.isNaN(n) ? NaN : sign === 'sub' && mode === 'direct' ? -n : n
  const valid = Number.isInteger(n) && n >= 1 && n <= MAX_COINS && (amount >= 0 || user.coins + amount >= 0)
  const after = mode === 'direct' && valid ? user.coins + amount : null

  return (
    <ReasonDialog
      open={open}
      onOpenChange={(o) => {
        if (!o) {
          setRaw('')
          setSign('add')
          setMode('direct')
        }
        onOpenChange(o)
      }}
      title="تنظیم سکه"
      description={`موجودی فعلی: ${formatNumber(user.coins)} سکه`}
      confirmLabel="ثبت"
      valid={valid}
      onSubmit={async (reason) => {
        await run({ type: 'coins', mode, amount, reason })
        onDone(mode === 'direct' ? 'موجودی کاربر تغییر کرد.' : 'هدیه به صندوق جایزه‌های کاربر اضافه شد.')
      }}
    >
      <div className="flex flex-col gap-1.5">
        <span className="text-sm font-medium text-text">نوع تغییر</span>
        <Select
          label="نوع تغییر"
          className="w-full"
          value={mode}
          onValueChange={(v) => {
            setMode(v as 'direct' | 'reward')
            if (v === 'reward') setSign('add')
          }}
          options={[
            { value: 'direct', label: 'اعمال فوری روی موجودی' },
            { value: 'reward', label: 'هدیهٔ قابل دریافت در صندوق جایزه‌ها' },
          ]}
        />
      </div>
      {mode === 'direct' && (
        <div className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-text">عملیات</span>
          <Select
            label="عملیات"
            className="w-full"
            value={sign}
            onValueChange={(v) => setSign(v as 'add' | 'sub')}
            options={[
              { value: 'add', label: 'افزودن' },
              { value: 'sub', label: 'کسر' },
            ]}
          />
        </div>
      )}
      <Input
        label="تعداد سکه"
        inputMode="numeric"
        value={raw}
        onChange={(e) => setRaw(e.target.value)}
        autoComplete="off"
        error={raw !== '' && !valid ? (sign === 'sub' && mode === 'direct' && n > user.coins ? 'بیشتر از موجودی کاربر است.' : 'عددی صحیح بین ۱ و ۱٬۰۰۰٬۰۰۰ وارد کنید.') : undefined}
        hint={after !== null ? `موجودی پس از تغییر: ${formatNumber(after)}` : mode === 'reward' ? 'کاربر باید خودش آن را دریافت کند؛ موجودی تا آن زمان تغییری نمی‌کند.' : undefined}
      />
    </ReasonDialog>
  )
}

const PRESET_DAYS = [7, 30, 90, 365]

function PremiumDialog({ user, open, onOpenChange, run, onDone }: DialogProps) {
  const [raw, setRaw] = useState('30')
  const days = parseWhole(raw)
  const valid = Number.isInteger(days) && days >= 1 && days <= 3650

  return (
    <ReasonDialog
      open={open}
      onOpenChange={(o) => {
        if (!o) setRaw('30')
        onOpenChange(o)
      }}
      title="اعطا یا تمدید اشتراک ویژه"
      description={
        user.premium && user.premium_until
          ? `اشتراک فعلی تا ${formatJalaliDateTime(user.premium_until)} است؛ روزها به آن اضافه می‌شود.`
          : 'کاربر اشتراک فعالی ندارد؛ از همین حالا محاسبه می‌شود.'
      }
      confirmLabel="ثبت"
      valid={valid}
      onSubmit={async (reason) => {
        await run({ type: 'premium_grant', days, reason })
        onDone('اشتراک ویژه ثبت شد.')
      }}
    >
      <Input
        label="تعداد روز"
        inputMode="numeric"
        value={raw}
        onChange={(e) => setRaw(e.target.value)}
        autoComplete="off"
        error={raw !== '' && !valid ? 'عددی بین ۱ و ۳٬۶۵۰ وارد کنید.' : undefined}
      />
      <div className="flex flex-wrap gap-2" role="group" aria-label="مقدارهای آماده">
        {PRESET_DAYS.map((d) => (
          <button
            key={d}
            type="button"
            onClick={() => setRaw(String(d))}
            className="cursor-pointer rounded-full border border-border bg-raised px-3 py-1 text-xs text-text hover:bg-active"
          >
            {formatNumber(d)} روز
          </button>
        ))}
      </div>
    </ReasonDialog>
  )
}

const USERNAME_RE = /^[\p{L}\p{N}_]{3,20}$/u

function RenameDialog({ user, open, onOpenChange, run, onDone }: DialogProps) {
  const [name, setName] = useState('')
  const trimmed = name.trim()
  const valid = USERNAME_RE.test(trimmed) && trimmed !== user.username

  return (
    <ReasonDialog
      open={open}
      onOpenChange={(o) => {
        if (!o) setName('')
        onOpenChange(o)
      }}
      title="تغییر نام کاربری"
      description={`نام فعلی: ${user.username}`}
      confirmLabel="تغییر نام"
      valid={valid}
      onSubmit={async (reason) => {
        await run({ type: 'rename', username: trimmed, reason })
        onDone('نام کاربری تغییر کرد.')
      }}
    >
      <Input
        label="نام کاربری جدید"
        value={name}
        onChange={(e) => setName(e.target.value)}
        autoComplete="off"
        dir="auto"
        maxLength={20}
        error={trimmed !== '' && !valid ? 'نام باید ۳ تا ۲۰ حرف، عدد یا _ و متفاوت از نام فعلی باشد.' : undefined}
        hint="هر حرف یا عدد (فارسی هم مجاز است) و زیرخط"
      />
    </ReasonDialog>
  )
}
