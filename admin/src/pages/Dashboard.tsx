import type { ReactNode } from 'react'
import { useMemo } from 'react'
import { useIsFetching } from '@tanstack/react-query'
import { Coins, Crown, Gift, RefreshCw, Swords, Trophy, Users } from 'lucide-react'
import { EChart } from '@/components/charts/EChart'
import { useChartColors } from '@/components/charts/useChartColors'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { Skeleton } from '@/components/ui/Skeleton'
import { StatCard } from '@/components/ui/StatCard'
import {
  DASHBOARD_REFRESH_MS,
  matchesOf,
  sumLast,
  useDashboardSummary,
  useDashboardTimeseries,
  weekOverWeek,
  type DashboardDay,
  type DashboardSummary,
} from '@/lib/dashboard'
import { messageOf } from '@/lib/errors'
import { formatJalaliDateTime, formatNumber, toFa } from '@/lib/fa'
import {
  activityOption,
  matchesBarOption,
  MODE_COLOR,
  MODE_KEYS,
  MODE_LABEL,
  modeDonutOption,
  modeTotals,
} from './dashboard/chartOptions'

export function Dashboard() {
  const summary = useDashboardSummary()
  const series = useDashboardTimeseries()
  const fetching = useIsFetching({ queryKey: ['admin', 'dashboard'] }) > 0

  const refetch = () => {
    void summary.refetch()
    void series.refetch()
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-text">داشبورد</h1>
          <p className="text-xs text-muted">
            {summary.data
              ? `آخرین به‌روزرسانی: ${formatJalaliDateTime(summary.data.generated_at)} · تازه‌سازی خودکار هر ${toFa(DASHBOARD_REFRESH_MS / 1000)} ثانیه`
              : `تازه‌سازی خودکار هر ${toFa(DASHBOARD_REFRESH_MS / 1000)} ثانیه`}
          </p>
        </div>
        <Button variant="secondary" size="sm" onClick={refetch} disabled={fetching}>
          <RefreshCw className={fetching ? 'size-4 animate-spin' : 'size-4'} aria-hidden />
          تازه‌سازی
        </Button>
      </div>

      <StatGrid summary={summary} days={series.data} />

      <div className="grid gap-4 xl:grid-cols-3">
        <ChartCard title="فعالیت روزانه" subtitle="مسابقه‌ها و ثبت‌نام‌ها در ۳۰ روز گذشته" className="xl:col-span-2" query={series}>
          {(days) => <ActivityChart days={days} />}
        </ChartCard>
        <ChartCard title="سهم حالت‌ها" subtitle="مسابقه‌های ۳۰ روز گذشته" query={series}>
          {(days) => <ModeShare days={days} />}
        </ChartCard>
        <ChartCard title="مسابقه‌ها در ۷ روز" subtitle="به تفکیک حالت" className="xl:col-span-2" query={series}>
          {(days) => <WeekBars days={days} />}
        </ChartCard>
        <LiveCard summary={summary} />
      </div>
    </div>
  )
}

type Query<T> = { data: T | undefined; isPending: boolean; isError: boolean; error: unknown; refetch: () => unknown }

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

function ChartCard({
  title,
  subtitle,
  className,
  query,
  children,
}: {
  title: string
  subtitle: string
  className?: string
  query: Query<DashboardDay[]>
  children: (days: DashboardDay[]) => ReactNode
}) {
  return (
    <Card className={className}>
      <CardHeader title={title} actions={<span className="hidden text-xs text-muted sm:inline">{subtitle}</span>} />
      <CardBody>
        {query.isError && !query.data ? (
          <ErrorBox error={query.error} onRetry={() => void query.refetch()} />
        ) : query.data ? (
          children(query.data)
        ) : (
          <Skeleton className="h-64 w-full" />
        )}
      </CardBody>
    </Card>
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

function ActivityChart({ days }: { days: DashboardDay[] }) {
  const c = useChartColors()
  const option = useMemo(() => activityOption(c, days), [c, days])
  const matches = days.reduce((a, d) => a + matchesOf(d), 0)
  const signups = days.reduce((a, d) => a + d.signups, 0)
  return (
    <div className="space-y-3">
      <Legend
        items={[
          { color: c.blue, label: 'مسابقه‌ها', value: formatNumber(matches) },
          { color: c.green, label: 'ثبت‌نام‌ها', value: formatNumber(signups) },
        ]}
      />
      <EChart
        option={option}
        height={280}
        label={`نمودار فعالیت روزانه: ${formatNumber(matches)} مسابقه و ${formatNumber(signups)} ثبت‌نام در ${toFa(days.length)} روز`}
      />
    </div>
  )
}

function WeekBars({ days }: { days: DashboardDay[] }) {
  const c = useChartColors()
  const week = useMemo(() => days.slice(-7), [days])
  const option = useMemo(() => matchesBarOption(c, week), [c, week])
  const totals = modeTotals(week)
  return (
    <div className="space-y-3">
      <Legend items={MODE_KEYS.map((k) => ({ color: c[MODE_COLOR[k]], label: MODE_LABEL[k], value: formatNumber(totals[k]) }))} />
      <EChart option={option} height={260} label={`نمودار مسابقه‌های ۷ روز گذشته: ${formatNumber(week.reduce((a, d) => a + matchesOf(d), 0))} مسابقه`} />
    </div>
  )
}

function ModeShare({ days }: { days: DashboardDay[] }) {
  const c = useChartColors()
  const totals = useMemo(() => modeTotals(days), [days])
  const sum = MODE_KEYS.reduce((a, k) => a + totals[k], 0)
  const option = useMemo(() => modeDonutOption(c, totals), [c, totals])
  if (sum === 0) {
    return <p className="py-16 text-center text-sm text-muted">در این بازه هنوز مسابقه‌ای ثبت نشده است.</p>
  }
  return (
    <div className="space-y-4">
      <div className="relative">
        <EChart option={option} height={200} label={`سهم حالت‌ها از ${formatNumber(sum)} مسابقه`} />
        <div className="pointer-events-none absolute inset-0 grid place-items-center text-center">
          <div>
            <p className="tabular text-xl font-semibold text-text">{formatNumber(sum)}</p>
            <p className="text-xs text-muted">مسابقه</p>
          </div>
        </div>
      </div>
      <ul className="space-y-2 text-xs">
        {MODE_KEYS.map((k) => (
          <li key={k} className="flex items-center justify-between gap-3">
            <span className="flex items-center gap-2 text-muted">
              <span aria-hidden className="size-2.5 rounded-full" style={{ background: c[MODE_COLOR[k]] }} />
              {MODE_LABEL[k]}
            </span>
            <span className="tabular text-text">
              {formatNumber(totals[k])} <span className="text-muted">({toFa(Math.round((totals[k] / sum) * 100))}٪)</span>
            </span>
          </li>
        ))}
      </ul>
    </div>
  )
}

function StatCardSkeleton() {
  return (
    <div className="rounded-card border border-border bg-surface p-5">
      <Skeleton className="h-4 w-24" />
      <Skeleton className="mt-3 h-8 w-32" />
      <Skeleton className="mt-4 h-10 w-full" />
    </div>
  )
}

function StatGrid({ summary, days }: { summary: Query<DashboardSummary>; days: DashboardDay[] | undefined }) {
  const s = summary.data
  if (summary.isError && !s) {
    return (
      <Card>
        <ErrorBox error={summary.error} onRetry={() => void summary.refetch()} />
      </Card>
    )
  }
  if (!s) {
    return (
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {Array.from({ length: 6 }, (_, i) => (
          <StatCardSkeleton key={i} />
        ))}
      </div>
    )
  }

  // Sparklines/deltas come from the time series; without it the tiles show numbers only.
  const spark = (pick: (d: DashboardDay) => number) => days?.slice(-14).map(pick)
  const wow = (pick: (d: DashboardDay) => number) => (days ? weekOverWeek(days, pick) : undefined)
  const claimed7d = days ? sumLast(days, 7, (d) => d.coins_claimed) : undefined

  return (
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
      <StatCard
        title="کاربران ثبت‌نام‌شده"
        value={formatNumber(s.users.total)}
        icon={Users}
        tone="blue"
        series={spark((d) => d.signups)}
        delta={wow((d) => d.signups)}
        caption={`${formatNumber(s.users.new_today)} امروز · ${formatNumber(s.users.new_7d)} در ۷ روز اخیر`}
      />
      <StatCard
        title="مسابقه‌های امروز"
        value={formatNumber(s.matches_today.total)}
        icon={Swords}
        tone="orange"
        series={spark(matchesOf)}
        delta={wow(matchesOf)}
        caption={`${formatNumber(s.matches_today.versus)} رودررو · ${formatNumber(s.matches_today.ai_online)} هوش مصنوعی آنلاین`}
      />
      <StatCard
        title="شرکت‌کنندگان چالش روزانه (امروز)"
        value={formatNumber(s.daily_participants_today)}
        icon={Trophy}
        tone="yellow"
        series={spark((d) => d.daily_attempts)}
        delta={wow((d) => d.daily_attempts)}
      />
      <StatCard title="اشتراک ویژهٔ فعال" value={formatNumber(s.users.premium_active)} icon={Crown} tone="pink" />
      <StatCard title="سکهٔ در گردش" value={formatNumber(s.coins_in_circulation)} icon={Coins} tone="green" />
      <StatCard
        title="پاداش‌های دریافت‌نشده"
        value={formatNumber(s.unclaimed_rewards.count)}
        icon={Gift}
        tone="blue"
        caption={
          `${formatNumber(s.unclaimed_rewards.coins)} سکه` +
          (claimed7d !== undefined ? ` · ${formatNumber(claimed7d)} سکه دریافت‌شده در ۷ روز` : '')
        }
      />
    </div>
  )
}

function LiveCard({ summary }: { summary: Query<DashboardSummary> }) {
  const s = summary.data
  return (
    <Card>
      <CardHeader title="وضعیت زنده" />
      <CardBody>
        {summary.isError && !s ? (
          <ErrorBox error={summary.error} onRetry={() => void summary.refetch()} />
        ) : !s ? (
          <div className="space-y-3">
            {Array.from({ length: 5 }, (_, i) => (
              <Skeleton key={i} className="h-6 w-full" />
            ))}
          </div>
        ) : (
          <dl className="space-y-3 text-sm">
            <Row label="اتاق‌های در جریان" value={formatNumber(s.live.active_rooms)} />
            <Row label="اتاق‌های در انتظار حریف" value={formatNumber(s.live.waiting_rooms)} />
            <Row label="بازیکنان متصل" value={formatNumber(s.live.connected_players)} />
            <Row label="صف جست‌وجوی حریف" value={formatNumber(s.live.queue_length)} />
            <div className="flex items-center justify-between gap-3 border-t border-border pt-3">
              <dt className="text-muted">اعلان‌های فشاری (FCM)</dt>
              <dd>
                <Badge tone={s.fcm_configured ? 'green' : 'yellow'}>{s.fcm_configured ? 'پیکربندی شده' : 'پیکربندی نشده'}</Badge>
              </dd>
            </div>
          </dl>
        )}
      </CardBody>
    </Card>
  )
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <dt className="text-muted">{label}</dt>
      <dd className="tabular font-medium text-text">{value}</dd>
    </div>
  )
}
