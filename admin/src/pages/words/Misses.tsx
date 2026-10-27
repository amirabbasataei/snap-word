import { Check, X } from 'lucide-react'
import { useState } from 'react'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardHeader } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { ReasonDialog } from '@/components/ui/ReasonDialog'
import { useToast } from '@/components/ui/Toast'
import { messageOf } from '@/lib/errors'
import { formatNumber } from '@/lib/fa'
import { useDictAction, useMisses, type WordMiss } from '@/lib/words'
import { WordCell } from './parts'

/** The words players most often typed in 1v1 games that the dictionary rejected. */
export function Misses({ canEdit }: { canEdit: boolean }) {
  const query = useMisses()
  const act = useDictAction()
  const { toast } = useToast()
  const [adding, setAdding] = useState<WordMiss | null>(null)

  const columns: Column<WordMiss>[] = [
    {
      key: 'word',
      header: 'کلمه',
      cell: (m) => (
        <WordCell
          word={m.word}
          warnings={m.warnings}
          extra={
            <>
              {m.in_dictionary && <Badge tone="green">اکنون در دیکشنری است</Badge>}
              {m.known_rejected && <Badge tone="pink">قبلاً رد شده</Badge>}
            </>
          }
        />
      ),
    },
    { key: 'count', header: 'تعداد رد شدن', cell: (m) => formatNumber(m.count) },
  ]
  if (canEdit) {
    columns.push({
      key: 'actions',
      header: '',
      cell: (m) => (
        <div className="flex justify-end gap-2">
          <Button size="sm" disabled={m.in_dictionary} onClick={() => setAdding(m)} aria-label={`افزودن «${m.word}» به دیکشنری`}>
            <Check className="size-4" aria-hidden />
            افزودن
          </Button>
          <Button
            size="sm"
            variant="ghost"
            aria-label={`نادیده گرفتن «${m.word}»`}
            onClick={() =>
              act.mutateAsync({ type: 'dismiss', word: m.word }).then(
                () => toast({ title: 'از فهرست حذف شد.' }),
                (e) => toast({ title: messageOf(e), tone: 'error' }),
              )
            }
          >
            <X className="size-4" aria-hidden />
          </Button>
        </div>
      ),
    })
  }

  return (
    <Card>
      <CardHeader title="پرتکرارترین کلمه‌های ردشده در بازی رودررو" />
      <p className="px-5 pb-3 text-xs text-muted">
        شمارش ناشناس کلمه‌هایی که سرور به‌عنوان «در دیکشنری نیست» رد کرده؛ بدون هیچ اطلاعاتی از بازیکن. کلمه‌ای که واقعاً درست است را اضافه کنید.
      </p>
      <DataTable
        columns={columns}
        rows={query.data?.items}
        rowKey={(m) => m.word}
        loading={query.isPending}
        error={query.isError ? messageOf(query.error) : null}
        onRetry={() => void query.refetch()}
        emptyText="هنوز کلمهٔ ردشده‌ای ثبت نشده است."
      />
      {adding && (
        <ReasonDialog
          open
          onOpenChange={(o) => !o && setAdding(null)}
          title={`افزودن «${adding.word}» به دیکشنری`}
          description="کلمه بلافاصله در بازی رودررو معتبر می‌شود و با همگام‌سازی به برنامهٔ بازیکنان می‌رسد."
          confirmLabel="افزودن"
          onSubmit={async (reason) => {
            await act.mutateAsync({ type: 'set', word: adding.word, action: 'add', reason })
            toast({ title: 'کلمه افزوده شد.' })
          }}
        />
      )}
    </Card>
  )
}
