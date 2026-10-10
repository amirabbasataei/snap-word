import { Link } from 'react-router-dom'
import { Card, CardBody } from '@/components/ui/Card'

export function NotFound() {
  return (
    <Card>
      <CardBody className="flex flex-col items-center gap-3 py-16 text-center">
        <p className="tabular text-4xl font-bold text-muted">۴۰۴</p>
        <p className="text-base text-text">صفحه‌ای که دنبالش هستید پیدا نشد.</p>
        <Link to="/" className="text-sm text-blue hover:underline">
          بازگشت به داشبورد
        </Link>
      </CardBody>
    </Card>
  )
}
