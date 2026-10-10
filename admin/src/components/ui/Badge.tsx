import type { HTMLAttributes } from 'react'
import { cn } from '@/lib/cn'

export type Tone = 'blue' | 'orange' | 'pink' | 'green' | 'yellow' | 'neutral'

// Tinted pill: text in the tone colour over a 15% mix of it (tokens only).
export const TONE_TEXT: Record<Tone, string> = {
  blue: 'text-blue',
  orange: 'text-orange',
  pink: 'text-pink',
  green: 'text-green',
  yellow: 'text-yellow',
  neutral: 'text-muted',
}
const TONE_BG: Record<Tone, string> = {
  blue: 'bg-[color-mix(in_srgb,var(--blue)_15%,transparent)]',
  orange: 'bg-[color-mix(in_srgb,var(--orange)_15%,transparent)]',
  pink: 'bg-[color-mix(in_srgb,var(--pink)_15%,transparent)]',
  green: 'bg-[color-mix(in_srgb,var(--green)_15%,transparent)]',
  yellow: 'bg-[color-mix(in_srgb,var(--yellow)_15%,transparent)]',
  neutral: 'bg-active',
}

export function Badge({ tone = 'neutral', className, ...rest }: HTMLAttributes<HTMLSpanElement> & { tone?: Tone }) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
        TONE_TEXT[tone],
        TONE_BG[tone],
        className,
      )}
      {...rest}
    />
  )
}
