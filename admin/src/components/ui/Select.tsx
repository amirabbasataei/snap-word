import * as RS from '@radix-ui/react-select'
import { Check, ChevronDown } from 'lucide-react'
import { cn } from '@/lib/cn'

export interface SelectOption {
  value: string
  label: string
}

interface Props {
  value: string
  onValueChange: (value: string) => void
  options: SelectOption[]
  placeholder?: string
  label?: string
  className?: string
  disabled?: boolean
}

export function Select({ value, onValueChange, options, placeholder, label, className, disabled }: Props) {
  return (
    <RS.Root value={value} onValueChange={onValueChange} dir="rtl" disabled={disabled}>
      <RS.Trigger
        aria-label={label}
        className={cn(
          'inline-flex h-10 min-w-36 items-center justify-between gap-2 rounded-lg border border-border bg-raised px-3 text-sm text-text',
          'transition focus:border-blue focus:outline-none disabled:opacity-60 data-[placeholder]:text-muted',
          className,
        )}
      >
        <RS.Value placeholder={placeholder} />
        <RS.Icon>
          <ChevronDown className="size-4 text-muted" aria-hidden />
        </RS.Icon>
      </RS.Trigger>
      <RS.Portal>
        <RS.Content
          position="popper"
          sideOffset={6}
          className="z-50 min-w-(--radix-select-trigger-width) overflow-hidden rounded-lg border border-border bg-surface p-1 shadow-pop"
        >
          <RS.Viewport>
            {options.map((o) => (
              <RS.Item
                key={o.value}
                value={o.value}
                className="relative flex cursor-pointer select-none items-center rounded-md py-2 ps-8 pe-3 text-sm text-text outline-none data-[highlighted]:bg-active"
              >
                <RS.ItemIndicator className="absolute start-2">
                  <Check className="size-4 text-blue" aria-hidden />
                </RS.ItemIndicator>
                <RS.ItemText>{o.label}</RS.ItemText>
              </RS.Item>
            ))}
          </RS.Viewport>
        </RS.Content>
      </RS.Portal>
    </RS.Root>
  )
}
