import { cn } from '@/lib/cn'

/** Two interlocked chain links + wordmark. */
export function Logo({ className, showText = true }: { className?: string; showText?: boolean }) {
  return (
    <span className={cn('inline-flex items-center gap-2.5 text-text', className)}>
      <svg viewBox="0 0 32 32" className="size-8 shrink-0" fill="none" strokeWidth="3" strokeLinecap="round" aria-hidden>
        <rect x="3" y="10" width="14" height="12" rx="6" className="stroke-blue" />
        <rect x="15" y="10" width="14" height="12" rx="6" className="stroke-orange" />
      </svg>
      {showText && <span className="text-xl font-bold">زنجیر</span>}
    </span>
  )
}
