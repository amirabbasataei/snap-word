import { ArrowRight, Ban, Coins, Crown, ImageOff, Pencil, ShieldCheck, ShieldOff, Sparkles } from 'lucide-react'
import { useState, type ReactNode } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '@/auth/AuthContext'
import { Avatar } from '@/components/ui/Avatar'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { Skeleton } from '@/components/ui/Skeleton'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/Tabs'
import { roleAtLeast } from '@/layout/nav'
import { ApiError, messageOf } from '@/lib/errors'
import { formatJalaliDate, formatJalaliDateTime, formatJalaliDay, formatNumber, toFa } from '@/lib/fa'
import { avatarUrl, useUser, type UserDetail as Detail } from '@/lib/users'
import { UserStatus } from './Users'
import { MATCH_KIND_LABEL, MATCH_STATUS_LABEL, REWARD_KIND_LABEL } from './users/labels'
import { UserActions, type ActionKind } from './users/UserActions'
import { NotFound } from './NotFound'

export function UserDetail() {
  const { id = '' } = useParams()
  const query = useUser(id)

  if (query.isPending) return <DetailSkeleton />
  if (query.isError) {
    if (query.error instanceof ApiError && query.error.status === 404) return <NotFound />
    return (
      <div className="space-y-4">
        <BackLink />
        <Card>
          <div role="alert" className="flex flex-col items-center gap-3 px-4 py-12 text-center">
            <p className="text-sm text-pink">{messageOf(query.error)}</p>
            <Button variant="secondary" size="sm" onClick={() => void query.refetch()}>
              تلاش دوباره
            </Button>
          </div>
        </Card>
      </div>
    )
  }
  return <Loaded user={query.data} />
}

function BackLink() {
  return (
    <Link to="/users" className="inline-flex items-center gap-1.5 text-sm text-muted hover:text-text">
      <ArrowRight className="size-4" aria-hidden />
      کاربران
    </Link>
  )
}

function DetailSkeleton() {
  return (
    <div className="space-y-4" aria-busy>
      <BackLink />
      <Skeleton className="h-28 w-full" />
      <Skeleton className="h-64 w-full" />
    </div>
  )
}

function Loaded({ user }: { user: Detail }) {
  const { admin } = useAuth()
  const canAct = admin ? roleAtLeast(admin.role, 'operator') : false
  const [action, setAction] = useState<ActionKind | null>(null)

  return (
    <div className="space-y-6">
      <BackLink />

      <Card>
        <CardBody className="flex flex-wrap items-start justify-between gap-4">
          <div className="flex min-w-0 items-center gap-4">
            <Avatar name={user.username} src={avatarUrl(user)} className="size-16 text-xl" />
            <div className="min-w-0 space-y-1.5">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="truncate text-xl font-semibold text-text">{user.username}</h1>
                <UserStatus user={user} />
              </div>
              <p className="text-sm text-muted" title={user.phone_masked ? 'شمارهٔ کامل فقط برای مالک نمایش داده می‌شود' : undefined}>
                <span dir="ltr" className="inline-block">{toFa(user.phone)}</span>
              </p>
              <p className="font-mono text-xs text-muted">
                <span dir="ltr" className="inline-block">{user.id}</span>
              </p>
            </div>
          </div>

          {canAct ? (
            <div className="flex flex-wrap gap-2" role="group" aria-label="اقدامات">
              <ActionButton icon={<Coins className="size-4" aria-hidden />} onClick={() => setAction('coins')}>سکه</ActionButton>
              <ActionButton icon={<Crown className="size-4" aria-hidden />} onClick={() => setAction('premium')}>اشتراک ویژه</ActionButton>
              {user.premium && (
                <ActionButton icon={<Sparkles className="size-4" aria-hidden />} onClick={() => setAction('premium_revoke')}>لغو اشتراک</ActionButton>
              )}
              <ActionButton icon={<Pencil className="size-4" aria-hidden />} onClick={() => setAction('rename')}>تغییر نام</ActionButton>
              {user.avatar_id && (
                <ActionButton icon={<ImageOff className="size-4" aria-hidden />} onClick={() => setAction('avatar_clear')}>حذف آواتار</ActionButton>
              )}
              {user.banned ? (
                <ActionButton icon={<ShieldCheck className="size-4" aria-hidden />} onClick={() => setAction('unban')}>رفع مسدودی</ActionButton>
              ) : (
                <Button variant="danger" size="sm" onClick={() => setAction('ban')}>
                  <Ban className="size-4" aria-hidden />
                  مسدودسازی
                </Button>
              )}
            </div>
          ) : (
            <p className="flex items-center gap-1.5 text-xs text-muted">
              <ShieldOff className="size-4" aria-hidden />
              نقش شما فقط اجازهٔ مشاهده می‌دهد.
            </p>
          )}
        </CardBody>
      </Card>

      {user.banned && (
        <div role="status" className="rounded-card border border-pink px-5 py-3 text-sm">
          <p className="font-medium text-pink">این حساب مسدود است{user.banned_at ? ` (از ${formatJalaliDateTime(user.banned_at)})` : ''}.</p>
          {user.ban_reason && <p className="mt-1 text-muted">دلیل: {user.ban_reason}</p>}
        </div>
      )}

      <Tabs defaultValue="summary">
        <TabsList className="overflow-x-auto">
          <TabsTrigger value="summary">خلاصه</TabsTrigger>
          <TabsTrigger value="matches">مسابقه‌ها</TabsTrigger>
          <TabsTrigger value="rewards">پاداش‌ها</TabsTrigger>
          <TabsTrigger value="referrals">معرفی‌ها</TabsTrigger>
        </TabsList>
        <TabsContent value="summary" className="pt-5"><SummaryTab user={user} /></TabsContent>
        <TabsContent value="matches" className="pt-5"><MatchesTab user={user} /></TabsContent>
        <TabsContent value="rewards" className="pt-5"><RewardsTab user={user} /></TabsContent>
        <TabsContent value="referrals" className="pt-5"><ReferralsTab user={user} /></TabsContent>
      </Tabs>

      {canAct && <UserActions user={user} action={action} onClose={() => setAction(null)} />}
    </div>
  )
}

function ActionButton({ icon, onClick, children }: { icon: ReactNode; onClick: () => void; children: ReactNode }) {
  return (
    <Button variant="secondary" size="sm" onClick={onClick}>
      {icon}
      {children}
    </Button>
  )
}

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-4 border-b border-border py-2.5 last:border-0">
      <dt className="shrink-0 text-sm text-muted">{label}</dt>
      <dd className="tabular min-w-0 break-words text-end text-sm text-text">{children}</dd>
    </div>
  )
}

function SummaryTab({ user }: { user: Detail }) {
  const s = user.stats
  const pct = user.xp_for_next > 0 ? Math.min(100, Math.round((user.xp_in_level / user.xp_for_next) * 100)) : 0
  return (
    <div className="grid gap-4 lg:grid-cols-3">
      <Card>
        <CardHeader title="حساب" />
        <CardBody>
          <dl>
            <Fact label="عضویت">{formatJalaliDateTime(user.joined_at ?? user.created_at)}</Fact>
            <Fact label="کد دعوت"><span dir="ltr" className="font-mono">{user.referral_code || '—'}</span></Fact>
            <Fact label="اشتراک ویژه">
              {user.premium ? `تا ${formatJalaliDateTime(user.premium_until)}` : user.premium_until ? `پایان‌یافته (${formatJalaliDate(user.premium_until)})` : 'ندارد'}
            </Fact>
            <Fact label="آواتار"><span dir="ltr">{user.avatar_id || '—'}</span></Fact>
            <Fact label="دوستان">{formatNumber(user.friends_count)}</Fact>
            <Fact label="دستگاه‌های اعلان">{formatNumber(user.device_tokens)}</Fact>
          </dl>
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="اقتصاد" />
        <CardBody className="space-y-4">
          <div>
            <p className="text-xs text-muted">موجودی سکه</p>
            <p className="tabular text-3xl font-semibold text-text">{formatNumber(user.coins)}</p>
          </div>
          <div>
            <div className="mb-1.5 flex items-baseline justify-between text-xs text-muted">
              <span>سطح {formatNumber(user.level)}</span>
              <span className="tabular">{formatNumber(user.xp_in_level)} از {formatNumber(user.xp_for_next)} امتیاز</span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-active" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100} aria-label="پیشرفت سطح">
              <div className="h-full rounded-full bg-blue" style={{ width: `${pct}%` }} />
            </div>
            <p className="tabular mt-1.5 text-xs text-muted">مجموع امتیاز تجربه: {formatNumber(user.xp)}</p>
          </div>
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="بازی" />
        <CardBody>
          <dl>
            <Fact label="مسابقه‌ها">{formatNumber(s.total_matches)}</Fact>
            <Fact label="برد">{formatNumber(s.wins)}</Fact>
            <Fact label="بهترین رشتهٔ موفق">{formatNumber(s.best_match_streak)}</Fact>
            <Fact label="رشتهٔ روزانه">{formatNumber(s.daily_streak)} (رکورد {formatNumber(s.longest_daily_streak)})</Fact>
            <Fact label="طولانی‌ترین کلمه">{s.longest_word || '—'}</Fact>
            <Fact label="آخرین بازی">{s.last_played_date ? formatJalaliDay(s.last_played_date.slice(0, 10), 'yyyy/MM/dd') : '—'}</Fact>
            <Fact label="مجموع امتیاز جدول">{formatNumber(s.total_score)}</Fact>
          </dl>
        </CardBody>
      </Card>
    </div>
  )
}

function MatchesTab({ user }: { user: Detail }) {
  const matchCols: Column<Detail['matches'][number]>[] = [
    { key: 'kind', header: 'نوع', cell: (m) => MATCH_KIND_LABEL[m.kind] ?? m.kind },
    { key: 'status', header: 'وضعیت', cell: (m) => <Badge tone={m.status === 'finished' ? 'green' : 'neutral'}>{MATCH_STATUS_LABEL[m.status] ?? m.status}</Badge> },
    { key: 'score', header: 'امتیاز', cell: (m) => formatNumber(m.score) },
    { key: 'won', header: 'نتیجه', cell: (m) => (m.won ? <Badge tone="yellow">برنده</Badge> : <span className="text-muted">—</span>) },
    { key: 'at', header: 'زمان', cell: (m) => formatJalaliDateTime(m.at) },
  ]
  const dailyCols: Column<Detail['daily_attempts'][number]>[] = [
    { key: 'date', header: 'روز', cell: (a) => formatJalaliDay(a.date, 'yyyy/MM/dd') },
    { key: 'attempt', header: 'تلاش', cell: (a) => (a.attempt === 1 ? 'اول (رایگان)' : `${formatNumber(a.attempt)} (دوباره)`) },
    { key: 'score', header: 'امتیاز', cell: (a) => formatNumber(a.score) },
    { key: 'chain', header: 'طول زنجیر', cell: (a) => formatNumber(a.chain_length) },
    { key: 'at', header: 'ثبت', cell: (a) => formatJalaliDateTime(a.completed_at) },
  ]
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader title="آخرین مسابقه‌ها" />
        <DataTable columns={matchCols} rows={user.matches} rowKey={(m) => m.id} emptyText="این کاربر هنوز مسابقه‌ای ثبت نکرده است." />
      </Card>
      <Card>
        <CardHeader title="چالش روزانه" />
        <DataTable columns={dailyCols} rows={user.daily_attempts} rowKey={(a) => `${a.date}-${a.attempt}`} emptyText="در چالش روزانه شرکت نکرده است." />
      </Card>
    </div>
  )
}

function RewardsTab({ user }: { user: Detail }) {
  const cols: Column<Detail['rewards'][number]>[] = [
    { key: 'kind', header: 'نوع', cell: (r) => REWARD_KIND_LABEL[r.kind] ?? r.kind },
    { key: 'detail', header: 'جزئیات', className: 'hidden sm:table-cell', cell: (r) => (r.detail ? toFa(r.detail) : '—') },
    { key: 'coins', header: 'سکه', cell: (r) => formatNumber(r.coins) },
    {
      key: 'state',
      header: 'وضعیت',
      cell: (r) => (r.claimed ? <Badge tone="green">دریافت‌شده · {formatJalaliDate(r.claimed_at)}</Badge> : <Badge tone="orange">دریافت‌نشده</Badge>),
    },
    { key: 'at', header: 'ایجاد', cell: (r) => formatJalaliDateTime(r.created_at) },
  ]
  return (
    <Card>
      <CardHeader title="صندوق جایزه‌ها" />
      <DataTable columns={cols} rows={user.rewards} rowKey={(r) => r.id} emptyText="جایزه‌ای ثبت نشده است." />
      {user.rewards.length >= 50 && <p className="border-t border-border px-4 py-3 text-xs text-muted">۵۰ مورد آخر نمایش داده می‌شود.</p>}
    </Card>
  )
}

function ReferralsTab({ user }: { user: Detail }) {
  const cols: Column<Detail['referred'][number]>[] = [
    { key: 'name', header: 'کاربر', cell: (r) => <Link to={`/users/${r.id}`} className="hover:text-blue">{r.username}</Link> },
    { key: 'at', header: 'عضویت', cell: (r) => formatJalaliDateTime(r.created_at) },
  ]
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader title="معرف" />
        <CardBody>
          {user.referrer ? (
            <Link to={`/users/${user.referrer.id}`} className="text-sm text-blue hover:underline">{user.referrer.username}</Link>
          ) : (
            <p className="text-sm text-muted">با کد دعوت کسی وارد نشده است.</p>
          )}
        </CardBody>
      </Card>
      <Card>
        <CardHeader title={`دعوت‌شدگان (${formatNumber(user.referred_count)})`} />
        <DataTable columns={cols} rows={user.referred} rowKey={(r) => r.id} emptyText="کسی با کد دعوت این کاربر وارد نشده است." />
        {user.referred_count > user.referred.length && (
          <p className="border-t border-border px-4 py-3 text-xs text-muted">{formatNumber(user.referred.length)} مورد آخر نمایش داده می‌شود.</p>
        )}
      </Card>
    </div>
  )
}
