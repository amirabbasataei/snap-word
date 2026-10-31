import { Send, TriangleAlert } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { Dialog } from '@/components/ui/Dialog'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { useToast } from '@/components/ui/Toast'
import { cn } from '@/lib/cn'
import { messageOf } from '@/lib/errors'
import { formatNumber, fromFa } from '@/lib/fa'
import {
  BODY_MAX, describeAudience, ROUTE_OPTIONS, TITLE_MAX, usePreview, useSendNotification,
  type Audience, type AudienceType, type Channel, type Segment,
} from '@/lib/notifications'
import { useUser } from '@/lib/users'
import { InboxCard, PushBanner } from './parts'
import { UserPicker, type PickedUser } from './UserPicker'

const AUDIENCES: { value: AudienceType; label: string; hint: string }[] = [
  { value: 'all', label: 'همهٔ کاربران', hint: 'همهٔ حساب‌های ثبت‌نام‌شده و غیرمسدود' },
  { value: 'segment', label: 'یک گروه', hint: 'بر اساس اشتراک، فعالیت، تازگی عضویت یا وضعیت اعلان' },
  { value: 'users', label: 'کاربران مشخص', hint: 'یک یا چند حساب را خودتان انتخاب کنید' },
]

const PREMIUM_OPTIONS = [
  { value: 'any', label: 'فرقی نمی‌کند' },
  { value: 'yes', label: 'دارای اشتراک ویژه' },
  { value: 'no', label: 'بدون اشتراک ویژه' },
]
const ACTIVITY_OPTIONS = [
  { value: 'any', label: 'فرقی نمی‌کند' },
  { value: 'active', label: 'بازی کرده در …روز اخیر' },
  { value: 'inactive', label: 'بازی نکرده در …روز اخیر' },
]
const PUSH_OPTIONS = [
  { value: 'any', label: 'فرقی نمی‌کند' },
  { value: 'enabled', label: 'اعلان فعال دارند' },
  { value: 'disabled', label: 'اعلان فعال ندارند' },
]

function parseDays(text: string, max: number): number | null {
  const n = Number(fromFa(text.trim()))
  return Number.isInteger(n) && n >= 1 && n <= max ? n : null
}

export function Compose({ canSend, onSent }: { canSend: boolean; onSent: () => void }) {
  const { toast } = useToast()
  const [sp] = useSearchParams()
  const userParam = sp.get('user') ?? ''

  const [channels, setChannels] = useState<Record<Channel, boolean>>({ push: true, inapp: true })
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [route, setRoute] = useState('')
  const [audType, setAudType] = useState<AudienceType>('all')
  const [premium, setPremium] = useState<Segment['premium']>('any')
  const [activity, setActivity] = useState<Segment['activity']>('any')
  const [activityDays, setActivityDays] = useState('30')
  const [joinedText, setJoinedText] = useState('')
  const [pushFilter, setPushFilter] = useState<Segment['push']>('any')
  const [picked, setPicked] = useState<PickedUser[]>([])
  const [confirming, setConfirming] = useState(false)
  const [typed, setTyped] = useState('')
  const [error, setError] = useState<string | null>(null)
  const send = useSendNotification()

  // «ارسال پیام» on a user's page opens this tab with ?user=<id>.
  const prefill = useUser(userParam, userParam !== '')
  useEffect(() => {
    const u = prefill.data
    if (u && u.id === userParam) {
      setAudType('users')
      setPicked((cur) => (cur.some((p) => p.id === u.id) ? cur : [{ id: u.id, username: u.username || u.id.slice(0, 8) }]))
    }
  }, [prefill.data, userParam])

  const days = parseDays(activityDays, 365)
  const joined = joinedText.trim() === '' ? 0 : parseDays(joinedText, 3650)
  const segmentValid = (activity === 'any' || days !== null) && joined !== null

  const audience: Audience = useMemo(() => {
    if (audType === 'all') return { type: 'all' }
    if (audType === 'users') return { type: 'users', user_ids: picked.map((p) => p.id) }
    return {
      type: 'segment',
      segment: { premium, activity, days: activity === 'any' ? 0 : (days ?? 0), joined_within_days: joined ?? 0, push: pushFilter },
    }
  }, [audType, picked, premium, activity, days, joined, pushFilter])
  const audienceValid = audType === 'all' || (audType === 'users' ? picked.length > 0 : segmentValid)

  const preview = usePreview(audience, audienceValid)
  const p = preview.data
  const wantsPush = channels.push
  const wantsInapp = channels.inapp
  const titleLen = Array.from(title.trim()).length
  const bodyLen = Array.from(body.trim()).length

  const problem = !canSend
    ? null
    : !wantsPush && !wantsInapp
      ? 'حداقل یک کانال را انتخاب کنید.'
      : p && !p.fcm_configured && wantsPush
        ? 'ارسال اعلان فوری روی سرور تنظیم نشده است؛ کانال «اعلان فوری» را بردارید.'
        : p && p.recipients === 0
          ? 'هیچ کاربری با این مخاطبان مطابقت ندارد.'
          : p && wantsPush && !wantsInapp && p.push.deliverable === 0
            ? 'هیچ‌یک از این مخاطبان اعلان را فعال نکرده‌اند؛ پیام درون‌برنامه هم بفرستید.'
            : null

  const ready =
    canSend && titleLen > 0 && titleLen <= TITLE_MAX && bodyLen > 0 && bodyLen <= BODY_MAX &&
    (wantsPush || wantsInapp) && audienceValid && !!p && !problem

  const needsTyped = audType === 'all'
  const confirmWord = 'ارسال'

  async function submit() {
    setError(null)
    try {
      await send.mutateAsync({
        title: title.trim(), body: body.trim(), route,
        channels: (['push', 'inapp'] as Channel[]).filter((c) => channels[c]), audience,
      })
      toast({ title: 'اعلان ارسال شد.' })
      setConfirming(false)
      setTyped('')
      setTitle('')
      setBody('')
      onSent()
    } catch (e) {
      setError(messageOf(e))
    }
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
      <div className="space-y-6">
        <Card>
          <CardHeader title="پیام" />
          <CardBody className="space-y-4">
            <fieldset className="space-y-2">
              <legend className="mb-1 text-sm font-medium text-text">کانال ارسال</legend>
              <CheckRow
                checked={channels.push}
                onChange={(v) => setChannels((c) => ({ ...c, push: v }))}
                label="اعلان فوری (Push)"
                hint="روی گوشی نمایش داده می‌شود؛ فقط به کسانی می‌رسد که اجازهٔ اعلان داده‌اند."
              />
              <CheckRow
                checked={channels.inapp}
                onChange={(v) => setChannels((c) => ({ ...c, inapp: v }))}
                label="پیام درون‌برنامه"
                hint="در صندوق اعلان‌های برنامه می‌ماند تا کاربر آن را ببیند؛ برای همهٔ حساب‌ها کار می‌کند."
              />
            </fieldset>
            <Input
              label="عنوان"
              value={title}
              maxLength={TITLE_MAX}
              onChange={(e) => setTitle(e.target.value)}
              disabled={!canSend}
              hint={`${formatNumber(titleLen)} از ${formatNumber(TITLE_MAX)}`}
            />
            <div className="flex flex-col gap-1.5">
              <label htmlFor="notif-body" className="text-sm font-medium text-text">متن پیام</label>
              <textarea
                id="notif-body"
                value={body}
                maxLength={BODY_MAX}
                rows={4}
                disabled={!canSend}
                onChange={(e) => setBody(e.target.value)}
                className="w-full resize-y rounded-lg border border-border bg-raised px-3 py-2 text-sm text-text transition focus:border-blue focus:outline-none disabled:opacity-60"
              />
              <p className="text-xs text-muted">{formatNumber(bodyLen)} از {formatNumber(BODY_MAX)}</p>
            </div>
            <div className="flex flex-col gap-1.5">
              <span className="text-sm font-medium text-text">با لمس پیام، کجا باز شود؟</span>
              <Select value={route} onValueChange={setRoute} options={ROUTE_OPTIONS} label="مقصد" className="w-full" disabled={!canSend} />
            </div>
          </CardBody>
        </Card>

        <Card>
          <CardHeader title="مخاطبان" />
          <CardBody className="space-y-4">
            <div role="radiogroup" aria-label="نوع مخاطب" className="grid gap-2 sm:grid-cols-3">
              {AUDIENCES.map((a) => (
                <button
                  key={a.value}
                  type="button"
                  role="radio"
                  aria-checked={audType === a.value}
                  disabled={!canSend}
                  onClick={() => setAudType(a.value)}
                  className={cn(
                    'cursor-pointer rounded-lg border px-3 py-2.5 text-start transition disabled:cursor-not-allowed disabled:opacity-60',
                    audType === a.value ? 'border-blue bg-raised' : 'border-border hover:bg-raised',
                  )}
                >
                  <span className="block text-sm font-medium text-text">{a.label}</span>
                  <span className="mt-0.5 block text-xs text-muted">{a.hint}</span>
                </button>
              ))}
            </div>

            {audType === 'segment' && (
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="flex flex-col gap-1.5">
                  <span className="text-sm font-medium text-text">اشتراک ویژه</span>
                  <Select value={premium} onValueChange={(v) => setPremium(v as Segment['premium'])} options={PREMIUM_OPTIONS} label="اشتراک ویژه" className="w-full" />
                </div>
                <div className="flex flex-col gap-1.5">
                  <span className="text-sm font-medium text-text">وضعیت اعلان</span>
                  <Select value={pushFilter} onValueChange={(v) => setPushFilter(v as Segment['push'])} options={PUSH_OPTIONS} label="وضعیت اعلان" className="w-full" />
                </div>
                <div className="flex flex-col gap-1.5">
                  <span className="text-sm font-medium text-text">فعالیت</span>
                  <Select value={activity} onValueChange={(v) => setActivity(v as Segment['activity'])} options={ACTIVITY_OPTIONS} label="فعالیت" className="w-full" />
                </div>
                {activity !== 'any' && (
                  <Input
                    label="تعداد روز"
                    inputMode="numeric"
                    value={activityDays}
                    onChange={(e) => setActivityDays(e.target.value)}
                    error={days === null ? 'عددی بین ۱ تا ۳۶۵' : undefined}
                  />
                )}
                <Input
                  label="عضو شده در … روز اخیر (اختیاری)"
                  inputMode="numeric"
                  value={joinedText}
                  onChange={(e) => setJoinedText(e.target.value)}
                  error={joined === null ? 'عددی بین ۱ تا ۳۶۵۰ یا خالی' : undefined}
                />
              </div>
            )}

            {audType === 'users' && <UserPicker picked={picked} onChange={setPicked} />}

            <AudienceSummary audience={audience} valid={audienceValid} loading={preview.isFetching} error={preview.isError ? messageOf(preview.error) : null} preview={p} wantsPush={wantsPush} />
          </CardBody>
        </Card>
      </div>

      <div className="space-y-6 lg:sticky lg:top-4 lg:self-start">
        <Card>
          <CardHeader title="پیش‌نمایش" />
          <CardBody className="space-y-3">
            {wantsPush && <PushBanner title={title} body={body} />}
            {wantsInapp && <InboxCard title={title} body={body} />}
            {!wantsPush && !wantsInapp && <p className="text-sm text-muted">یک کانال انتخاب کنید.</p>}
          </CardBody>
        </Card>

        {canSend ? (
          <div className="space-y-2">
            {problem && (
              <p role="alert" className="flex items-start gap-2 rounded-lg border border-orange px-3 py-2 text-sm text-orange">
                <TriangleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
                {problem}
              </p>
            )}
            <Button size="lg" className="w-full" disabled={!ready} onClick={() => { setError(null); setConfirming(true) }}>
              <Send className="size-4" aria-hidden />
              ارسال…
            </Button>
          </div>
        ) : (
          <p className="text-xs text-muted">فقط اپراتور و مالک می‌توانند اعلان ارسال کنند.</p>
        )}
      </div>

      {confirming && p && (
        <Dialog
          open
          onOpenChange={(o) => { if (!o && !send.isPending) { setConfirming(false); setTyped(''); setError(null) } }}
          title="ارسال اعلان؟"
          description="پس از ارسال، پیام قابل بازگرداندن نیست."
          footer={
            <>
              <Button variant="secondary" disabled={send.isPending} onClick={() => setConfirming(false)}>انصراف</Button>
              <Button loading={send.isPending} disabled={needsTyped && typed.trim() !== confirmWord} onClick={() => void submit()}>
                ارسال
              </Button>
            </>
          }
        >
          <div className="space-y-3 text-sm">
            <p className="font-medium text-text">{title.trim()}</p>
            <p className="text-muted">{body.trim()}</p>
            <ul className="list-disc space-y-1 ps-5 text-text">
              <li>مخاطبان: {describeAudience(audience)} — {formatNumber(p.recipients)} حساب</li>
              {wantsInapp && <li>پیام درون‌برنامه برای {formatNumber(p.recipients)} حساب</li>}
              {wantsPush && <li>اعلان فوری برای {formatNumber(p.push.deliverable)} حساب دارای اجازه</li>}
            </ul>
            {needsTyped && (
              <Input
                label={`برای تأیید «${confirmWord}» را تایپ کنید`}
                value={typed}
                onChange={(e) => setTyped(e.target.value)}
                autoComplete="off"
              />
            )}
            {error && <p role="alert" className="rounded-lg border border-pink px-3 py-2 text-pink">{error}</p>}
          </div>
        </Dialog>
      )}
    </div>
  )
}

function CheckRow({ checked, onChange, label, hint }: { checked: boolean; onChange: (v: boolean) => void; label: string; hint: string }) {
  return (
    <label className="flex cursor-pointer items-start gap-3 rounded-lg border border-border px-3 py-2.5 hover:bg-raised">
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="mt-0.5 size-4 cursor-pointer accent-[var(--blue)]"
      />
      <span>
        <span className="block text-sm font-medium text-text">{label}</span>
        <span className="block text-xs text-muted">{hint}</span>
      </span>
    </label>
  )
}

/** Live size of the chosen audience and how much of it a push can reach. */
function AudienceSummary({
  audience, valid, loading, error, preview, wantsPush,
}: {
  audience: Audience
  valid: boolean
  loading: boolean
  error: string | null
  preview: ReturnType<typeof usePreview>['data']
  wantsPush: boolean
}) {
  if (!valid) return <p className="text-sm text-muted">مخاطبان را کامل کنید تا تعداد گیرندگان نمایش داده شود.</p>
  if (error) return <p role="alert" className="text-sm text-pink">{error}</p>
  if (!preview) return <p className="text-sm text-muted">در حال محاسبه…</p>
  const pu = preview.push
  return (
    <div className={cn('rounded-lg border border-border bg-raised px-3.5 py-3 text-sm', loading && 'opacity-70')} aria-live="polite">
      <p className="text-text">
        <b>{formatNumber(preview.recipients)}</b> حساب با «{describeAudience(audience)}» مطابقت دارد
        <span className="text-muted"> — پیام درون‌برنامه به همهٔ آن‌ها می‌رسد.</span>
      </p>
      {wantsPush && (
        <p className="mt-1.5 text-muted">
          اعلان فوری برای <b className="text-text">{formatNumber(pu.deliverable)}</b> حساب قابل ارسال است
          {pu.deliverable > 0 && ` (${formatNumber(pu.granted)} مجاز${pu.unknown ? `، ${formatNumber(pu.unknown)} نامشخص` : ''})`}.
          {' '}
          {formatNumber(pu.denied)} نفر رد کرده‌اند، {formatNumber(pu.not_determined)} نفر هنوز پرسیده نشده و {formatNumber(pu.none)} نفر دستگاهی ثبت نکرده‌اند؛ این‌ها فقط پیام درون‌برنامه می‌گیرند.
        </p>
      )}
    </div>
  )
}
