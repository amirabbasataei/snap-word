import * as RA from '@radix-ui/react-avatar'
import { cn } from '@/lib/cn'

interface Props {
  name: string
  src?: string
  className?: string
}

/** Image with the first letter of the name as fallback (matches the app's AvatarTile). */
export function Avatar({ name, src, className }: Props) {
  const initial = Array.from(name.trim())[0] ?? '؟'
  return (
    <RA.Root
      className={cn(
        'inline-grid size-10 shrink-0 place-items-center overflow-hidden rounded-full bg-active text-sm font-semibold text-text',
        className,
      )}
    >
      {src && <RA.Image src={src} alt="" className="size-full object-cover" />}
      <RA.Fallback delayMs={src ? 300 : 0}>{initial}</RA.Fallback>
    </RA.Root>
  )
}
