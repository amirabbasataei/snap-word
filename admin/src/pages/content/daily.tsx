import { useState } from 'react'
import { Badge, type Tone } from '@/components/ui/Badge'
import { ReasonDialog } from '@/components/ui/ReasonDialog'
import { useToast } from '@/components/ui/Toast'
import { cn } from '@/lib/cn'
import { useSetStartLetter, type DayStatus, type PayoutState } from '@/lib/content'
import { formatJalaliDay, formatNumber } from '@/lib/fa'

export const STATUS_LABEL: Record<DayStatus, { text: string; tone: Tone }> = {
  past: { text: 'گذشته', tone: 'neutral' },
  today: { text: 'امروز', tone: 'green' },
  future: { text: 'آینده', tone: 'blue' },
}

export const PAYOUT_LABEL: Record<PayoutState, { text: string; tone: Tone; hint: string }> = {
  not_due: { text: 'هنوز زمان پرداخت نرسیده', tone: 'neutral', hint: 'جایزه‌ها بعد از نیمه‌شب (به وقت ایران) پرداخت می‌شوند.' },
  no_players: { text: 'بدون شرکت‌کننده', tone: 'neutral', hint: 'کسی بازی نکرده؛ جایزه‌ای پرداخت نمی‌شود.' },
  paid: { text: 'پرداخت‌شده', tone: 'green', hint: 'جایزه‌ها در صندوق بازیکنان گذاشته شده است.' },
  pending: { text: 'در انتظار پرداخت', tone: 'yellow', hint: 'زمان‌بند ظرف چند دقیقه جایزه‌ها را پرداخت می‌کند.' },
  missed: { text: 'پرداخت‌نشده', tone: 'pink', hint: 'زمان‌بند فقط روز گذشته را پرداخت می‌کند؛ این روز دیگر خودکار پرداخت نمی‌شود.' },
}

export function dayLabel(date: string): string {
  return formatJalaliDay(date, 'yyyy/MM/dd')
}

export function LetterTile({ letter, className }: { letter: string; className?: string }) {
  return (
    <span
      className={cn('inline-grid size-9 place-items-center rounded-lg bg-active text-lg font-semibold text-text', className)}
      aria-label={`حرف ${letter}`}
    >
      {letter}
    </span>
  )
}

export function DayStatusBadges({ status, generated, customized }: { status: DayStatus; generated: boolean; customized: boolean }) {
  const s = STATUS_LABEL[status]
  return (
    <span className="inline-flex flex-wrap gap-1.5">
      <Badge tone={s.tone}>{s.text}</Badge>
      {!generated && <Badge tone="neutral">ساخته‌نشده</Badge>}
      {customized && <Badge tone="orange">دستی</Badge>}
    </span>
  )
}

/** Picks a new start letter for a future day (audited, reason required). */
export function StartLetterDialog({
  date, dayNumber, current, letters, onClose,
}: {
  date: string
  dayNumber: number
  current: string
  letters: string[]
  onClose: () => void
}) {
  const set = useSetStartLetter()
  const { toast } = useToast()
  const [letter, setLetter] = useState(current)
  return (
    <ReasonDialog
      open
      onOpenChange={(o) => !o && onClose()}
      title={`حرف شروع چالش ${formatNumber(dayNumber)}`}
      description={`${dayLabel(date)} — فقط حرف‌هایی که کلمات کافی در فرهنگ لغت دارند انتخاب می‌شوند. حرف فعلی: «${current}».`}
      confirmLabel="ذخیرهٔ حرف"
      valid={letter !== current}
      onSubmit={async (reason) => {
        await set.mutateAsync({ date, letter, reason })
        toast({ title: `حرف شروع روی «${letter}» تنظیم شد.` })
      }}
    >
      <div role="radiogroup" aria-label="حرف شروع" className="grid grid-cols-6 gap-2 sm:grid-cols-8">
        {letters.map((l) => (
          <button
            key={l}
            type="button"
            role="radio"
            aria-checked={l === letter}
            onClick={() => setLetter(l)}
            className={cn(
              'grid h-10 cursor-pointer place-items-center rounded-lg border text-base transition',
              l === letter ? 'border-blue bg-active font-semibold text-text' : 'border-border bg-raised text-muted hover:text-text',
            )}
          >
            {l}
          </button>
        ))}
      </div>
    </ReasonDialog>
  )
}
