import * as RD from '@radix-ui/react-dialog'
import { X } from 'lucide-react'
import { useState, type ReactNode } from 'react'
import { Button } from './Button'
import { Input } from './Input'

interface DialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description?: string
  children?: ReactNode
  footer?: ReactNode
}

export function Dialog({ open, onOpenChange, title, description, children, footer }: DialogProps) {
  return (
    <RD.Root open={open} onOpenChange={onOpenChange}>
      <RD.Portal>
        <RD.Overlay className="fixed inset-0 z-50 animate-[fade-in_150ms_ease-out] bg-scrim" />
        <RD.Content
          dir="rtl"
          className="fixed inset-x-0 top-1/2 z-50 mx-auto w-[calc(100%-2rem)] max-w-md -translate-y-1/2 animate-[pop-in_150ms_ease-out] rounded-card border border-border bg-surface shadow-pop"
        >
          <header className="flex items-start justify-between gap-4 border-b border-border px-5 py-4">
            <div>
              <RD.Title className="text-base font-semibold text-text">{title}</RD.Title>
              {description ? (
                <RD.Description className="mt-1 text-sm text-muted">{description}</RD.Description>
              ) : (
                <RD.Description className="sr-only">{title}</RD.Description>
              )}
            </div>
            <RD.Close
              aria-label="بستن"
              className="grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-muted hover:bg-active hover:text-text"
            >
              <X className="size-4" aria-hidden />
            </RD.Close>
          </header>
          {children && <div className="px-5 py-4">{children}</div>}
          {footer && <footer className="flex justify-end gap-2 border-t border-border px-5 py-3.5">{footer}</footer>}
        </RD.Content>
      </RD.Portal>
    </RD.Root>
  )
}

interface ConfirmProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description?: string
  confirmLabel: string
  onConfirm: () => void | Promise<void>
  /** Destructive actions: the operator must type this exact text to enable the button. */
  requireText?: string
  loading?: boolean
}

export function ConfirmDialog({ open, onOpenChange, title, description, confirmLabel, onConfirm, requireText, loading }: ConfirmProps) {
  const [typed, setTyped] = useState('')
  const blocked = requireText !== undefined && typed.trim() !== requireText
  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        if (!o) setTyped('')
        onOpenChange(o)
      }}
      title={title}
      description={description}
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            انصراف
          </Button>
          <Button variant="danger" disabled={blocked} loading={loading} onClick={() => void onConfirm()}>
            {confirmLabel}
          </Button>
        </>
      }
    >
      {requireText !== undefined && (
        <Input
          label={`برای تأیید «${requireText}» را تایپ کنید`}
          value={typed}
          onChange={(e) => setTyped(e.target.value)}
          autoComplete="off"
        />
      )}
    </Dialog>
  )
}
