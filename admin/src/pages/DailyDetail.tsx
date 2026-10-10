import { ArrowRight, Pencil } from 'lucide-react'
import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '@/auth/AuthContext'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { Skeleton } from '@/components/ui/Skeleton'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/Tabs'
import { roleAtLeast } from '@/layout/nav'
import { useDailyDetail, type DailyDetail as Detail } from '@/lib/content'
import { ApiError, messageOf } from '@/lib/errors'
import { formatJalaliDateTime, formatNumber } from '@/lib/fa'
import { dayLabel, DayStatusBadges, LetterTile, PAYOUT_LABEL, StartLetterDialog } from './content/daily'
import { NotFound } from './NotFound'

export function DailyDetail() {
  const { date = '' } = useParams()
  const query = useDailyDetail(date)

  if (query.isPending) {
    return (
      <div className="space-y-4" aria-busy>
        <BackLink />
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    )
  }
  if (query.isError) {
    if (query.error instanceof ApiError && (query.error.status === 404 || query.error.code === 'invalid_date')) return <NotFound />
    return (
      <div className="space-y-4">
        <BackLink />
        <Card>
          <div role="alert" className="flex flex-col items-center gap-3 px-4 py-12 text-center">
            <p className="text-sm text-pink">{messageOf(query.error)}</p>
            <Button variant="secondary" size="sm" onClick={() => void query.refetch()}>تلاش دوباره</Button>
          </div>
        </Card>
      </div>
    )
  }
  return <Loaded day={query.data} />
}

function BackLink() {
  return (
    <Link to="/content/daily" className="inline-flex items-center gap-1.5 text-sm text-muted hover:text-text">
      <ArrowRight className="size-4" aria-hidden />
      چالش روزانه
    </Link>
  )
}

function Tile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-card border border-border bg-surface px-4 py-3">
      <p className="text-xs text-muted">{label}</p>
      <p className="tabular mt-1 text-xl font-semibold text-text">{value}</p>
    </div>
  )
}

function Loaded({ day }: { day: Detail }) {
  const { admin } = useAuth()
  const canEdit = admin ? roleAtLeast(admin.role, 'operator') : false
  const [editing, setEditing] = useState(false)
  const payout = PAYOUT_LABEL[day.payout.state]
  const r = day.payout.rewards

  const board: Column<Detail['board'][number]>[] = [
    { key: 'rank', header: 'رتبه', cell: (b) => formatNumber(b.rank) },
    {
      key: 'user',
      header: 'بازیکن',
      cell: (b) => (
        <span className="inline-flex flex-wrap items-center gap-2">
          <Link to={`/users/${b.user_id}`} className="hover:text-blue">{b.username || '—'}</Link>
          {b.banned && <Badge tone="pink">مسدود</Badge>}
        </span>
      ),
    },
    { key: 'score', header: 'بهترین امتیاز', cell: (b) => formatNumber(b.score) },
    { key: 'chain', header: 'طول زنجیر', className: 'hidden sm:table-cell', cell: (b) => formatNumber(b.chain_length) },
  ]
  const attempts: Column<Detail['attempts'][number]>[] = [
    {
      key: 'user',
      header: 'بازیکن',
      cell: (a) => <Link to={`/users/${a.user_id}`} className="hover:text-blue">{a.username || '—'}</Link>,
    },
    { key: 'n', header: 'تلاش', cell: (a) => (a.attempt === 1 ? 'رایگان' : `${formatNumber(a.attempt)} (پولی)`) },
    { key: 'score', header: 'امتیاز', cell: (a) => formatNumber(a.score) },
    {
      key: 'chain',
      header: 'زنجیر',
      cell: (a) => (
        <span className="flex max-w-md flex-wrap items-center gap-1" title={a.word_chain.join(' ← ')}>
          {a.word_chain.map((w, i) => (
            <Badge key={i} tone="neutral" className="font-normal">{w}</Badge>
          ))}
        </span>
      ),
    },
    { key: 'at', header: 'زمان', className: 'hidden md:table-cell', cell: (a) => formatJalaliDateTime(a.completed_at) },
  ]

  return (
    <div className="space-y-6">
      <BackLink />

      <Card>
        <CardBody className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <LetterTile letter={day.start_letter} className="size-16 text-3xl" />
            <div className="space-y-1.5">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="text-xl font-semibold text-text">چالش #{formatNumber(day.day_number)}</h1>
                <DayStatusBadges status={day.status} generated={day.generated} customized={day.customized} />
              </div>
              <p className="tabular text-sm text-muted">{dayLabel(day.date)}</p>
            </div>
          </div>
          {canEdit && day.editable && (
            <Button variant="secondary" size="sm" onClick={() => setEditing(true)}>
              <Pencil className="size-4" aria-hidden />
              تغییر حرف شروع
            </Button>
          )}
        </CardBody>
      </Card>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-5">
        <Tile label="بازیکن" value={formatNumber(day.stats.players)} />
        <Tile label="تلاش" value={formatNumber(day.stats.attempts)} />
        <Tile label="تلاش دوم (پولی)" value={formatNumber(day.stats.retries)} />
        <Tile label="بهترین امتیاز" value={day.stats.players > 0 ? formatNumber(day.stats.best_score) : '—'} />
        <Tile label="میانگین امتیاز" value={day.stats.players > 0 ? formatNumber(day.stats.avg_score) : '—'} />
      </div>

      <Card>
        <CardHeader title="جایزه‌ها" actions={<Badge tone={payout.tone}>{payout.text}</Badge>} />
        <CardBody className="space-y-3">
          <p className="text-sm text-muted">{payout.hint}</p>
          {(r.done_created > 0 || r.rank_created > 0) && (
            <dl className="grid gap-x-8 gap-y-2 text-sm sm:grid-cols-3">
              <div>
                <dt className="text-xs text-muted">جایزهٔ شرکت</dt>
                <dd className="tabular">{formatNumber(r.done_created)} ساخته‌شده · {formatNumber(r.done_claimed)} برداشته‌شده</dd>
              </div>
              <div>
                <dt className="text-xs text-muted">جایزهٔ رتبه</dt>
                <dd className="tabular">{formatNumber(r.rank_created)} ساخته‌شده · {formatNumber(r.rank_claimed)} برداشته‌شده</dd>
              </div>
              <div>
                <dt className="text-xs text-muted">مجموع سکه</dt>
                <dd className="tabular">{formatNumber(r.coins)}</dd>
              </div>
            </dl>
          )}
        </CardBody>
      </Card>

      <Tabs defaultValue="board">
        <TabsList>
          <TabsTrigger value="board">جدول روز</TabsTrigger>
          <TabsTrigger value="attempts">تلاش‌ها</TabsTrigger>
        </TabsList>
        <TabsContent value="board" className="pt-5">
          <Card>
            <DataTable columns={board} rows={day.board} rowKey={(b) => b.user_id} emptyText="کسی در این روز بازی نکرده است." />
          </Card>
        </TabsContent>
        <TabsContent value="attempts" className="pt-5">
          <Card>
            <DataTable
              columns={attempts}
              rows={day.attempts}
              rowKey={(a) => `${a.user_id}-${a.attempt}`}
              emptyText="تلاشی ثبت نشده است."
            />
            {day.stats.attempts > day.attempts.length && (
              <p className="border-t border-border px-4 py-3 text-xs text-muted">
                {formatNumber(day.attempts.length)} تلاش آخر از {formatNumber(day.stats.attempts)} تلاش نمایش داده می‌شود.
              </p>
            )}
          </Card>
        </TabsContent>
      </Tabs>

      {editing && (
        <StartLetterDialog
          date={day.date}
          dayNumber={day.day_number}
          current={day.start_letter}
          letters={day.eligible_letters}
          onClose={() => setEditing(false)}
        />
      )}
    </div>
  )
}
