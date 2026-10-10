import type { LucideIcon } from 'lucide-react'
import { cn } from '@/lib/cn'
import { formatPercent } from '@/lib/fa'
import { TONE_TEXT, type Tone } from './Badge'

interface Props {
  title: string
  /** Pre-formatted (Persian digits) — use formatNumber/formatCompact. */
  value: string
  icon: LucideIcon
  tone?: Exclude<Tone, 'neutral'>
  /** Up to 14 daily values for the mini bar sparkline. */
  series?: number[]
  /** Period-over-period change as a ratio (0.25 = +25%); omit when unknown. */
  delta?: number
  /** Small muted line under the value (already Persian-formatted). */
  caption?: string
}

/** Reference stat tile: title, big number, coloured icon, 14-day bars, delta. */
export function StatCard({ title, value, icon: Icon, tone = 'blue', series, delta, caption }: Props) {
  const max = series && series.length ? Math.max(...series, 1) : 1
  return (
    <div className="flex flex-col justify-between overflow-hidden rounded-card border border-border bg-surface">
      <div className="flex items-start justify-between gap-3 px-5 pt-4">
        <div>
          <p className="text-sm text-muted">{title}</p>
          <p className="tabular mt-1 text-2xl font-semibold text-text">{value}</p>
          {caption && <p className="tabular mt-0.5 text-xs text-muted">{caption}</p>}
        </div>
        <Icon className={cn('size-6 shrink-0', TONE_TEXT[tone])} aria-hidden />
      </div>
      <div className="mt-3 flex items-end justify-between gap-3 px-5 pb-0">
        <div className={cn('flex h-10 flex-1 items-end gap-[3px]', TONE_TEXT[tone])} aria-hidden>
          {series?.map((v, i) => (
            <span
              key={i}
              className="w-full max-w-1 rounded-t-sm bg-current"
              style={{ height: `${Math.max(8, (v / max) * 100)}%` }}
            />
          ))}
        </div>
        {delta !== undefined && (
          <span dir="ltr" className={cn('tabular pb-2 text-sm font-medium', delta >= 0 ? 'text-green' : 'text-pink')}>
            {formatPercent(delta, true)}
          </span>
        )}
      </div>
    </div>
  )
}
