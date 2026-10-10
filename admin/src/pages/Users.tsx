import { Crown, Search } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Avatar } from '@/components/ui/Avatar'
import { Badge } from '@/components/ui/Badge'
import { Card } from '@/components/ui/Card'
import { DataTable, type Column, type SortState } from '@/components/ui/DataTable'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { messageOf } from '@/lib/errors'
import { formatJalaliDate, formatNumber, toFa } from '@/lib/fa'
import {
  avatarUrl, USERS_PAGE_SIZE, useUsers,
  type UserFilter, type UserItem, type UserListParams, type UserSortKey,
} from '@/lib/users'

const FILTERS: { value: UserFilter; label: string }[] = [
  { value: 'all', label: 'همهٔ کاربران' },
  { value: 'premium', label: 'اشتراک ویژه' },
  { value: 'banned', label: 'مسدودشده' },
  { value: 'new', label: 'تازه‌وارد (۷ روز اخیر)' },
]
const SORTS: UserSortKey[] = ['created', 'coins', 'xp', 'matches', 'username']

/** Parses the URL into list params, falling back to the defaults for anything unknown. */
export function paramsFromUrl(sp: URLSearchParams): UserListParams {
  const filter = sp.get('filter') as UserFilter | null
  const sort = sp.get('sort') as UserSortKey | null
  const page = Number(sp.get('page'))
  return {
    q: sp.get('q') ?? '',
    filter: filter && FILTERS.some((f) => f.value === filter) ? filter : 'all',
    sort: sort && SORTS.includes(sort) ? sort : 'created',
    order: sp.get('order') === 'asc' ? 'asc' : 'desc',
    page: Number.isInteger(page) && page > 0 ? page : 1,
  }
}

export function UserStatus({ user }: { user: Pick<UserItem, 'banned' | 'premium'> }) {
  return (
    <span className="inline-flex flex-wrap gap-1.5">
      {user.banned && <Badge tone="pink">مسدود</Badge>}
      {user.premium && (
        <Badge tone="yellow" className="gap-1">
          <Crown className="size-3" aria-hidden />
          ویژه
        </Badge>
      )}
      {!user.banned && !user.premium && <Badge tone="green">فعال</Badge>}
    </span>
  )
}

export function Users() {
  const [sp, setSp] = useSearchParams()
  const params = paramsFromUrl(sp)
  const [text, setText] = useState(params.q)

  // Follow external changes of ?q= (the topbar search navigates here).
  useEffect(() => setText(params.q), [params.q])

  // Debounce typing into the URL; a new search always returns to page 1.
  useEffect(() => {
    if (text.trim() === params.q) return
    const t = setTimeout(() => update({ q: text.trim(), page: 1 }), 350)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text])

  function update(patch: Partial<UserListParams>) {
    const next = { ...params, ...patch }
    const qs = new URLSearchParams()
    if (next.q) qs.set('q', next.q)
    if (next.filter !== 'all') qs.set('filter', next.filter)
    if (next.sort !== 'created') qs.set('sort', next.sort)
    if (next.order !== 'desc') qs.set('order', next.order)
    if (next.page > 1) qs.set('page', String(next.page))
    setSp(qs, { replace: true })
  }

  const query = useUsers(params)
  const sort: SortState = { key: params.sort, dir: params.order }

  const columns: Column<UserItem>[] = [
    {
      key: 'username',
      header: 'کاربر',
      sortable: true,
      cell: (u) => (
        <Link to={`/users/${u.id}`} className="flex items-center gap-3 hover:text-blue">
          <Avatar name={u.username} src={avatarUrl(u)} className="size-9" />
          <span className="font-medium">{u.username}</span>
        </Link>
      ),
    },
    {
      key: 'phone',
      header: 'موبایل',
      className: 'hidden md:table-cell',
      cell: (u) => (
        <span dir="ltr" className="inline-block text-muted" title={u.phone_masked ? 'شمارهٔ کامل فقط برای مالک نمایش داده می‌شود' : undefined}>
          {toFa(u.phone)}
        </span>
      ),
    },
    { key: 'coins', header: 'سکه', sortable: true, cell: (u) => formatNumber(u.coins) },
    { key: 'xp', header: 'سطح', sortable: true, className: 'hidden sm:table-cell', cell: (u) => formatNumber(u.level) },
    { key: 'matches', header: 'مسابقه', sortable: true, className: 'hidden lg:table-cell', cell: (u) => formatNumber(u.total_matches) },
    { key: 'status', header: 'وضعیت', cell: (u) => <UserStatus user={u} /> },
    { key: 'created', header: 'عضویت', sortable: true, className: 'hidden md:table-cell', cell: (u) => formatJalaliDate(u.created_at) },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">کاربران</h1>
        <p className="text-xs text-muted">
          جستجو بر اساس نام کاربری، کد دعوت یا شناسه — شمارهٔ موبایل فقط برای مالک قابل جستجو است.
        </p>
      </div>

      <Card>
        <div className="flex flex-wrap items-end gap-3 border-b border-border p-4">
          <div className="min-w-56 flex-1">
            <Input
              aria-label="جستجوی کاربر"
              placeholder="جستجو…"
              value={text}
              onChange={(e) => setText(e.target.value)}
              startAdornment={<Search className="size-4" aria-hidden />}
              autoComplete="off"
            />
          </div>
          <Select
            label="فیلتر"
            value={params.filter}
            onValueChange={(v) => update({ filter: v as UserFilter, page: 1 })}
            options={FILTERS}
          />
        </div>
        <DataTable
          columns={columns}
          rows={query.data?.items}
          rowKey={(u) => u.id}
          loading={query.isPending}
          error={query.isError ? messageOf(query.error) : null}
          onRetry={() => void query.refetch()}
          emptyText={params.q || params.filter !== 'all' ? 'کاربری با این مشخصات پیدا نشد.' : 'هنوز کاربری ثبت‌نام نکرده است.'}
          page={params.page}
          pageSize={USERS_PAGE_SIZE}
          total={query.data?.total}
          onPageChange={(page) => update({ page })}
          sort={sort}
          onSortChange={(s) => update({ sort: s.key as UserSortKey, order: s.dir, page: 1 })}
        />
      </Card>
    </div>
  )
}
