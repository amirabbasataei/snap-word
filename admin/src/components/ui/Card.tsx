import type { HTMLAttributes, ReactNode } from 'react'
import { MoreHorizontal } from 'lucide-react'
import * as DM from '@radix-ui/react-dropdown-menu'
import { cn } from '@/lib/cn'

export function Card({ className, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return <section className={cn('rounded-card border border-border bg-surface', className)} {...rest} />
}

export interface CardMenuItem {
  label: string
  onSelect: () => void
}

interface HeaderProps {
  title: ReactNode
  /** Items for the `⋯` menu; omit for no menu. */
  menu?: CardMenuItem[]
  actions?: ReactNode
}

/** Title row + `⋯` menu, separated from the body by a hairline (reference style). */
export function CardHeader({ title, menu, actions }: HeaderProps) {
  return (
    <header className="flex items-center justify-between gap-3 border-b border-border px-5 py-3.5">
      <h2 className="text-base font-semibold text-text">{title}</h2>
      <div className="flex items-center gap-2">
        {actions}
        {menu && menu.length > 0 && (
          <DM.Root dir="rtl">
            <DM.Trigger
              aria-label="گزینه‌ها"
              className="grid size-8 cursor-pointer place-items-center rounded-md text-muted transition hover:bg-active hover:text-text"
            >
              <MoreHorizontal className="size-5" aria-hidden />
            </DM.Trigger>
            <DM.Portal>
              <DM.Content
                align="start"
                sideOffset={4}
                className="z-50 min-w-40 rounded-lg border border-border bg-surface p-1 shadow-pop"
              >
                {menu.map((m) => (
                  <DM.Item
                    key={m.label}
                    onSelect={m.onSelect}
                    className="cursor-pointer rounded-md px-3 py-2 text-sm text-text outline-none data-[highlighted]:bg-active"
                  >
                    {m.label}
                  </DM.Item>
                ))}
              </DM.Content>
            </DM.Portal>
          </DM.Root>
        )}
      </div>
    </header>
  )
}

export function CardBody({ className, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('p-5', className)} {...rest} />
}
