import { ExternalLink } from 'lucide-react'
import { useId, useState, type ReactNode } from 'react'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Input } from '@/components/ui/Input'
import { messageOf } from '@/lib/errors'
import { formatNumber } from '@/lib/fa'
import { lookupUrl, WARNING_LABEL } from '@/lib/words'

/** The word, with policy warnings and a link to an external dictionary. */
export function WordCell({ word, warnings, extra }: { word: string; warnings: string[]; extra?: ReactNode }) {
  return (
    <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
      <span className="text-base font-medium text-text">{word}</span>
      <a
        href={lookupUrl(word)}
        target="_blank"
        rel="noopener noreferrer"
        className="text-muted hover:text-blue"
        aria-label={`جستجوی «${word}» در واژه‌نامه`}
        title="جستجو در واژه‌یاب"
      >
        <ExternalLink className="size-3.5" aria-hidden />
      </a>
      {warnings.map((w) => (
        <Badge key={w} tone="orange">{WARNING_LABEL[w] ?? w}</Badge>
      ))}
      {extra}
    </div>
  )
}

interface NoteDialogProps {
  title: string
  description?: string
  confirmLabel: string
  danger?: boolean
  /** Count shown in the description of a bulk action. */
  count?: number
  onClose: () => void
  onSubmit: (note: string) => Promise<void>
}

/** Confirmation with an optional note (the review rows keep it; at least 3 characters when given). */
export function NoteDialog({ title, description, confirmLabel, danger, count, onClose, onSubmit }: NoteDialogProps) {
  const formId = useId()
  const [note, setNote] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const n = Array.from(note.trim()).length
  const valid = n === 0 || (n >= 3 && n <= 200)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid || pending) return
    setPending(true)
    setError(null)
    try {
      await onSubmit(note.trim())
      onClose()
    } catch (err) {
      setPending(false)
      setError(messageOf(err))
    }
  }

  return (
    <Dialog
      open
      onOpenChange={(o) => !o && !pending && onClose()}
      title={title}
      description={count ? `${description ?? ''} (${formatNumber(count)} مورد)`.trim() : description}
      footer={
        <>
          <Button variant="secondary" onClick={onClose} disabled={pending}>انصراف</Button>
          <Button type="submit" form={formId} variant={danger ? 'danger' : 'primary'} disabled={!valid} loading={pending}>
            {confirmLabel}
          </Button>
        </>
      }
    >
      <form id={formId} onSubmit={submit} className="flex flex-col gap-3">
        <Input
          label="یادداشت (اختیاری)"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          maxLength={200}
          autoComplete="off"
          error={n > 0 && n < 3 ? 'یادداشت حداقل ۳ نویسه باشد یا خالی بماند.' : undefined}
        />
        {error && <p role="alert" className="rounded-lg border border-pink px-3 py-2 text-sm text-pink">{error}</p>}
      </form>
    </Dialog>
  )
}
