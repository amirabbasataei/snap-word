import { forwardRef, useId, type InputHTMLAttributes, type ReactNode } from 'react'
import { cn } from '@/lib/cn'

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string
  hint?: string
  error?: string
  /** Rendered inside the field at its end edge (e.g. a show-password toggle). */
  endAdornment?: ReactNode
  /** Rendered inside the field at its start edge (e.g. a search icon). */
  startAdornment?: ReactNode
}

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { label, hint, error, endAdornment, startAdornment, className, id, ...rest },
  ref,
) {
  const auto = useId()
  const inputId = id ?? auto
  const describedBy = error ? `${inputId}-err` : hint ? `${inputId}-hint` : undefined
  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <label htmlFor={inputId} className="text-sm font-medium text-text">
          {label}
        </label>
      )}
      <div className="relative">
        {startAdornment && (
          <span className="pointer-events-none absolute inset-y-0 start-3 flex items-center text-muted">{startAdornment}</span>
        )}
        <input
          ref={ref}
          id={inputId}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          className={cn(
            'h-10 w-full rounded-lg border bg-raised px-3 text-sm text-text placeholder:text-muted',
            'transition focus:border-blue focus:outline-none disabled:opacity-60',
            error ? 'border-pink' : 'border-border',
            startAdornment && 'ps-10',
            endAdornment && 'pe-10',
            className,
          )}
          {...rest}
        />
        {endAdornment && <span className="absolute inset-y-0 end-1.5 flex items-center">{endAdornment}</span>}
      </div>
      {error ? (
        <p id={`${inputId}-err`} className="text-xs text-pink">
          {error}
        </p>
      ) : hint ? (
        <p id={`${inputId}-hint`} className="text-xs text-muted">
          {hint}
        </p>
      ) : null}
    </div>
  )
})
