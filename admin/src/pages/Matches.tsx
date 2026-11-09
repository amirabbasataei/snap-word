import { Search } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Card } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { messageOf } from '@/lib/errors'
import { formatJalaliDateTime, formatNumber } from '@/lib/fa'
import {
  MATCHES_PAGE_SIZE, useMatches,
  type MatchItem, type MatchListParams, type MatchRange, type MatchStatusFilter,
} from '@/lib/matches'
import type { MatchKind } from '@/lib/users'
import { formatDuration, MatchStatusBadge, PlayerLine } from './matches/parts'
import { MATCH_KIND_LABEL, MATCH_STATUS_LABEL } from './users/labels'

const KINDS: { value: MatchKind | 'all'; label: string }[] = [
  { value: 'all', label: 'همهٔ نوع‌ها' },
  ...(Object.entries(MATCH_KIND_LABEL) as [MatchKind, string][]).map(([value, label]) => ({ value, label })),
]
const STATUSES: { value: MatchStatusFilter; label: string }[] = [
  { value: 'all', label: 'همهٔ وضعیت‌ها' },
  { value: 'finished', label: MATCH_STATUS_LABEL.finished },
  { value: 'active', label: MATCH_STATUS_LABEL.active },
  { value: 'abandoned', label: MATCH_STATUS_LABEL.abandoned },
  { value: 'pending', label: MATCH_STATUS_LABEL.pending },
]
const RANGES: { value: MatchRange; label: string }[] = [
  { value: 'all', label: 'همهٔ زمان‌ها' },
  { value: 'today', label: 'امروز' },
  { value: '7d', label: '۷ روز اخیر' },
  { value: '30d', label: '۳۰ روز اخیر' },
]

/** Parses the URL into list params, falling back to the defaults for anything unknown. */
export function paramsFromUrl(sp: URLSearchParams): MatchListParams {
  const kind = sp.get('kind') as MatchKind | 'all' | null
  const status = sp.get('status') as MatchStatusFilter | null
  const range = sp.get('range') as MatchRange | null
  const page = Number(sp.get('page'))
  return {
    q: sp.get('q') ?? '',
    kind: kind && KINDS.some((k) => k.value === kind) ? kind : 'all',
    status: status && STATUSES.some((s) => s.value === status) ? status : 'all',
    range: range && RANGES.some((r) => r.value === range) ? range : 'all',
    page: Number.isInteger(page) && page > 0 ? page : 1,
  }
}

export function Matches() {
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

  function update(patch: Partial<MatchListParams>) {
    const next = { ...params, ...patch }
    const qs = new URLSearchParams()
    if (next.q) qs.set('q', next.q)
    if (next.kind !== 'all') qs.set('kind', next.kind)
    if (next.status !== 'all') qs.set('status', next.status)
    if (next.range !== 'all') qs.set('range', next.range)
    if (next.page > 1) qs.set('page', String(next.page))
    setSp(qs, { replace: true })
  }

  const query = useMatches(params)
  const filtered = params.q !== '' || params.kind !== 'all' || params.status !== 'all' || params.range !== 'all'

  const columns: Column<MatchItem>[] = [
    {
      key: 'at',
      header: 'زمان',
      cell: (m) => (
        <Link to={`/matches/${m.id}`} className="tabular block hover:text-blue" aria-label={`جزئیات مسابقه ${formatJalaliDateTime(m.at)}`}>
          {formatJalaliDateTime(m.at)}
        </Link>
      ),
    },
    {
      key: 'kind',
      header: 'نوع',
      cell: (m) => (
        <div>
          <span className="block">{MATCH_KIND_LABEL[m.kind] ?? m.kind}</span>
          <span className="mt-1 block sm:hidden"><MatchStatusBadge status={m.status} label={MATCH_STATUS_LABEL[m.status] ?? m.status} /></span>
        </div>
      ),
    },
    {
      key: 'players',
      header: 'بازیکنان',
      cell: (m) => (
        <ul className="space-y-1">
          {m.players.map((p) => (
            <li key={p.user_id}><PlayerLine p={p} winner={p.user_id === m.winner_id && m.winner_id !== ''} /></li>
          ))}
        </ul>
      ),
    },
    { key: 'status', header: 'وضعیت', className: 'hidden sm:table-cell', cell: (m) => <MatchStatusBadge status={m.status} label={MATCH_STATUS_LABEL[m.status] ?? m.status} /> },
    { key: 'chain', header: 'کلمه', className: 'hidden md:table-cell', cell: (m) => (m.chain_length > 0 ? formatNumber(m.chain_length) : '—') },
    { key: 'duration', header: 'مدت', className: 'hidden lg:table-cell', cell: (m) => formatDuration(m.duration_sec) },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">مسابقه‌ها</h1>
        <p className="text-xs text-muted">
          مسابقه‌های ثبت‌شده روی سرور: رودررو، هوش مصنوعی آنلاین، چالش روزانه و بازی‌های تک‌نفره‌ای که بازیکنان آپلود کرده‌اند. تفاوت تک‌نفره و هوش مصنوعیِ روی دستگاه از روی سرور مشخص نیست.
        </p>
      </div>

      <Card>
        <div className="flex flex-wrap items-end gap-3 border-b border-border p-4">
          <div className="min-w-56 flex-1">
            <Input
              aria-label="جستجوی مسابقه"
              placeholder="نام بازیکن، شناسهٔ کاربر یا مسابقه…"
              value={text}
              onChange={(e) => setText(e.target.value)}
              startAdornment={<Search className="size-4" aria-hidden />}
              autoComplete="off"
            />
          </div>
          <Select label="نوع" value={params.kind} onValueChange={(v) => update({ kind: v as MatchKind | 'all', page: 1 })} options={KINDS} />
          <Select label="وضعیت" value={params.status} onValueChange={(v) => update({ status: v as MatchStatusFilter, page: 1 })} options={STATUSES} />
          <Select label="بازه" value={params.range} onValueChange={(v) => update({ range: v as MatchRange, page: 1 })} options={RANGES} />
        </div>
        <DataTable
          columns={columns}
          rows={query.data?.items}
          rowKey={(m) => m.id}
          loading={query.isPending}
          error={query.isError ? messageOf(query.error) : null}
          onRetry={() => void query.refetch()}
          emptyText={filtered ? 'مسابقه‌ای با این مشخصات پیدا نشد.' : 'هنوز مسابقه‌ای ثبت نشده است.'}
          page={params.page}
          pageSize={MATCHES_PAGE_SIZE}
          total={query.data?.total}
          onPageChange={(page) => update({ page })}
        />
      </Card>
    </div>
  )
}
