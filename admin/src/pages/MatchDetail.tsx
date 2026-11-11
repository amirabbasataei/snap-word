import { ArrowRight } from 'lucide-react'
import { Link, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { Skeleton } from '@/components/ui/Skeleton'
import { ApiError, messageOf } from '@/lib/errors'
import { formatJalaliDateTime, formatNumber } from '@/lib/fa'
import { useMatch, type MatchDetail as Detail } from '@/lib/matches'
import { formatDuration, MatchStatusBadge, PlayerLine } from './matches/parts'
import { NotFound } from './NotFound'
import { MATCH_KIND_LABEL, MATCH_STATUS_LABEL } from './users/labels'

export function MatchDetail() {
  const { id = '' } = useParams()
  const query = useMatch(id)

  if (query.isPending) {
    return (
      <div className="space-y-4" aria-busy>
        <BackLink />
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-48 w-full" />
      </div>
    )
  }
  if (query.isError) {
    if (query.error instanceof ApiError && query.error.status === 404) return <NotFound />
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
  return <Loaded match={query.data} />
}

function BackLink() {
  return (
    <Link to="/matches" className="inline-flex items-center gap-1.5 text-sm text-muted hover:text-text">
      <ArrowRight className="size-4" aria-hidden />
      مسابقه‌ها
    </Link>
  )
}

function Fact({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-4 border-b border-border py-2.5 last:border-0">
      <dt className="shrink-0 text-sm text-muted">{label}</dt>
      <dd className="tabular min-w-0 break-words text-end text-sm text-text">{children}</dd>
    </div>
  )
}

function Loaded({ match: m }: { match: Detail }) {
  return (
    <div className="space-y-6">
      <BackLink />
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="text-xl font-semibold text-text">{MATCH_KIND_LABEL[m.kind] ?? m.kind}</h1>
        <MatchStatusBadge status={m.status} label={MATCH_STATUS_LABEL[m.status] ?? m.status} />
        {m.kind === 'versus' && (
          <Link to={`/messages?q=${m.id}`} className="text-sm text-muted hover:text-blue">پیام‌های این مسابقه</Link>
        )}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader title="بازیکنان" />
          <CardBody>
            <ul className="space-y-3">
              {m.players.map((p) => (
                <li key={p.user_id}><PlayerLine p={p} winner={m.winner_id !== '' && p.user_id === m.winner_id} /></li>
              ))}
            </ul>
            {m.status === 'finished' && m.winner_id === '' && m.players.length > 1 && (
              <p className="mt-3 text-sm text-muted">برنده‌ای ثبت نشده (مساوی).</p>
            )}
          </CardBody>
        </Card>
        <Card>
          <CardHeader title="مشخصات" />
          <CardBody>
            <dl>
              <Fact label="شروع">{formatJalaliDateTime(m.started_at ?? m.at)}</Fact>
              <Fact label="پایان">{formatJalaliDateTime(m.ended_at)}</Fact>
              <Fact label="مدت">{formatDuration(m.duration_sec)}</Fact>
              <Fact label="تعداد کلمه">{formatNumber(m.chain_length)}</Fact>
              <Fact label="شناسه"><span dir="ltr" className="inline-block text-xs text-muted">{m.id}</span></Fact>
            </dl>
          </CardBody>
        </Card>
      </div>

      <Card>
        <CardHeader title="زنجیر کلمه‌ها" />
        <CardBody>
          {m.word_chain.length === 0 ? (
            <p className="text-sm text-muted">زنجیری برای این مسابقه ذخیره نشده است.</p>
          ) : (
            <ol className="flex flex-wrap gap-2" aria-label="زنجیر کلمه‌ها">
              {m.word_chain.map((w, i) => (
                <li key={`${i}-${w}`} className="inline-flex items-center gap-1.5 rounded-lg border border-border bg-raised px-2.5 py-1 text-sm text-text">
                  <span className="tabular text-xs text-muted">{formatNumber(i + 1)}</span>
                  {w}
                </li>
              ))}
            </ol>
          )}
        </CardBody>
      </Card>
    </div>
  )
}
