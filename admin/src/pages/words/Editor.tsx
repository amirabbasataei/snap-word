import { Copy, Search } from 'lucide-react'
import { useState, type FormEvent } from 'react'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { ReasonDialog } from '@/components/ui/ReasonDialog'
import { useToast } from '@/components/ui/Toast'
import { messageOf } from '@/lib/errors'
import { formatNumber } from '@/lib/fa'
import { STATUS_LABEL, useDictAction, useWordExport, useWordLookup, type WordOverrideAction } from '@/lib/words'
import { WordCell } from './parts'

const ACTION_COPY: Record<WordOverrideAction, { title: string; confirm: string; done: string; danger?: boolean }> = {
  add: { title: 'افزودن به دیکشنری', confirm: 'افزودن', done: 'کلمه افزوده شد.' },
  remove: { title: 'حذف از دیکشنری', confirm: 'حذف', done: 'کلمه حذف شد.', danger: true },
  ai_block: { title: 'مسدود کردن برای هوش مصنوعی', confirm: 'مسدود کردن', done: 'کلمه برای هوش مصنوعی مسدود شد.' },
  ai_unblock: { title: 'رفع انسداد برای هوش مصنوعی', confirm: 'رفع انسداد', done: 'انسداد برداشته شد.' },
}

/** Look a word up and change the dictionary directly; export the overlay for the next fa.txt release. */
export function Editor({ canEdit }: { canEdit: boolean }) {
  const [text, setText] = useState('')
  const [word, setWord] = useState('')
  const [action, setAction] = useState<WordOverrideAction | null>(null)
  const lookup = useWordLookup(word)
  const act = useDictAction()
  const { toast } = useToast()

  function search(e: FormEvent) {
    e.preventDefault()
    setWord(text.trim())
  }
  const d = lookup.data

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader title="بررسی و ویرایش مستقیم یک کلمه" />
        <CardBody className="space-y-4">
          <form onSubmit={search} className="flex items-end gap-2">
            <Input label="کلمه" value={text} onChange={(e) => setText(e.target.value)} autoComplete="off" className="w-64" />
            <Button type="submit" variant="secondary" disabled={text.trim() === ''}>
              <Search className="size-4" aria-hidden />
              بررسی
            </Button>
          </form>

          {word !== '' && lookup.isError && <p role="alert" className="text-sm text-pink">{messageOf(lookup.error)}</p>}
          {d && (
            <div className="space-y-3 rounded-lg border border-border p-4">
              <WordCell word={d.word} warnings={d.warnings} />
              <div className="flex flex-wrap gap-2">
                {d.in_dictionary ? <Badge tone="green">در دیکشنری هست</Badge> : <Badge tone="neutral">در دیکشنری نیست</Badge>}
                {d.in_dictionary && !d.in_base && <Badge tone="blue">افزودهٔ بعدی (هنوز در fa.txt نیست)</Badge>}
                {!d.in_dictionary && d.in_base && <Badge tone="pink">حذف‌شده از fa.txt</Badge>}
                {d.ai_blocked && <Badge tone="yellow">مسدود برای هوش مصنوعی</Badge>}
                {d.known_rejected && <Badge tone="pink">در فهرست ردشده‌های پالایش</Badge>}
              </div>
              {d.suggestions.length > 0 && (
                <ul className="space-y-1 text-sm text-muted">
                  {d.suggestions.map((s) => (
                    <li key={s.id}>
                      {s.kind === 'add' ? 'پیشنهاد افزودن' : 'گزارش حذف'} — {STATUS_LABEL[s.status]} — {formatNumber(s.reporters)} گزارش
                    </li>
                  ))}
                </ul>
              )}
              {canEdit && (
                <div className="flex flex-wrap gap-2">
                  {!d.in_dictionary && <Button size="sm" onClick={() => setAction('add')}>افزودن</Button>}
                  {d.in_dictionary && <Button size="sm" variant="danger" onClick={() => setAction('remove')}>حذف از دیکشنری</Button>}
                  {d.in_dictionary && !d.ai_blocked && <Button size="sm" variant="secondary" onClick={() => setAction('ai_block')}>مسدود برای هوش مصنوعی</Button>}
                  {d.ai_blocked && <Button size="sm" variant="secondary" onClick={() => setAction('ai_unblock')}>رفع انسداد هوش مصنوعی</Button>}
                </div>
              )}
            </div>
          )}
        </CardBody>
      </Card>

      <ExportCard />

      {action && d && (
        <ReasonDialog
          open
          onOpenChange={(o) => !o && setAction(null)}
          title={`${ACTION_COPY[action].title}: «${d.word}»`}
          confirmLabel={ACTION_COPY[action].confirm}
          danger={ACTION_COPY[action].danger}
          requireText={ACTION_COPY[action].danger ? d.word : undefined}
          onSubmit={async (reason) => {
            await act.mutateAsync({ type: 'set', word: d.word, action, reason })
            toast({ title: ACTION_COPY[action].done })
          }}
        />
      )}
    </div>
  )
}

function ExportCard() {
  const [open, setOpen] = useState(false)
  const q = useWordExport(open)
  const { toast } = useToast()
  const d = q.data

  async function copy(words: string[]) {
    try {
      await navigator.clipboard.writeText(words.join('\n'))
      toast({ title: 'کپی شد.' })
    } catch {
      toast({ title: 'کپی انجام نشد؛ متن را دستی انتخاب کنید.', tone: 'error' })
    }
  }

  return (
    <Card>
      <CardHeader title="خروجی برای نسخهٔ بعدی fa.txt" />
      <CardBody className="space-y-4">
        <p className="text-sm text-muted">
          کلمه‌های تأییدشده فوراً فعال هستند و از طریق همگام‌سازی به برنامه می‌رسند. برای ثبت دائمی، هر نسخهٔ منتشرشده باید این فهرست را به هر دو نسخهٔ
          <span dir="ltr"> fa.txt </span>
          (سرور و برنامه — باید یکسان بمانند) اضافه یا از آن‌ها حذف کند.
        </p>
        {!open ? (
          <Button variant="secondary" onClick={() => setOpen(true)}>نمایش خروجی</Button>
        ) : q.isPending ? (
          <p className="text-sm text-muted">در حال بارگذاری…</p>
        ) : q.isError ? (
          <p role="alert" className="text-sm text-pink">{messageOf(q.error)}</p>
        ) : d ? (
          <div className="grid gap-4 md:grid-cols-3">
            <ExportList title="اضافه شود" words={d.added} onCopy={copy} />
            <ExportList title="حذف شود" words={d.removed} onCopy={copy} />
            <ExportList title="مسدود برای هوش مصنوعی (در فایل می‌ماند)" words={d.ai_blocked} onCopy={copy} />
          </div>
        ) : null}
      </CardBody>
    </Card>
  )
}

function ExportList({ title, words, onCopy }: { title: string; words: string[]; onCopy: (w: string[]) => void }) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-sm font-medium text-text">{title} ({formatNumber(words.length)})</h3>
        <Button size="sm" variant="ghost" disabled={words.length === 0} onClick={() => onCopy(words)} aria-label={`کپی ${title}`}>
          <Copy className="size-4" aria-hidden />
        </Button>
      </div>
      <textarea
        readOnly
        aria-label={title}
        value={words.join('\n')}
        className="h-40 w-full resize-y rounded-lg border border-border bg-raised p-3 text-sm text-text"
      />
    </div>
  )
}
