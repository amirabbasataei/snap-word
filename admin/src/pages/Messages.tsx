import { Search } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Badge } from '@/components/ui/Badge'
import { Card } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { messageOf } from '@/lib/errors'
import { formatJalaliDateTime } from '@/lib/fa'
import type { MatchRange } from '@/lib/matches'
import {
  MESSAGES_PAGE_SIZE, useMessages,
  type MessageKindFilter, type MessageListParams, type PlayerMessage,
} from '@/lib/messages'

const KINDS: { value: MessageKindFilter; label: string }[] = [
  { value: 'all', label: 'همهٔ پیام‌ها' },
  { value: 'custom', label: 'متن آزاد' },
  { value: 'preset', label: 'تیکهٔ آماده' },
]
const RANGES: { value: MatchRange; label: string }[] = [
  { value: 'all', label: 'همهٔ زمان‌ها' },
  { value: 'today', label: 'امروز' },
  { value: '7d', label: '۷ روز اخیر' },
  { value: '30d', label: '۳۰ روز اخیر' },
]

/** Parses the URL into list params, falling back to the defaults for anything unknown. */
export function paramsFromUrl(sp: URLSearchParams): MessageListParams {
  const kind = sp.get('kind') as MessageKindFilter | null
  const range = sp.get('range') as MatchRange | null
  const page = Number(sp.get('page'))
  return {
    q: sp.get('q') ?? '',
    kind: kind && KINDS.some((k) => k.value === kind) ? kind : 'all',
    range: range && RANGES.some((r) => r.value === range) ? range : 'all',
    page: Number.isInteger(page) && page > 0 ? page : 1,
  }
}

export function Messages() {
  const [sp, setSp] = useSearchParams()
  const params = paramsFromUrl(sp)
  const [text, setText] = useState(params.q)
  useEffect(() => setText(params.q), [params.q])

  // Debounce typing into the URL; a new search always returns to page 1.
  useEffect(() => {
    if (text.trim() === params.q) return
    const t = setTimeout(() => update({ q: text.trim(), page: 1 }), 350)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text])

  function update(patch: Partial<MessageListParams>) {
    const next = { ...params, ...patch }
    const qs = new URLSearchParams()
    if (next.q) qs.set('q', next.q)
    if (next.kind !== 'all') qs.set('kind', next.kind)
    if (next.range !== 'all') qs.set('range', next.range)
    if (next.page > 1) qs.set('page', String(next.page))
    setSp(qs, { replace: true })
  }

  const query = useMessages(params)
  const filtered = params.q !== '' || params.kind !== 'all' || params.range !== 'all'

  const columns: Column<PlayerMessage>[] = [
    { key: 'at', header: 'زمان', cell: (m) => <span className="tabular whitespace-nowrap">{formatJalaliDateTime(m.at)}</span> },
    {
      key: 'sender',
      header: 'فرستنده',
      cell: (m) => (
        <span className="inline-flex flex-wrap items-center gap-2">
          <Link to={`/users/${m.sender_id}`} className="font-medium hover:text-blue">{m.sender_name || 'بدون نام'}</Link>
          {m.sender_banned && <Badge tone="pink">مسدود</Badge>}
        </span>
      ),
    },
    {
      key: 'text',
      header: 'پیام',
      cell: (m) => (
        <div>
          <span className="block whitespace-pre-wrap break-words">{m.text}</span>
          <span className="mt-1 block md:hidden"><KindBadge kind={m.kind} /></span>
        </div>
      ),
    },
    { key: 'kind', header: 'نوع', className: 'hidden md:table-cell', cell: (m) => <KindBadge kind={m.kind} /> },
    {
      key: 'to',
      header: 'حریف',
      className: 'hidden sm:table-cell',
      cell: (m) =>
        m.opponent_id ? (
          <Link to={`/users/${m.opponent_id}`} className="hover:text-blue">{m.opponent_name || 'بدون نام'}</Link>
        ) : (
          <span className="text-muted">—</span>
        ),
    },
    {
      key: 'match',
      header: 'مسابقه',
      className: 'hidden lg:table-cell',
      cell: (m) =>
        m.match_id ? (
          <Link to={`/matches/${m.match_id}`} className="text-xs hover:text-blue" aria-label={`مسابقهٔ پیام ${formatJalaliDateTime(m.at)}`}>
            مشاهده
          </Link>
        ) : (
          <span className="text-muted">—</span>
        ),
    },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">پیام‌های بازیکنان</h1>
        <p className="text-xs text-muted">
          هر پیامی که بازیکنی در یک مسابقهٔ رودررو فرستاده، چه تیکهٔ آماده و چه متن آزادِ اشتراک ویژه. پیام‌هایی که سرور رد کرده (بدون اشتراک یا پشت‌سرهم) ذخیره نمی‌شوند.
        </p>
      </div>

      <Card>
        <div className="flex flex-wrap items-end gap-3 border-b border-border p-4">
          <div className="min-w-56 flex-1">
            <Input
              aria-label="جستجوی پیام"
              placeholder="نام فرستنده، شناسهٔ کاربر یا مسابقه، یا بخشی از متن…"
              value={text}
              onChange={(e) => setText(e.target.value)}
              startAdornment={<Search className="size-4" aria-hidden />}
              autoComplete="off"
            />
          </div>
          <Select label="نوع" value={params.kind} onValueChange={(v) => update({ kind: v as MessageKindFilter, page: 1 })} options={KINDS} />
          <Select label="بازه" value={params.range} onValueChange={(v) => update({ range: v as MatchRange, page: 1 })} options={RANGES} />
        </div>
        <DataTable
          columns={columns}
          rows={query.data?.items}
          rowKey={(m) => m.id}
          loading={query.isPending}
          error={query.isError ? messageOf(query.error) : null}
          onRetry={() => void query.refetch()}
          emptyText={filtered ? 'پیامی با این مشخصات پیدا نشد.' : 'هنوز پیامی فرستاده نشده است.'}
          page={params.page}
          pageSize={MESSAGES_PAGE_SIZE}
          total={query.data?.total}
          onPageChange={(page) => update({ page })}
        />
      </Card>
    </div>
  )
}

function KindBadge({ kind }: { kind: PlayerMessage['kind'] }) {
  return kind === 'custom' ? <Badge tone="blue">متن آزاد</Badge> : <Badge tone="neutral">تیکهٔ آماده</Badge>
}
