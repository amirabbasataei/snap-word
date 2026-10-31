import { useState } from 'react'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { Dialog } from '@/components/ui/Dialog'
import { Skeleton } from '@/components/ui/Skeleton'
import { messageOf } from '@/lib/errors'
import { formatJalaliDateTime, formatNumber } from '@/lib/fa'
import {
  describeAudience, HISTORY_PAGE_SIZE, ROUTE_LABEL, useCampaign, useCampaigns, type Campaign,
} from '@/lib/notifications'
import { ChannelBadges, PushStatusBadge, pushResultText } from './parts'

export function History() {
  const [page, setPage] = useState(1)
  const [open, setOpen] = useState<string | null>(null)
  const query = useCampaigns(page)

  const columns: Column<Campaign>[] = [
    { key: 'at', header: 'زمان', cell: (c) => formatJalaliDateTime(c.created_at) },
    {
      key: 'title',
      header: 'پیام',
      className: 'max-w-72',
      cell: (c) => (
        <button type="button" onClick={() => setOpen(c.id)} className="block max-w-72 cursor-pointer truncate text-start text-blue hover:underline">
          {c.title}
        </button>
      ),
    },
    { key: 'audience', header: 'مخاطبان', cell: (c) => describeAudience(c.audience) },
    { key: 'channels', header: 'کانال', cell: (c) => <ChannelBadges c={c} /> },
    { key: 'recipients', header: 'حساب‌ها', cell: (c) => formatNumber(c.recipients) },
    { key: 'push', header: 'اعلان فوری', cell: (c) => <span className="inline-flex items-center gap-2"><PushStatusBadge c={c} />{c.push && c.push_status !== 'sending' && <span className="text-xs text-muted">{pushResultText(c)}</span>}</span> },
    { key: 'inapp', header: 'خوانده‌شده', cell: (c) => (c.inapp ? `${formatNumber(c.inapp_read)} از ${formatNumber(c.inapp_delivered)}` : '—') },
    { key: 'by', header: 'فرستنده', cell: (c) => c.created_by },
  ]

  return (
    <>
      <Card>
        <DataTable
          columns={columns}
          rows={query.data?.items}
          rowKey={(c) => c.id}
          error={query.isError && !query.data ? messageOf(query.error) : null}
          onRetry={() => void query.refetch()}
          emptyText="هنوز اعلانی ارسال نشده است."
          page={page}
          pageSize={HISTORY_PAGE_SIZE}
          total={query.data?.total}
          onPageChange={setPage}
        />
      </Card>
      {open && <Detail id={open} onClose={() => setOpen(null)} />}
    </>
  )
}

function Detail({ id, onClose }: { id: string; onClose: () => void }) {
  const query = useCampaign(id)
  const c = query.data
  return (
    <Dialog
      open
      onOpenChange={(o) => !o && onClose()}
      title={c?.title ?? 'جزئیات اعلان'}
      footer={<Button variant="secondary" onClick={onClose}>بستن</Button>}
    >
      {query.isPending ? (
        <Skeleton className="h-32 w-full" />
      ) : query.isError || !c ? (
        <p role="alert" className="text-sm text-pink">{messageOf(query.error)}</p>
      ) : (
        <div className="space-y-4 text-sm">
          <p className="whitespace-pre-line text-text">{c.body}</p>
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2">
            <dt className="text-muted">ارسال</dt>
            <dd>{formatJalaliDateTime(c.created_at)} · {c.created_by}</dd>
            <dt className="text-muted">مخاطبان</dt>
            <dd>{describeAudience(c.audience)} · {formatNumber(c.recipients)} حساب</dd>
            <dt className="text-muted">کانال</dt>
            <dd><ChannelBadges c={c} /></dd>
            <dt className="text-muted">مقصد</dt>
            <dd>{ROUTE_LABEL[c.route] ?? c.route}</dd>
            {c.push && (
              <>
                <dt className="text-muted">اعلان فوری</dt>
                <dd className="space-y-1">
                  <PushStatusBadge c={c} />
                  {c.push_status !== 'sending' && (
                    <p className="text-xs text-muted">
                      {formatNumber(c.push_users)} حساب · {formatNumber(c.push_devices)} دستگاه · {formatNumber(c.push_sent)} موفق · {formatNumber(c.push_failed)} ناموفق
                      {c.push_removed > 0 && ` · ${formatNumber(c.push_removed)} دستگاهِ نامعتبر حذف شد`}
                    </p>
                  )}
                </dd>
              </>
            )}
            {c.inapp && (
              <>
                <dt className="text-muted">پیام درون‌برنامه</dt>
                <dd>{formatNumber(c.inapp_read)} از {formatNumber(c.inapp_delivered)} نفر خوانده‌اند</dd>
              </>
            )}
          </dl>
          {c.users.length > 0 && (
            <div>
              <p className="mb-1.5 text-muted">گیرندگان</p>
              <ul className="flex flex-wrap gap-1.5">
                {c.users.map((u) => (
                  <li key={u.id}>
                    <Badge tone={u.read_at ? 'green' : 'neutral'}>{u.username || u.id.slice(0, 8)}{u.read_at ? ' ✓' : ''}</Badge>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </Dialog>
  )
}
