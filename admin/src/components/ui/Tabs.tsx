import * as RT from '@radix-ui/react-tabs'
import type { ComponentProps } from 'react'
import { cn } from '@/lib/cn'

export function Tabs(props: ComponentProps<typeof RT.Root>) {
  return <RT.Root dir="rtl" {...props} />
}

export function TabsList({ className, ...rest }: ComponentProps<typeof RT.List>) {
  return <RT.List className={cn('flex gap-1 border-b border-border', className)} {...rest} />
}

export function TabsTrigger({ className, ...rest }: ComponentProps<typeof RT.Trigger>) {
  return (
    <RT.Trigger
      className={cn(
        '-mb-px cursor-pointer border-b-2 border-transparent px-4 py-2.5 text-sm text-muted transition',
        'hover:text-text data-[state=active]:border-blue data-[state=active]:text-text',
        className,
      )}
      {...rest}
    />
  )
}

export const TabsContent = RT.Content
