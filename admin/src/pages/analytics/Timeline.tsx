import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { Skeleton } from '@/components/ui/Skeleton'
import { eventLabel, fetchTimelinePage, screenLabel, useTimeline, type Timeline as TimelineData, type TimelineItem } from '@/lib/analytics'
import { messageOf } from '@/lib/errors'
import { formatJalaliDate, formatJalaliDateTime, formatNumber, toFa } from '@/lib/fa'

/** Compact «key: value» rendering of an event's props (small, PII-free by contract). */
function propsText(props: TimelineItem['props']): string {
  if (!props) return ''
  return Object.entries(props)
    .map(([k, v]) => `${k}: ${typeof v === 'number' ? toFa(v) : String(v)}`)
    .join(' · ')
}

function shortId(id: string): string {
  return toFa(id.slice(0, 8))
}

/**
 * "This player did X, then Y" — a user's (all their installs, including the
 * guest history before signup) or a single install's events, newest first.
 */
export function Timeline({ kind, id }: { kind: 'users' | 'installs'; id: string }) {
  const query = useTimeline(kind, id)
  const [older, setOlder] = useState<TimelineData[]>([])
  const [loadingMore, setLoadingMore] = useState(false)
  const [moreError, setMoreError] = useState<string | null>(null)

  if (query.isPending) return <Skeleton className="h-64 w-full" />
  if (query.isError) {
    return (
      <div role="alert" className="flex flex-col items-center gap-3 py-10 text-center">
        <p className="text-sm text-pink">{messageOf(query.error)}</p>
        <Button variant="secondary" size="sm" onClick={() => void query.refetch()}>
          تلاش دوباره
        </Button>
      </div>
    )
  }

  const pages = [query.data, ...older]
  const events = pages.flatMap((p) => p.events)
  const last = pages[pages.length - 1]
  const showInstall = query.data.installs.length > 1

  async function more() {
    if (!last.next_before) return
    setLoadingMore(true)
    setMoreError(null)
    try {
      const page = await fetchTimelinePage(kind, id, last.next_before)
      setOlder((o) => [...o, page])
    } catch (e) {
      setMoreError(messageOf(e))
    } finally {
      setLoadingMore(false)
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader title="دستگاه‌ها" />
        <CardBody>
          {query.data.installs.length === 0 ? (
            <p className="text-sm text-muted">برای این مورد هنوز رویدادی ثبت نشده است.</p>
          ) : (
            <ul className="space-y-2 text-sm">
              {query.data.installs.map((i) => (
                <li key={i.install_id} className="flex flex-wrap items-center gap-x-4 gap-y-1">
                  <Link to={`/analytics/installs/${i.install_id}`} className="tabular text-blue hover:underline" dir="ltr">
                    {i.install_id.slice(0, 8)}
                  </Link>
                  <span className="text-muted">
                    {i.platform || '—'} · {i.app_version || '—'}
                  </span>
                  <span className="text-muted">
                    از {formatJalaliDate(i.first_seen)} تا {formatJalaliDate(i.last_seen)}
                  </span>
                  {i.user_id && <Badge tone="green">وصل به حساب</Badge>}
                </li>
              ))}
            </ul>
          )}
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="رویدادها" actions={<span className="text-xs text-muted">{formatNumber(events.length)} رویداد، تازه‌ترین بالا</span>} />
        {events.length === 0 ? (
          <p className="px-5 py-10 text-center text-sm text-muted">رویدادی ثبت نشده است.</p>
        ) : (
          <ol className="divide-y divide-border">
            {events.map((e, i) => (
              <li key={`${e.ts}-${i}`} className="flex flex-wrap items-baseline gap-x-4 gap-y-1 px-5 py-2.5 text-sm">
                <time className="tabular w-36 shrink-0 text-xs text-muted">{formatJalaliDateTime(e.ts)}</time>
                <span className="font-medium text-text">{eventLabel(e.name)}</span>
                {e.screen && <Badge tone="neutral">{screenLabel(e.screen)}</Badge>}
                {e.props && <span className="tabular text-xs text-muted">{propsText(e.props)}</span>}
                {showInstall && (
                  <span className="tabular ms-auto text-xs text-muted" dir="ltr">
                    {shortId(e.install_id)}
                  </span>
                )}
              </li>
            ))}
          </ol>
        )}
        {last.next_before && (
          <div className="flex flex-col items-center gap-2 border-t border-border px-5 py-4">
            {moreError && <p role="alert" className="text-sm text-pink">{moreError}</p>}
            <Button variant="secondary" size="sm" onClick={() => void more()} loading={loadingMore}>
              رویدادهای قدیمی‌تر
            </Button>
          </div>
        )}
      </Card>
    </div>
  )
}
