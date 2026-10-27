import { Activity, Clock, Repeat, Users, UserPlus } from 'lucide-react'
import { useMemo, useState, type ReactNode } from 'react'
import { EChart } from '@/components/charts/EChart'
import { useChartColors } from '@/components/charts/useChartColors'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { Select } from '@/components/ui/Select'
import { Skeleton } from '@/components/ui/Skeleton'
import { StatCard } from '@/components/ui/StatCard'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/Tabs'
import {
  ANALYTICS_RANGES,
  averageRetention,
  EVENT_NAMES,
  eventLabel,
  formatDuration,
  lastDays,
  RETENTION_MAX_OFFSET,
  retentionShare,
  screenLabel,
  useAnalyticsOverview,
  useEventCounts,
  useFunnel,
  useRetention,
  useScreens,
  type AnalyticsOverviewDay,
  type RetentionCohort,
  type ScreenRow,
} from '@/lib/analytics'
import { messageOf } from '@/lib/errors'
import { formatJalaliDay, formatNumber, formatPercent, toFa } from '@/lib/fa'
import { cn } from '@/lib/cn'
import { dauOption, eventsOption, seriesColor } from './analytics/chartOptions'

const RANGE_OPTIONS = ANALYTICS_RANGES.map((d) => ({ value: String(d), label: `${toFa(d)} روز گذشته` }))
const MAX_EVENT_SERIES = 5

export function Analytics() {
  const [days, setDays] = useState<number>(30)
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-text">تحلیل رفتار</h1>
          <p className="text-xs text-muted">
            رویدادهای دستگاه‌ها (مهمان و ثبت‌نام‌شده)؛ روزها به وقت ایران. امروز تا ۱۵ دقیقه عقب است.
          </p>
        </div>
        <Select
          label="بازهٔ زمانی"
          value={String(days)}
          onValueChange={(v) => setDays(Number(v))}
          options={RANGE_OPTIONS}
        />
      </div>

      <Tabs defaultValue="overview">
        <TabsList className="overflow-x-auto">
          <TabsTrigger value="overview">نمای کلی</TabsTrigger>
          <TabsTrigger value="retention">بازگشت کاربران</TabsTrigger>
          <TabsTrigger value="funnel">قیف</TabsTrigger>
          <TabsTrigger value="screens">صفحه‌ها</TabsTrigger>
          <TabsTrigger value="events">رویدادها</TabsTrigger>
        </TabsList>
        <TabsContent value="overview" className="pt-5"><OverviewTab days={days} /></TabsContent>
        <TabsContent value="retention" className="pt-5"><RetentionTab /></TabsContent>
        <TabsContent value="funnel" className="pt-5"><FunnelTab days={days} /></TabsContent>
        <TabsContent value="screens" className="pt-5"><ScreensTab days={days} /></TabsContent>
        <TabsContent value="events" className="pt-5"><EventsTab days={days} /></TabsContent>
      </Tabs>
    </div>
  )
}

function ErrorBox({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  return (
    <div role="alert" className="flex flex-col items-center gap-3 py-10 text-center">
      <p className="text-sm text-pink">{messageOf(error)}</p>
      <Button variant="secondary" size="sm" onClick={onRetry}>
        تلاش دوباره
      </Button>
    </div>
  )
}

function Legend({ items }: { items: { color: string; label: string; value?: string }[] }) {
  return (
    <ul className="flex flex-wrap gap-x-5 gap-y-2 text-xs text-muted">
      {items.map((i) => (
        <li key={i.label} className="flex items-center gap-2">
          <span aria-hidden className="size-2.5 rounded-full" style={{ background: i.color }} />
          <span>{i.label}</span>
          {i.value !== undefined && <b className="tabular font-medium text-text">{i.value}</b>}
        </li>
      ))}
    </ul>
  )
}

// ---------------------------------------------------------------- overview

function OverviewTab({ days }: { days: number }) {
  const q = useAnalyticsOverview(days)
  const c = useChartColors()
  const o = q.data
  const option = useMemo(() => (o ? dauOption(c, o.days) : null), [c, o])

  if (q.isError && !o) return <Card><ErrorBox error={q.error} onRetry={() => void q.refetch()} /></Card>
  if (!o || !option) {
    return (
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {Array.from({ length: 6 }, (_, i) => <Skeleton key={i} className="h-28 w-full" />)}
      </div>
    )
  }

  const series = (pick: (d: AnalyticsOverviewDay) => number) => o.days.slice(-14).map(pick)
  return (
    <div className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <StatCard title="فعال امروز (DAU)" value={formatNumber(o.dau)} icon={Activity} tone="blue" series={series((d) => d.active)}
          caption={`${formatNumber(o.days.at(-1)?.active_users ?? 0)} نفر وارد شده`} />
        <StatCard title="فعال در ۷ روز (WAU)" value={formatNumber(o.wau)} icon={Users} tone="green" />
        <StatCard title="فعال در ۳۰ روز (MAU)" value={formatNumber(o.mau)} icon={Users} tone="yellow"
          caption={`${formatNumber(o.total_installs)} نصب در کل · ${formatNumber(o.linked_installs)} وصل به حساب`} />
        <StatCard title="چسبندگی (DAU ÷ MAU)" value={formatPercent(o.stickiness)} icon={Repeat} tone="orange" />
        <StatCard title="نصب جدید امروز" value={formatNumber(o.new_installs_today)} icon={UserPlus} tone="pink"
          series={series((d) => d.new_installs)} caption={`${formatNumber(o.new_installs_7d)} در ۷ روز اخیر`} />
        <StatCard title="میانگین طول نشست (۷ روز)" value={o.avg_session_ms > 0 ? formatDuration(o.avg_session_ms, toFa) : '—'}
          icon={Clock} tone="blue" series={series((d) => d.sessions)} caption="یک نشست = یک بار حضور در پیش‌زمینه" />
      </div>
      <Card>
        <CardHeader title="کاربران فعال روزانه" />
        <CardBody>
          <div className="space-y-3">
            <Legend items={[
              { color: c.blue, label: 'فعال' },
              { color: c.green, label: 'وارد شده' },
              { color: c.orange, label: 'نصب جدید' },
            ]} />
            <EChart option={option} height={280}
              label={`نمودار کاربران فعال روزانه در ${toFa(o.days.length)} روز؛ امروز ${formatNumber(o.dau)} نفر`} />
          </div>
        </CardBody>
      </Card>
    </div>
  )
}

// --------------------------------------------------------------- retention

const RETENTION_RANGES = [14, 30, 60, 90]

function RetentionTab() {
  const [by, setBy] = useState<'install' | 'user'>('install')
  const [range, setRange] = useState(30)
  const q = useRetention(range, by)

  return (
    <Card>
      <CardHeader
        title="بازگشت کاربران (کوهورت)"
        actions={
          <div className="flex flex-wrap gap-2">
            <Select label="شمارش بر اساس" value={by} onValueChange={(v) => setBy(v as 'install' | 'user')}
              options={[{ value: 'install', label: 'دستگاه (همهٔ بازیکن‌ها)' }, { value: 'user', label: 'حساب کاربری' }]} />
            <Select label="بازهٔ کوهورت‌ها" value={String(range)} onValueChange={(v) => setRange(Number(v))}
              options={RETENTION_RANGES.map((d) => ({ value: String(d), label: `${toFa(d)} روز گذشته` }))} />
          </div>
        }
      />
      <CardBody>
        {q.isError ? <ErrorBox error={q.error} onRetry={() => void q.refetch()} />
          : !q.data ? <Skeleton className="h-64 w-full" />
          : q.data.cohorts.length === 0 ? <p className="py-10 text-center text-sm text-muted">در این بازه هنوز کوهورتی نیست.</p>
          : <RetentionGrid cohorts={q.data.cohorts} by={by} />}
      </CardBody>
    </Card>
  )
}

/** Share of the cohort → blend strength of the blue token over the surface. */
function cellStyle(share: number | null) {
  if (share == null) return undefined
  return { background: `color-mix(in srgb, var(--blue) ${Math.round(Math.min(1, share) * 85)}%, var(--surface))` }
}

function RetentionGrid({ cohorts, by }: { cohorts: RetentionCohort[]; by: 'install' | 'user' }) {
  const avg = useMemo(() => averageRetention(cohorts), [cohorts])
  const offsets = Array.from({ length: RETENTION_MAX_OFFSET + 1 }, (_, i) => i)
  return (
    <div className="space-y-3">
      <p className="text-xs text-muted">
        هر ردیف یک روز است و نشان می‌دهد چند درصد از {by === 'user' ? 'حساب‌هایی که اولین بار آن روز فعال بودند' : 'دستگاه‌هایی که آن روز نصب شدند'} در
        روزهای بعد (D۱ تا D۳۰) دوباره فعال شده‌اند. خانهٔ خالی یعنی آن روز هنوز نرسیده است.
      </p>
      <div className="overflow-x-auto">
        <table className="min-w-max border-separate border-spacing-0.5 text-xs" aria-label="جدول بازگشت کاربران">
          <thead>
            <tr className="text-muted">
              <th className="px-2 py-1 text-start font-normal">کوهورت</th>
              <th className="px-2 py-1 text-start font-normal">تعداد</th>
              {offsets.map((o) => <th key={o} className="tabular min-w-9 px-1 py-1 font-normal">D{toFa(o)}</th>)}
            </tr>
          </thead>
          <tbody>
            {cohorts.map((c) => (
              <tr key={c.cohort}>
                <td className="tabular whitespace-nowrap px-2 py-1 text-text">{formatJalaliDay(c.cohort, 'yyyy/MM/dd')}</td>
                <td className="tabular px-2 py-1 text-muted">{formatNumber(c.size)}</td>
                {offsets.map((o) => {
                  const share = retentionShare(c, o)
                  return (
                    <td key={o} title={c.retained[o] == null ? undefined : `${formatNumber(c.retained[o] as number)} از ${formatNumber(c.size)}`}
                      className={cn('tabular rounded-sm px-1 py-1 text-center', share == null ? 'text-muted' : 'text-text')}
                      style={cellStyle(share)}>
                      {share == null ? '' : toFa(Math.round(share * 100))}
                    </td>
                  )
                })}
              </tr>
            ))}
            <tr className="font-medium">
              <td className="px-2 pt-2 text-text" colSpan={2}>میانگین وزنی</td>
              {avg.map((v, o) => (
                <td key={o} className="tabular px-1 pt-2 text-center text-text">{v == null ? '' : toFa(Math.round(v * 100))}</td>
              ))}
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ funnel

const DEFAULT_STEPS = ['app_open', 'game_start', 'game_end', 'signup']
const EVENT_OPTIONS = EVENT_NAMES.map((n) => ({ value: n, label: eventLabel(n) }))

function FunnelTab({ days }: { days: number }) {
  const [steps, setSteps] = useState<string[]>(DEFAULT_STEPS)
  const q = useFunnel(steps, days)
  const setStep = (i: number, v: string) => setSteps((s) => s.map((x, j) => (j === i ? v : x)))

  return (
    <Card>
      <CardHeader title="قیف مراحل" actions={<span className="hidden text-xs text-muted sm:inline">دستگاه‌هایی که مراحل را به ترتیب انجام داده‌اند</span>} />
      <CardBody>
        <div className="space-y-5">
          <div className="flex flex-wrap items-center gap-2">
            {steps.map((s, i) => (
              <div key={i} className="flex items-center gap-1">
                <span className="tabular text-xs text-muted">{toFa(i + 1)}</span>
                <Select label={`مرحلهٔ ${toFa(i + 1)}`} value={s} onValueChange={(v) => setStep(i, v)} options={EVENT_OPTIONS} />
                {steps.length > 2 && (
                  <Button variant="ghost" size="sm" aria-label={`حذف مرحلهٔ ${toFa(i + 1)}`} onClick={() => setSteps((x) => x.filter((_, j) => j !== i))}>
                    ✕
                  </Button>
                )}
              </div>
            ))}
            {steps.length < 6 && (
              <Button variant="secondary" size="sm" onClick={() => setSteps((s) => [...s, 'signup'])}>افزودن مرحله</Button>
            )}
          </div>

          {q.isError ? <ErrorBox error={q.error} onRetry={() => void q.refetch()} />
            : !q.data ? <Skeleton className="h-48 w-full" />
            : (
              <ol className="space-y-3">
                {q.data.map((st, i) => (
                  <li key={i}>
                    <div className="mb-1 flex items-baseline justify-between gap-3 text-sm">
                      <span className="text-text">{eventLabel(st.name)}</span>
                      <span className="tabular text-muted">
                        <b className="font-medium text-text">{formatNumber(st.count)}</b>
                        {i > 0 && ` · ${formatPercent(st.pct_of_prev)} از مرحلهٔ قبل · ${formatPercent(st.pct_of_first)} از ابتدا`}
                      </span>
                    </div>
                    <div className="h-3 overflow-hidden rounded-full bg-raised" role="img"
                      aria-label={`${eventLabel(st.name)}: ${formatNumber(st.count)} دستگاه`}>
                      <div className="h-full rounded-full bg-blue" style={{ width: `${Math.max(st.pct_of_first * 100, st.count > 0 ? 1.5 : 0)}%` }} />
                    </div>
                  </li>
                ))}
              </ol>
            )}
        </div>
      </CardBody>
    </Card>
  )
}

// ----------------------------------------------------------------- screens

function ScreensTab({ days }: { days: number }) {
  const q = useScreens(days)
  const columns: Column<ScreenRow>[] = [
    { key: 'screen', header: 'صفحه', cell: (r) => <span className="text-text">{screenLabel(r.screen)}</span> },
    { key: 'views', header: 'بازدید', cell: (r) => <span className="tabular">{formatNumber(r.views)}</span> },
    { key: 'median', header: 'میانهٔ زمان حضور', cell: (r) => <span className="tabular">{formatDuration(r.median_ms, toFa)}</span> },
    { key: 'avg', header: 'میانگین زمان حضور', cell: (r) => <span className="tabular">{formatDuration(r.avg_ms, toFa)}</span> },
  ]
  return (
    <Card>
      <CardHeader title="زمان حضور در صفحه‌ها" actions={<span className="hidden text-xs text-muted sm:inline">میانه تقریبی است (میانگین وزنی میانهٔ روزها)</span>} />
      <DataTable columns={columns} rows={q.data} rowKey={(r) => r.screen} loading={q.isPending}
        error={q.isError ? messageOf(q.error) : null} onRetry={() => void q.refetch()} emptyText="هنوز بازدیدی ثبت نشده است." />
    </Card>
  )
}

// ------------------------------------------------------------------ events

function EventsTab({ days }: { days: number }) {
  const q = useEventCounts(days)
  const c = useChartColors()
  const [picked, setPicked] = useState<string[]>(['app_open', 'game_start', 'game_end'])
  const dayList = useMemo(() => lastDays(days), [days])
  const option = useMemo(() => eventsOption(c, dayList, picked, q.data ?? []), [c, dayList, picked, q.data])

  const totals = useMemo(() => {
    const m = new Map<string, number>()
    for (const r of q.data ?? []) m.set(r.name, (m.get(r.name) ?? 0) + r.count)
    return EVENT_NAMES.map((n) => ({ name: n, count: m.get(n) ?? 0 })).sort((a, b) => b.count - a.count)
  }, [q.data])

  const toggle = (n: string) =>
    setPicked((p) => (p.includes(n) ? p.filter((x) => x !== n) : p.length >= MAX_EVENT_SERIES ? p : [...p, n]))

  let body: ReactNode
  if (q.isError) body = <ErrorBox error={q.error} onRetry={() => void q.refetch()} />
  else if (!q.data) body = <Skeleton className="h-72 w-full" />
  else {
    body = (
      <div className="space-y-3">
        <Legend items={picked.map((n, i) => ({ color: seriesColor(c, i), label: eventLabel(n) }))} />
        <EChart option={option} height={280} label={`نمودار تعداد رویدادها در ${toFa(days)} روز`} />
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader title="تعداد رویدادها" actions={<span className="hidden text-xs text-muted sm:inline">حداکثر {toFa(MAX_EVENT_SERIES)} رویداد همزمان</span>} />
        <CardBody>
          <div className="mb-4 flex flex-wrap gap-2">
            {EVENT_NAMES.map((n) => {
              const on = picked.includes(n)
              return (
                <button key={n} type="button" aria-pressed={on} onClick={() => toggle(n)}
                  className={cn('cursor-pointer rounded-full border px-3 py-1 text-xs transition',
                    on ? 'border-blue bg-active text-text' : 'border-border text-muted hover:text-text')}>
                  {eventLabel(n)}
                </button>
              )
            })}
          </div>
          {body}
        </CardBody>
      </Card>
      <Card>
        <CardHeader title="جمع رویدادها در بازه" />
        <CardBody>
          <dl className="grid gap-x-8 gap-y-2 text-sm sm:grid-cols-2 xl:grid-cols-3">
            {totals.map((t) => (
              <div key={t.name} className="flex items-center justify-between gap-3">
                <dt className="text-muted">{eventLabel(t.name)}</dt>
                <dd className="tabular font-medium text-text">{formatNumber(t.count)}</dd>
              </div>
            ))}
          </dl>
        </CardBody>
      </Card>
    </div>
  )
}
