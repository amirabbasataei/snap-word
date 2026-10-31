import { Smartphone } from 'lucide-react'
import { Badge } from '@/components/ui/Badge'
import { formatNumber } from '@/lib/fa'
import type { Campaign } from '@/lib/notifications'

/** How a push looks on a phone's lock screen (preview only; the OS draws the real one). */
export function PushBanner({ title, body }: { title: string; body: string }) {
  return (
    <div className="rounded-card border border-border bg-raised p-3.5" aria-label="پیش‌نمایش اعلان فوری">
      <div className="mb-1.5 flex items-center gap-2 text-xs text-muted">
        <span className="grid size-5 place-items-center rounded-md bg-blue text-on-accent" aria-hidden>
          <Smartphone className="size-3" />
        </span>
        <span>زنجیر</span>
        <span>· اکنون</span>
      </div>
      <p className="text-sm font-semibold text-text">{title || 'عنوان اعلان'}</p>
      <p className="mt-0.5 whitespace-pre-line text-sm text-muted">{body || 'متن اعلان اینجا نمایش داده می‌شود.'}</p>
    </div>
  )
}

/** How the message appears in the app's «اعلان‌ها» inbox. */
export function InboxCard({ title, body }: { title: string; body: string }) {
  return (
    <div className="rounded-card border border-border bg-surface p-3.5" aria-label="پیش‌نمایش پیام درون‌برنامه">
      <p className="text-sm font-semibold text-text">{title || 'عنوان پیام'}</p>
      <p className="mt-0.5 whitespace-pre-line text-sm text-muted">{body || 'متن پیام اینجا نمایش داده می‌شود.'}</p>
      <p className="mt-2 text-end text-xs text-blue">باشه</p>
    </div>
  )
}

export function ChannelBadges({ c }: { c: Pick<Campaign, 'push' | 'inapp'> }) {
  return (
    <span className="inline-flex flex-wrap gap-1.5">
      {c.push && <Badge tone="blue">اعلان فوری</Badge>}
      {c.inapp && <Badge tone="green">درون‌برنامه</Badge>}
    </span>
  )
}

const PUSH_STATUS: Record<Campaign['push_status'], { label: string; tone: 'neutral' | 'orange' | 'green' | 'pink' }> = {
  none: { label: '—', tone: 'neutral' },
  sending: { label: 'در حال ارسال…', tone: 'orange' },
  done: { label: 'ارسال شد', tone: 'green' },
  failed: { label: 'ناموفق', tone: 'pink' },
  interrupted: { label: 'نیمه‌کاره ماند', tone: 'pink' },
}

export function PushStatusBadge({ c }: { c: Campaign }) {
  if (!c.push) return <span className="text-muted">—</span>
  const s = PUSH_STATUS[c.push_status]
  return <Badge tone={s.tone}>{s.label}</Badge>
}

/** «۱۲ از ۱۴ دستگاه» style result line for the push part of a campaign. */
export function pushResultText(c: Campaign): string {
  if (!c.push) return '—'
  if (c.push_status === 'sending') return 'در حال ارسال…'
  return `${formatNumber(c.push_sent)} از ${formatNumber(c.push_devices)} دستگاه`
}
