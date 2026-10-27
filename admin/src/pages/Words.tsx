import { Check, Search, X } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useAuth } from '@/auth/AuthContext'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardHeader } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { Input } from '@/components/ui/Input'
import { ReasonDialog } from '@/components/ui/ReasonDialog'
import { Select } from '@/components/ui/Select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/Tabs'
import { useToast } from '@/components/ui/Toast'
import { roleAtLeast } from '@/layout/nav'
import { messageOf } from '@/lib/errors'
import { formatNumber, formatRelative } from '@/lib/fa'
import {
  STATUS_LABEL, useWordDecision, useWordQueue, WORDS_PAGE_SIZE,
  type BulkResult, type RemoveOutcome, type WordKind, type WordSort, type WordStatusFilter, type WordSuggestion,
} from '@/lib/words'
import { Editor } from './words/Editor'
import { Misses } from './words/Misses'
import { NoteDialog, WordCell } from './words/parts'

const STATUS_OPTIONS: { value: WordStatusFilter; label: string }[] = [
  { value: 'pending', label: 'در انتظار بررسی' },
  { value: 'approved', label: 'تأییدشده' },
  { value: 'rejected', label: 'ردشده' },
  { value: 'all', label: 'همه' },
]
const SORT_OPTIONS: { value: WordSort; label: string }[] = [
  { value: 'reporters', label: 'بیشترین گزارش' },
  { value: 'recent', label: 'جدیدترین' },
]

type Dialog =
  | { kind: 'approve'; ids: number[] }
  | { kind: 'reject'; ids: number[] }
  | { kind: 'ai_block'; item: WordSuggestion }
  | { kind: 'remove'; item: WordSuggestion }

export function Words() {
  const { admin } = useAuth()
  const canEdit = admin ? roleAtLeast(admin.role, 'operator') : false
  // Both queues stay mounted (hidden when inactive) so the tab badges show the pending counts.
  const [pending, setPending] = useState<Record<WordKind, number>>({ add: 0, remove: 0 })

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">پیشنهاد کلمات</h1>
        <p className="text-xs text-muted">
          کلمه‌هایی که بازیکنان به‌عنوان «کلمهٔ درستِ ناموجود» گزارش داده‌اند، گزارش کلمه‌های نامناسب، و ویرایش مستقیم دیکشنری. تأیید یک کلمه بلافاصله آن را در بازی رودررو معتبر می‌کند و با همگام‌سازی به برنامهٔ بازیکنان می‌رسد.
        </p>
      </div>
      <Tabs defaultValue="add">
        <TabsList className="overflow-x-auto">
          <TabsTrigger value="add">پیشنهاد افزودن{pending.add ? ` (${formatNumber(pending.add)})` : ''}</TabsTrigger>
          <TabsTrigger value="remove">گزارش حذف{pending.remove ? ` (${formatNumber(pending.remove)})` : ''}</TabsTrigger>
          <TabsTrigger value="misses">ردشده‌ها در بازی</TabsTrigger>
          <TabsTrigger value="editor">ویرایش مستقیم</TabsTrigger>
        </TabsList>
        <div className="pt-6">
          <TabsContent value="add" forceMount className="data-[state=inactive]:hidden">
            <Queue kind="add" canEdit={canEdit} onPending={setPending} />
          </TabsContent>
          <TabsContent value="remove" forceMount className="data-[state=inactive]:hidden">
            <Queue kind="remove" canEdit={canEdit} onPending={setPending} />
          </TabsContent>
          <TabsContent value="misses">
            <Misses canEdit={canEdit} />
          </TabsContent>
          <TabsContent value="editor">
            <Editor canEdit={canEdit} />
          </TabsContent>
        </div>
      </Tabs>
    </div>
  )
}

function Queue({ kind, canEdit, onPending }: { kind: WordKind; canEdit: boolean; onPending: (p: Record<WordKind, number>) => void }) {
  const [status, setStatus] = useState<WordStatusFilter>('pending')
  const [sort, setSort] = useState<WordSort>('reporters')
  const [text, setText] = useState('')
  const [q, setQ] = useState('')
  const [page, setPage] = useState(1)
  const [selected, setSelected] = useState<Set<number>>(new Set())
  const [dialog, setDialog] = useState<Dialog | null>(null)
  const decide = useWordDecision()
  const { toast } = useToast()

  useEffect(() => {
    const t = setTimeout(() => {
      setQ(text.trim())
      setPage(1)
    }, 350)
    return () => clearTimeout(t)
  }, [text])

  const query = useWordQueue({ kind, status, q, sort, page })
  const rows = query.data?.items
  useEffect(() => {
    if (query.data) onPending(query.data.pending)
  }, [query.data, onPending])
  // Selection never outlives the page or filter it was made on.
  useEffect(() => setSelected(new Set()), [status, q, sort, page, kind])

  const selectable = useMemo(() => (rows ?? []).filter((r) => r.status === 'pending'), [rows])
  const isAdd = kind === 'add'

  function toggle(id: number) {
    setSelected((cur) => {
      const next = new Set(cur)
      if (!next.delete(id)) next.add(id)
      return next
    })
  }

  async function run(fn: () => Promise<unknown>, done: string) {
    const res = await fn()
    const bulk = res as Partial<BulkResult> | undefined
    if (bulk && Array.isArray(bulk.failed) && bulk.failed.length > 0) {
      toast({ title: `${formatNumber(bulk.done ?? 0)} مورد انجام شد؛ ${formatNumber(bulk.failed.length)} مورد نشد.`, tone: 'error' })
    } else {
      toast({ title: done })
    }
    setSelected(new Set())
  }

  const columns: Column<WordSuggestion>[] = []
  if (canEdit && isAdd) {
    columns.push({
      key: 'select',
      header: '',
      className: 'w-10',
      cell: (r) =>
        r.status === 'pending' ? (
          <input
            type="checkbox"
            checked={selected.has(r.id)}
            onChange={() => toggle(r.id)}
            aria-label={`انتخاب «${r.word}»`}
            className="size-4 cursor-pointer accent-[var(--blue)]"
          />
        ) : null,
    })
  }
  columns.push(
    { key: 'word', header: 'کلمه', cell: (r) => <WordCell word={r.word} warnings={r.warnings} extra={r.known_rejected ? <Badge tone="pink">قبلاً رد شده</Badge> : undefined} /> },
    { key: 'reporters', header: 'گزارش‌دهنده', cell: (r) => formatNumber(r.reporters) },
  )
  if (!isAdd) {
    columns.push({
      key: 'reasons',
      header: 'دلیل گزارش',
      className: 'hidden md:table-cell',
      cell: (r) => (
        <span className="text-muted">
          {r.not_a_word > 0 && `کلمه نیست: ${formatNumber(r.not_a_word)}`}
          {r.not_a_word > 0 && r.inappropriate > 0 && ' · '}
          {r.inappropriate > 0 && `نامناسب: ${formatNumber(r.inappropriate)}`}
        </span>
      ),
    })
  }
  columns.push(
    { key: 'last', header: 'آخرین گزارش', className: 'hidden sm:table-cell', cell: (r) => formatRelative(r.last_reported_at) },
    {
      key: 'status',
      header: 'وضعیت',
      cell: (r) => (
        <Badge tone={r.status === 'approved' ? 'green' : r.status === 'rejected' ? 'pink' : 'neutral'} title={r.review_note || undefined}>
          {STATUS_LABEL[r.status]}
          {r.status === 'approved' && r.outcome === 'ai_block' && ' (فقط AI)'}
        </Badge>
      ),
    },
  )
  if (canEdit) {
    columns.push({
      key: 'actions',
      header: '',
      cell: (r) =>
        r.status !== 'pending' ? null : (
          <div className="flex justify-end gap-2">
            {isAdd ? (
              <Button size="sm" onClick={() => setDialog({ kind: 'approve', ids: [r.id] })} aria-label={`تأیید «${r.word}»`}>
                <Check className="size-4" aria-hidden />
                تأیید
              </Button>
            ) : (
              <>
                <Button size="sm" variant="secondary" onClick={() => setDialog({ kind: 'ai_block', item: r })} aria-label={`مسدود برای هوش مصنوعی «${r.word}»`}>
                  مسدود برای AI
                </Button>
                <Button size="sm" variant="danger" onClick={() => setDialog({ kind: 'remove', item: r })} aria-label={`حذف «${r.word}» از دیکشنری`}>
                  حذف از دیکشنری
                </Button>
              </>
            )}
            <Button size="sm" variant="ghost" onClick={() => setDialog({ kind: 'reject', ids: [r.id] })} aria-label={`رد «${r.word}»`}>
              <X className="size-4" aria-hidden />
              رد
            </Button>
          </div>
        ),
    })
  }

  const ids = [...selected]
  return (
    <Card>
      <CardHeader title={isAdd ? 'پیشنهاد افزودن کلمه' : 'گزارش کلمه‌های نادرست یا نامناسب'} />
      <div className="flex flex-wrap items-end gap-3 border-b border-border px-5 pb-4">
        <Input
          label="جستجو"
          value={text}
          onChange={(e) => setText(e.target.value)}
          autoComplete="off"
          startAdornment={<Search className="size-4" aria-hidden />}
          className="w-52"
        />
        <Select
          label="وضعیت"
          value={status}
          onValueChange={(v) => {
            setStatus(v as WordStatusFilter)
            setPage(1)
          }}
          options={STATUS_OPTIONS}
        />
        <Select
          label="مرتب‌سازی"
          value={sort}
          onValueChange={(v) => {
            setSort(v as WordSort)
            setPage(1)
          }}
          options={SORT_OPTIONS}
        />
      </div>

      {canEdit && isAdd && selectable.length > 0 && (
        <div className="flex flex-wrap items-center gap-3 border-b border-border bg-raised px-5 py-3 text-sm">
          <span className="text-text">{ids.length ? `${formatNumber(ids.length)} مورد انتخاب شده` : 'مورد انتخاب‌شده‌ای نیست'}</span>
          <Button size="sm" variant="secondary" onClick={() => setSelected(new Set(selectable.filter((r) => r.warnings.length === 0).map((r) => r.id)))}>
            انتخاب همهٔ بدون هشدار
          </Button>
          {ids.length > 0 && (
            <>
              <Button size="sm" onClick={() => setDialog({ kind: 'approve', ids })}>تأیید انتخاب‌شده‌ها</Button>
              <Button size="sm" variant="ghost" onClick={() => setDialog({ kind: 'reject', ids })}>رد انتخاب‌شده‌ها</Button>
              <Button size="sm" variant="ghost" onClick={() => setSelected(new Set())}>لغو انتخاب</Button>
            </>
          )}
        </div>
      )}

      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(r) => String(r.id)}
        loading={query.isPending}
        error={query.isError ? messageOf(query.error) : null}
        onRetry={() => void query.refetch()}
        emptyText={status === 'pending' ? 'پیشنهادی در انتظار بررسی نیست.' : 'موردی پیدا نشد.'}
        page={page}
        pageSize={WORDS_PAGE_SIZE}
        total={query.data?.total}
        onPageChange={setPage}
      />

      {dialog?.kind === 'approve' && (
        <NoteDialog
          title={dialog.ids.length > 1 ? 'تأیید کلمه‌های انتخاب‌شده' : 'تأیید کلمه'}
          description="کلمه بلافاصله در دیکشنری فعال می‌شود و اولین گزارش‌دهندهٔ واردشده جایزه می‌گیرد."
          confirmLabel="تأیید"
          count={dialog.ids.length > 1 ? dialog.ids.length : undefined}
          onClose={() => setDialog(null)}
          onSubmit={(note) =>
            run(
              () => decide.mutateAsync(dialog.ids.length > 1 ? { type: 'bulk', ids: dialog.ids, action: 'approve', note } : { type: 'approve', id: dialog.ids[0], note }),
              'کلمه تأیید شد.',
            )
          }
        />
      )}
      {dialog?.kind === 'reject' && (
        <NoteDialog
          title={dialog.ids.length > 1 ? 'رد پیشنهادهای انتخاب‌شده' : 'رد پیشنهاد'}
          description="پیشنهاد رد می‌شود و دوباره قابل گزارش نیست."
          confirmLabel="رد"
          danger
          count={dialog.ids.length > 1 ? dialog.ids.length : undefined}
          onClose={() => setDialog(null)}
          onSubmit={(note) =>
            run(
              () => decide.mutateAsync(dialog.ids.length > 1 ? { type: 'bulk', ids: dialog.ids, action: 'reject', note } : { type: 'reject', id: dialog.ids[0], note }),
              'پیشنهاد رد شد.',
            )
          }
        />
      )}
      {dialog?.kind === 'ai_block' && (
        <NoteDialog
          title={`مسدود برای هوش مصنوعی: «${dialog.item.word}»`}
          description="کلمه برای بازیکنان معتبر می‌ماند ولی حریف هوش مصنوعی هرگز آن را بازی نمی‌کند."
          confirmLabel="مسدود کردن"
          onClose={() => setDialog(null)}
          onSubmit={(note) => run(() => decide.mutateAsync({ type: 'approve', id: dialog.item.id, outcome: 'ai_block' as RemoveOutcome, note }), 'کلمه برای هوش مصنوعی مسدود شد.')}
        />
      )}
      {dialog?.kind === 'remove' && (
        <ReasonDialog
          open
          onOpenChange={(o) => !o && setDialog(null)}
          title={`حذف «${dialog.item.word}» از دیکشنری`}
          description="از این پس این کلمه در بازی (رودررو و، پس از همگام‌سازی، تک‌نفره و رقابت با هوش مصنوعی) نامعتبر است."
          confirmLabel="حذف از دیکشنری"
          danger
          requireText={dialog.item.word}
          onSubmit={(reason) => run(() => decide.mutateAsync({ type: 'approve', id: dialog.item.id, outcome: 'remove', note: reason }), 'کلمه حذف شد.')}
        />
      )}
    </Card>
  )
}
