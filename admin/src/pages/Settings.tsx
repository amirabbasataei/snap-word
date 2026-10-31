import { MessageSquareOff, MessageSquareText, TriangleAlert } from 'lucide-react'
import { useState } from 'react'
import { useAuth } from '@/auth/AuthContext'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardHeader } from '@/components/ui/Card'
import { ReasonDialog } from '@/components/ui/ReasonDialog'
import { Skeleton } from '@/components/ui/Skeleton'
import { useToast } from '@/components/ui/Toast'
import { roleAtLeast } from '@/layout/nav'
import { messageOf } from '@/lib/errors'
import { toFa, formatJalaliDateTime } from '@/lib/fa'
import { useOtpStatus, useSetOtpSms } from '@/lib/settings'

export function Settings() {
  const { admin } = useAuth()
  const isOwner = admin ? roleAtLeast(admin.role, 'owner') : false
  const query = useOtpStatus()
  const set = useSetOtpSms()
  const { toast } = useToast()
  const [confirm, setConfirm] = useState<'off' | 'on' | null>(null)

  const st = query.data

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">تنظیمات</h1>
        <p className="text-xs text-muted">کلیدهایی که بدون انتشار نسخهٔ جدید روی سرور اثر می‌گذارند.</p>
      </div>

      <Card>
        <CardHeader title="پیامک کد ورود (OTP)" />
        {query.isPending ? (
          <div className="space-y-3 p-5" aria-busy>
            <Skeleton className="h-6 w-48" />
            <Skeleton className="h-10 w-full" />
          </div>
        ) : query.isError || !st ? (
          <div role="alert" className="flex flex-col items-center gap-3 px-4 py-10 text-center">
            <p className="text-sm text-pink">{messageOf(query.error)}</p>
            <Button variant="secondary" size="sm" onClick={() => void query.refetch()}>تلاش دوباره</Button>
          </div>
        ) : (
          <div className="space-y-4 p-5">
            <div className="flex flex-wrap items-center gap-2">
              {st.bypass_active ? (
                <Badge tone="orange">
                  <MessageSquareOff className="me-1 size-3.5" aria-hidden />
                  پیامک غیرفعال — کد {toFa(st.dev_code)} پذیرفته می‌شود
                </Badge>
              ) : (
                <Badge tone="green">
                  <MessageSquareText className="me-1 size-3.5" aria-hidden />
                  پیامک فعال (کاوه‌نگار)
                </Badge>
              )}
              {!st.provider_configured && <Badge tone="pink">کلید کاوه‌نگار روی سرور تنظیم نشده</Badge>}
            </div>

            <p className="text-sm text-muted">
              وقتی ارسال پیامک فعال است، هر ورود با یک کد ۴ رقمی تصادفی از طریق قالب تأییدیهٔ کاوه‌نگار (Verify Lookup) پیامک می‌شود.
              وقتی غیرفعال است هیچ پیامکی ارسال نمی‌شود و کد ثابت {toFa(st.dev_code)} برای ورود هر شماره‌ای پذیرفته می‌شود.
            </p>

            {st.updated_at && (
              <p className="text-xs text-muted">
                آخرین تغییر: {formatJalaliDateTime(st.updated_at)}{st.updated_by ? ` · ${st.updated_by}` : ''}
              </p>
            )}

            {!st.provider_configured && (
              <p className="text-xs text-muted">
                تا وقتی کلید API روی سرور تنظیم نشده، ارسال پیامک ممکن نیست و کد {toFa(st.dev_code)} همیشه معتبر است؛ این کلید آن را تغییر نمی‌دهد.
              </p>
            )}

            {isOwner ? (
              <div className="flex justify-start">
                {st.sms_enabled ? (
                  <Button variant="danger" onClick={() => setConfirm('off')}>غیرفعال‌کردن ارسال پیامک</Button>
                ) : (
                  <Button onClick={() => setConfirm('on')}>فعال‌کردن ارسال پیامک</Button>
                )}
              </div>
            ) : (
              <p className="text-xs text-muted">فقط مالک می‌تواند این تنظیم را تغییر دهد.</p>
            )}
          </div>
        )}
      </Card>

      {confirm === 'off' && (
        <ReasonDialog
          open
          onOpenChange={(o) => !o && setConfirm(null)}
          title="غیرفعال‌کردن ارسال پیامک"
          description="با غیرفعال‌شدن، هر کسی که شمارهٔ دیگری را بداند می‌تواند با کد ۱۱۱۱ وارد حساب آن شماره شود. فقط برای آزمایش یا زمانی که سرویس پیامک در دسترس نیست استفاده کنید و بعد از آن دوباره فعالش کنید."
          confirmLabel="غیرفعال‌کردن"
          danger
          requireText="غیرفعال"
          onSubmit={async (reason) => {
            await set.mutateAsync({ enabled: false, reason })
            toast({ title: 'ارسال پیامک غیرفعال شد؛ کد ۱۱۱۱ پذیرفته می‌شود.' })
          }}
        >
          <p className="flex items-start gap-2 rounded-lg border border-orange px-3 py-2 text-sm text-orange">
            <TriangleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
            این کار ورود را برای همهٔ حساب‌ها بی‌امن می‌کند.
          </p>
        </ReasonDialog>
      )}
      {confirm === 'on' && (
        <ReasonDialog
          open
          onOpenChange={(o) => !o && setConfirm(null)}
          title="فعال‌کردن ارسال پیامک"
          description="کدهای ورود دوباره با پیامک ارسال می‌شوند و کد ۱۱۱۱ دیگر پذیرفته نمی‌شود."
          confirmLabel="فعال‌کردن"
          onSubmit={async (reason) => {
            await set.mutateAsync({ enabled: true, reason })
            toast({ title: 'ارسال پیامک فعال شد.' })
          }}
        />
      )}
    </div>
  )
}
