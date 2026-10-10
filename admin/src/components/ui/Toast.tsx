import * as RT from '@radix-ui/react-toast'
import { AlertCircle, CheckCircle2, X } from 'lucide-react'
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import { cn } from '@/lib/cn'

type ToastTone = 'success' | 'error'
interface ToastItem {
  id: number
  title: string
  description?: string
  tone: ToastTone
}
interface ToastApi {
  toast: (t: { title: string; description?: string; tone?: ToastTone }) => void
}

const Ctx = createContext<ToastApi | null>(null)

export function useToast(): ToastApi {
  const v = useContext(Ctx)
  if (!v) throw new Error('useToast must be used inside <ToastProvider>')
  return v
}

let seq = 0

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([])
  const toast = useCallback<ToastApi['toast']>((t) => {
    setItems((cur) => [...cur, { id: ++seq, title: t.title, description: t.description, tone: t.tone ?? 'success' }])
  }, [])
  const api = useMemo(() => ({ toast }), [toast])

  return (
    <Ctx.Provider value={api}>
      <RT.Provider swipeDirection="right" duration={5000}>
        {children}
        {items.map((t) => (
          <RT.Root
            key={t.id}
            dir="rtl"
            onOpenChange={(open) => {
              if (!open) setItems((cur) => cur.filter((x) => x.id !== t.id))
            }}
            className="flex items-start gap-3 rounded-lg border border-border bg-surface p-4 shadow-pop data-[state=open]:animate-[pop-in_150ms_ease-out]"
          >
            {t.tone === 'success' ? (
              <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-green" aria-hidden />
            ) : (
              <AlertCircle className={cn('mt-0.5 size-5 shrink-0 text-pink')} aria-hidden />
            )}
            <div className="flex-1">
              <RT.Title className="text-sm font-medium text-text">{t.title}</RT.Title>
              {t.description && <RT.Description className="mt-0.5 text-xs text-muted">{t.description}</RT.Description>}
            </div>
            <RT.Close aria-label="بستن" className="cursor-pointer text-muted hover:text-text">
              <X className="size-4" aria-hidden />
            </RT.Close>
          </RT.Root>
        ))}
        <RT.Viewport className="fixed bottom-4 start-4 z-[100] flex w-[calc(100%-2rem)] max-w-sm flex-col gap-2 outline-none" />
      </RT.Provider>
    </Ctx.Provider>
  )
}
