import type { LucideIcon } from 'lucide-react'
import { Card, CardBody } from '@/components/ui/Card'
import { Badge } from '@/components/ui/Badge'

interface Props {
  title: string
  stage: string
  icon: LucideIcon
}

export function Placeholder({ title, stage, icon: Icon }: Props) {
  return (
    <div>
      <h1 className="mb-6 text-xl font-semibold text-text">{title}</h1>
      <Card>
        <CardBody className="flex flex-col items-center gap-3 py-16 text-center">
          <span className="grid size-14 place-items-center rounded-full bg-active text-muted">
            <Icon className="size-7" aria-hidden />
          </span>
          <p className="text-base font-medium text-text">این بخش هنوز ساخته نشده است</p>
          <Badge tone="blue" dir="ltr">
            {stage}
          </Badge>
        </CardBody>
      </Card>
    </div>
  )
}
