import { BellOff, BellRing, CircleHelp, Smartphone, TriangleAlert, UserX } from 'lucide-react'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { Skeleton } from '@/components/ui/Skeleton'
import { StatCard } from '@/components/ui/StatCard'
import { messageOf } from '@/lib/errors'
import { formatNumber, formatPercent } from '@/lib/fa'
import { useReach } from '@/lib/notifications'

const PERMISSION_LABEL: Record<string, string> = {
  granted: 'مجاز',
  denied: 'ردشده',
  not_determined: 'پرسیده نشده',
  unknown: 'نامشخص (نسخهٔ قدیمی)',
}

/**
 * Answers «who has allowed push notifications?» for the whole player base.
 * An account is counted once, by its best device.
 */
export function Reach() {
  const query = useReach()
  if (query.isPending) {
    return (
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5" aria-busy>
        {Array.from({ length: 5 }, (_, i) => <Skeleton key={i} className="h-28 w-full" />)}
      </div>
    )
  }
  if (query.isError || !query.data) {
    return (
      <Card>
        <div role="alert" className="flex flex-col items-center gap-3 px-4 py-10 text-center">
          <p className="text-sm text-pink">{messageOf(query.error)}</p>
          <Button variant="secondary" size="sm" onClick={() => void query.refetch()}>تلاش دوباره</Button>
        </div>
      </Card>
    )
  }
  const r = query.data
  const share = (n: number) => (r.users > 0 ? formatPercent(n / r.users) : '—')
  return (
    <div className="space-y-6">
      {!r.fcm_configured && (
        <p role="alert" className="flex items-start gap-2 rounded-lg border border-orange px-3 py-2 text-sm text-orange">
          <TriangleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
          کلید Firebase روی سرور تنظیم نشده است؛ اعلان فوری ارسال نمی‌شود و فقط پیام درون‌برنامه کار می‌کند.
        </p>
      )}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard title="اعلان مجاز" value={formatNumber(r.granted)} caption={share(r.granted)} icon={BellRing} tone="green" />
        <StatCard title="نامشخص" value={formatNumber(r.unknown)} caption="نسخهٔ قدیمی برنامه" icon={CircleHelp} tone="yellow" />
        <StatCard title="رد کرده‌اند" value={formatNumber(r.denied)} caption={share(r.denied)} icon={BellOff} tone="pink" />
        <StatCard title="هنوز پرسیده نشده" value={formatNumber(r.not_determined)} caption={share(r.not_determined)} icon={Smartphone} tone="orange" />
        <StatCard title="بدون دستگاه" value={formatNumber(r.none)} caption={share(r.none)} icon={UserX} tone="blue" />
      </div>

      <Card>
        <CardHeader title="چطور خوانده شود؟" />
        <CardBody className="space-y-2 text-sm text-muted">
          <p>
            از میان <b className="text-text">{formatNumber(r.users)}</b> حساب ثبت‌نام‌شدهٔ فعال،{' '}
            <b className="text-text">{formatNumber(r.deliverable)}</b> حساب اعلان فوری را دریافت می‌کند (مجاز + نامشخص).
            بقیه فقط پیام درون‌برنامه می‌بینند.
          </p>
          <ul className="list-disc space-y-1 ps-5">
            <li><b className="text-text">مجاز:</b> برنامه به سرور گزارش داده که سیستم‌عامل اجازهٔ نمایش اعلان را داده است.</li>
            <li><b className="text-text">رد کرده‌اند:</b> اجازه را نداده‌اند یا بعداً از تنظیمات گوشی بسته‌اند؛ برای آن‌ها اعلان فوری فرستاده نمی‌شود.</li>
            <li><b className="text-text">هنوز پرسیده نشده:</b> درخواست اجازه فقط یک‌بار و هنگام اولین ورود به تب دوستان نمایش داده می‌شود.</li>
            <li><b className="text-text">نامشخص:</b> دستگاه‌هایی که پیش از افزوده‌شدن این گزارش ثبت شده‌اند؛ با اولین ورود به نسخهٔ جدید برنامه روشن می‌شوند. به آن‌ها اعلان فرستاده می‌شود.</li>
            <li><b className="text-text">بدون دستگاه:</b> مهمان‌ها و حساب‌هایی که هرگز با حساب وارد‌شده برنامه را باز نکرده‌اند هم اینجا هستند.</li>
          </ul>
        </CardBody>
      </Card>

      {r.devices && r.devices.length > 0 && (
        <Card>
          <CardHeader title="دستگاه‌های ثبت‌شده" />
          <CardBody>
            <ul className="divide-y divide-border">
              {r.devices.map((d) => (
                <li key={`${d.platform}-${d.permission}`} className="flex items-center justify-between py-2 text-sm">
                  <span className="inline-flex items-center gap-2">
                    <Badge tone="neutral">{d.platform === 'ios' ? 'iOS' : 'اندروید'}</Badge>
                    {PERMISSION_LABEL[d.permission] ?? d.permission}
                  </span>
                  <span className="tabular text-text">{formatNumber(d.count)}</span>
                </li>
              ))}
            </ul>
          </CardBody>
        </Card>
      )}
    </div>
  )
}
