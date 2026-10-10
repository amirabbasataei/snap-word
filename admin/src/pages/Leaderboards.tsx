import { Link, useSearchParams } from 'react-router-dom'
import { Avatar } from '@/components/ui/Avatar'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { Select } from '@/components/ui/Select'
import { Skeleton } from '@/components/ui/Skeleton'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/Tabs'
import { useBoard, useWeeklyRewards, type BoardEntry } from '@/lib/content'
import { messageOf } from '@/lib/errors'
import { formatJalaliDateTime, formatJalaliDay, formatNumber } from '@/lib/fa'

const TABS = ['weekly', 'alltime', 'rewards'] as const
type Tab = (typeof TABS)[number]
const LIMITS = [25, 50, 100]

export function Leaderboards() {
  const [sp, setSp] = useSearchParams()
  const t = sp.get('tab') as Tab | null
  const tab: Tab = t && TABS.includes(t) ? t : 'weekly'
  const limitRaw = Number(sp.get('limit'))
  const limit = LIMITS.includes(limitRaw) ? limitRaw : 50

  function update(next: { tab?: Tab; limit?: number }) {
    const qs = new URLSearchParams()
    const nt = next.tab ?? tab
    const nl = next.limit ?? limit
    if (nt !== 'weekly') qs.set('tab', nt)
    if (nl !== 50) qs.set('limit', String(nl))
    setSp(qs, { replace: true })
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">جدول امتیازات</h1>
        <p className="text-xs text-muted">
          فقط نمایش. کاربران مسدود مثل خود برنامه در جدول‌ها دیده نمی‌شوند. جدول هفتگی هر شنبه ساعت ۰۰:۰۰ (به وقت ایران) پایان می‌یابد.
        </p>
      </div>
      <Tabs value={tab} onValueChange={(v) => update({ tab: v as Tab })}>
        <TabsList className="overflow-x-auto">
          <TabsTrigger value="weekly">هفتگی</TabsTrigger>
          <TabsTrigger value="alltime">همیشه</TabsTrigger>
          <TabsTrigger value="rewards">جایزه‌های هفتگی</TabsTrigger>
        </TabsList>
        <TabsContent value="weekly" className="pt-5"><BoardView kind="weekly" limit={limit} onLimit={(l) => update({ limit: l })} /></TabsContent>
        <TabsContent value="alltime" className="pt-5"><BoardView kind="alltime" limit={limit} onLimit={(l) => update({ limit: l })} /></TabsContent>
        <TabsContent value="rewards" className="pt-5"><RewardsView /></TabsContent>
      </Tabs>
    </div>
  )
}

function BoardView({ kind, limit, onLimit }: { kind: 'weekly' | 'alltime'; limit: number; onLimit: (n: number) => void }) {
  const query = useBoard(kind, limit)
  const columns: Column<BoardEntry>[] = [
    { key: 'rank', header: 'رتبه', cell: (e) => formatNumber(e.rank) },
    {
      key: 'user',
      header: 'بازیکن',
      cell: (e) => (
        <Link to={`/users/${e.user_id}`} className="flex items-center gap-3 hover:text-blue">
          <Avatar
            name={e.username}
            src={e.avatar_id ? `/api/v1/avatars/${encodeURIComponent(e.avatar_id)}/image` : undefined}
            className="size-9"
          />
          <span className="font-medium">{e.username || '—'}</span>
        </Link>
      ),
    },
    { key: 'score', header: 'امتیاز', cell: (e) => formatNumber(e.score) },
  ]
  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border p-4">
        <p className="tabular text-xs text-muted">
          {kind === 'weekly' && query.data?.resets_at
            ? `پایان هفته: ${formatJalaliDateTime(query.data.resets_at)}`
            : kind === 'alltime'
              ? 'مجموع امتیاز بازی‌های رتبه‌دار، از ابتدا (بدون بازنشانی)'
              : ' '}
        </p>
        <Select
          label="تعداد ردیف"
          value={String(limit)}
          onValueChange={(v) => onLimit(Number(v))}
          options={LIMITS.map((n) => ({ value: String(n), label: `${formatNumber(n)} نفر اول` }))}
        />
      </div>
      <DataTable
        columns={columns}
        rows={query.data?.entries}
        rowKey={(e) => e.user_id}
        loading={query.isPending}
        error={query.isError ? messageOf(query.error) : null}
        onRetry={() => void query.refetch()}
        emptyText={kind === 'weekly' ? 'این هفته هنوز امتیازی ثبت نشده است.' : 'هنوز امتیازی ثبت نشده است.'}
      />
    </Card>
  )
}

function RewardsView() {
  const query = useWeeklyRewards()
  if (query.isPending) return <Skeleton className="h-48 w-full" />
  if (query.isError) {
    return (
      <Card>
        <div role="alert" className="flex flex-col items-center gap-3 px-4 py-10 text-center">
          <p className="text-sm text-pink">{messageOf(query.error)}</p>
          <Button variant="secondary" size="sm" onClick={() => void query.refetch()}>تلاش دوباره</Button>
        </div>
      </Card>
    )
  }
  const { weeks, prizes } = query.data
  return (
    <div className="space-y-4">
      <p className="tabular text-xs text-muted">
        جایزهٔ فعلی نفرات اول تا سوم: {prizes.map((p) => formatNumber(p)).join('، ')} سکه.
      </p>
      {weeks.length === 0 ? (
        <Card>
          <CardBody className="py-10 text-center text-sm text-muted">هنوز جایزهٔ هفتگی پرداخت نشده است.</CardBody>
        </Card>
      ) : (
        weeks.map((w) => (
          <Card key={w.payout_date}>
            <CardHeader title={`پرداخت ${formatJalaliDay(w.payout_date, 'yyyy/MM/dd')}`} />
            <DataTable
              columns={[
                { key: 'rank', header: 'رتبه', cell: (r) => formatNumber(r.rank) },
                {
                  key: 'user',
                  header: 'بازیکن',
                  cell: (r) => (
                    <span className="inline-flex flex-wrap items-center gap-2">
                      <Link to={`/users/${r.user_id}`} className="hover:text-blue">{r.username || '—'}</Link>
                      {r.banned && <Badge tone="pink">مسدود</Badge>}
                    </span>
                  ),
                },
                { key: 'coins', header: 'سکه', cell: (r) => formatNumber(r.coins) },
                { key: 'at', header: 'زمان پرداخت', className: 'hidden sm:table-cell', cell: (r) => formatJalaliDateTime(r.awarded_at) },
              ]}
              rows={w.rewards}
              rowKey={(r) => r.user_id}
            />
          </Card>
        ))
      )}
    </div>
  )
}
