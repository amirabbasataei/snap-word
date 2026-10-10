import { Pencil } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '@/auth/AuthContext'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { roleAtLeast } from '@/layout/nav'
import { useDailyList, type DailyDay } from '@/lib/content'
import { messageOf } from '@/lib/errors'
import { formatNumber } from '@/lib/fa'
import { dayLabel, DayStatusBadges, LetterTile, StartLetterDialog } from './content/daily'

export function Daily() {
  const { admin } = useAuth()
  const canEdit = admin ? roleAtLeast(admin.role, 'operator') : false
  const query = useDailyList()
  const [editing, setEditing] = useState<DailyDay | null>(null)

  const columns: Column<DailyDay>[] = [
    {
      key: 'day',
      header: 'چالش',
      cell: (d) => {
        const label = (
          <>
            <span className="font-medium">#{formatNumber(d.day_number)}</span>
            <span className="tabular block text-xs text-muted">{dayLabel(d.date)}</span>
          </>
        )
        return (
          <div>
            {d.generated ? <Link to={`/content/daily/${d.date}`} className="block hover:text-blue">{label}</Link> : <span className="block">{label}</span>}
            {/* the status column is hidden on phones; the badges move under the day */}
            <span className="mt-1.5 block sm:hidden">
              <DayStatusBadges status={d.status} generated={d.generated} customized={d.customized} />
            </span>
          </div>
        )
      },
    },
    { key: 'letter', header: 'حرف شروع', cell: (d) => <LetterTile letter={d.start_letter} /> },
    { key: 'status', header: 'وضعیت', className: 'hidden sm:table-cell', cell: (d) => <DayStatusBadges status={d.status} generated={d.generated} customized={d.customized} /> },
    { key: 'players', header: 'بازیکن', className: 'hidden sm:table-cell', cell: (d) => (d.generated && d.status !== 'future' ? formatNumber(d.players) : '—') },
    { key: 'attempts', header: 'تلاش', className: 'hidden md:table-cell', cell: (d) => (d.generated && d.status !== 'future' ? formatNumber(d.attempts) : '—') },
    { key: 'best', header: 'بهترین امتیاز', className: 'hidden md:table-cell', cell: (d) => (d.players > 0 ? formatNumber(d.best_score) : '—') },
    {
      key: 'actions',
      header: <span className="sr-only">اقدام‌ها</span>,
      cell: (d) =>
        canEdit && d.editable && query.data ? (
          <Button size="sm" variant="secondary" onClick={() => setEditing(d)} aria-label={`تغییر حرف شروع چالش ${formatNumber(d.day_number)}`}>
            <Pencil className="size-3.5" aria-hidden />
            <span className="hidden sm:inline">تغییر حرف</span>
          </Button>
        ) : null,
    },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">چالش روزانه</h1>
        <p className="text-xs text-muted">
          ۳۰ روز گذشته تا ۷ روز آینده، به وقت ایران. حرف شروع فقط برای روزهای آینده قابل تغییر است؛ روزی که زمان‌بند هنوز نساخته، حرفِ نشان‌داده‌شده همان است که ساخته می‌شود.
        </p>
      </div>
      <Card>
        <DataTable
          columns={columns}
          rows={query.data?.rows}
          rowKey={(d) => d.date}
          loading={query.isPending}
          error={query.isError ? messageOf(query.error) : null}
          onRetry={() => void query.refetch()}
          emptyText="چالشی در این بازه وجود ندارد."
        />
      </Card>
      {editing && query.data && (
        <StartLetterDialog
          date={editing.date}
          dayNumber={editing.day_number}
          current={editing.start_letter}
          letters={query.data.eligible_letters}
          onClose={() => setEditing(null)}
        />
      )}
    </div>
  )
}
