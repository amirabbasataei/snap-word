import { useId, useState, type FormEvent, type ReactNode } from 'react'
import { messageOf } from '@/lib/errors'
import { formatNumber } from '@/lib/fa'
import { Button } from './Button'
import { Dialog } from './Dialog'
import { Input } from './Input'

export const REASON_MIN = 3
export const REASON_MAX = 200

interface Props {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description?: string
  confirmLabel: string
  /** Red confirm button for destructive actions. */
  danger?: boolean
  /** Destructive: the operator must type this exact text before confirming. */
  requireText?: string
  /** Action-specific fields, rendered above the reason. */
  children?: ReactNode
  /** Extra validity gate for the fields in `children`. */
  valid?: boolean
  /** Performs the action; a rejection is shown inside the dialog in Persian. */
  onSubmit: (reason: string) => Promise<void>
}

/**
 * Dialog for every audited admin mutation: optional fields, a mandatory reason
 * (the API rejects an action without one) and, for destructive actions, a
 * typed confirmation.
 */
export function ReasonDialog({
  open, onOpenChange, title, description, confirmLabel, danger, requireText, children, valid = true, onSubmit,
}: Props) {
  const formId = useId()
  const [reason, setReason] = useState('')
  const [typed, setTyped] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)

  const trimmed = reason.trim()
  const reasonOk = Array.from(trimmed).length >= REASON_MIN
  const confirmed = requireText === undefined || typed.trim() === requireText
  const canSubmit = valid && reasonOk && confirmed && !pending

  function handleOpenChange(o: boolean) {
    if (pending) return
    if (!o) {
      setReason('')
      setTyped('')
      setError(null)
    }
    onOpenChange(o)
  }

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (!canSubmit) return
    setPending(true)
    setError(null)
    try {
      await onSubmit(trimmed)
      setPending(false)
      handleOpenChange(false)
    } catch (err) {
      setPending(false)
      setError(messageOf(err))
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={handleOpenChange}
      title={title}
      description={description}
      footer={
        <>
          <Button variant="secondary" onClick={() => handleOpenChange(false)} disabled={pending}>
            انصراف
          </Button>
          <Button type="submit" form={formId} variant={danger ? 'danger' : 'primary'} disabled={!canSubmit} loading={pending}>
            {confirmLabel}
          </Button>
        </>
      }
    >
      <form id={formId} onSubmit={submit} className="flex flex-col gap-4">
        {children}
        <Input
          label="دلیل (ثبت در گزارش فعالیت)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          maxLength={REASON_MAX}
          autoComplete="off"
          hint={`${formatNumber(Array.from(trimmed).length)} از ${formatNumber(REASON_MAX)} · حداقل ${formatNumber(REASON_MIN)} نویسه`}
        />
        {requireText !== undefined && (
          <Input
            label={`برای تأیید «${requireText}» را تایپ کنید`}
            value={typed}
            onChange={(e) => setTyped(e.target.value)}
            autoComplete="off"
            dir="auto"
          />
        )}
        {error && (
          <p role="alert" className="rounded-lg border border-pink px-3 py-2 text-sm text-pink">
            {error}
          </p>
        )}
      </form>
    </Dialog>
  )
}
