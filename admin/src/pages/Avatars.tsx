import { ImagePlus, RefreshCw, Trash2, Users } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { useAuth } from '@/auth/AuthContext'
import { Avatar } from '@/components/ui/Avatar'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardHeader } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { ReasonDialog } from '@/components/ui/ReasonDialog'
import { Skeleton } from '@/components/ui/Skeleton'
import { useToast } from '@/components/ui/Toast'
import { roleAtLeast } from '@/layout/nav'
import {
  AVATAR_ID_RE, avatarImageUrl, useAvatarAction, useAvatars, useAvatarUsage,
  type AvatarEntry, type AvatarList,
} from '@/lib/content'
import { messageOf } from '@/lib/errors'
import { formatNumber } from '@/lib/fa'

/** Why a picked file cannot be uploaded, in Persian; null when it is fine. Mirrors the server's checks (which still decide). */
export function validateAvatarFile(file: { type: string; size: number }, limits: Pick<AvatarList, 'max_bytes' | 'types'>): string | null {
  if (!limits.types.includes(file.type)) return 'فقط تصویر PNG، JPEG یا WebP پذیرفته می‌شود.'
  if (file.size === 0) return 'فایل خالی است.'
  if (file.size > limits.max_bytes) {
    return `حجم تصویر ${formatNumber(Math.ceil(file.size / 1024))} کیلوبایت است؛ حداکثر مجاز ${formatNumber(Math.floor(limits.max_bytes / 1024))} کیلوبایت است.`
  }
  return null
}

type Dialog =
  | { kind: 'upload'; replace: AvatarEntry | null }
  | { kind: 'delete'; avatar: AvatarEntry }

export function Avatars() {
  const { admin } = useAuth()
  const canEdit = admin ? roleAtLeast(admin.role, 'operator') : false
  const query = useAvatars()
  const [dialog, setDialog] = useState<Dialog | null>(null)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">آواتارها</h1>
        <p className="text-xs text-muted">
          تصویرهایی که بازیکنان دارای اشتراک ویژه برای پروفایل انتخاب می‌کنند. تصویر جایگزین‌شده تا یک روز ممکن است در دستگاه‌ها قدیمی بماند.
        </p>
      </div>

      <Card>
        <CardHeader
          title={`فهرست آواتارها${query.data ? ` (${formatNumber(query.data.items.length)})` : ''}`}
          actions={
            canEdit && (
              <Button size="sm" onClick={() => setDialog({ kind: 'upload', replace: null })} disabled={!query.data}>
                <ImagePlus className="size-4" aria-hidden />
                آواتار جدید
              </Button>
            )
          }
        />
        {query.isPending ? (
          <div className="grid grid-cols-2 gap-4 p-5 sm:grid-cols-3 lg:grid-cols-4" aria-busy>
            {Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="h-52 w-full" />)}
          </div>
        ) : query.isError ? (
          <div role="alert" className="flex flex-col items-center gap-3 px-4 py-10 text-center">
            <p className="text-sm text-pink">{messageOf(query.error)}</p>
            <Button variant="secondary" size="sm" onClick={() => void query.refetch()}>تلاش دوباره</Button>
          </div>
        ) : query.data.items.length === 0 ? (
          <p className="px-4 py-10 text-center text-sm text-muted">هنوز آواتاری ثبت نشده است.</p>
        ) : (
          <ul className="grid grid-cols-2 gap-4 p-5 sm:grid-cols-3 lg:grid-cols-4">
            {query.data.items.map((a) => (
              <li key={a.id} className="flex flex-col gap-3 rounded-card border border-border bg-raised p-3">
                <img
                  src={avatarImageUrl(a)}
                  alt={`آواتار ${a.id}`}
                  loading="lazy"
                  className="aspect-square w-full rounded-lg bg-surface object-cover"
                />
                <div className="min-w-0 space-y-1.5">
                  <p dir="ltr" className="truncate text-start text-sm font-medium text-text">{a.id}</p>
                  <p className="tabular text-xs text-muted">
                    {formatNumber(Math.max(1, Math.round(a.bytes / 1024)))} کیلوبایت · {a.content_type.replace('image/', '').toUpperCase()}
                  </p>
                  <Badge tone={a.users > 0 ? 'blue' : 'neutral'} className="gap-1">
                    <Users className="size-3" aria-hidden />
                    {formatNumber(a.users)} کاربر
                  </Badge>
                </div>
                {canEdit && (
                  <div className="mt-auto flex gap-2">
                    <Button size="sm" variant="secondary" className="flex-1" onClick={() => setDialog({ kind: 'upload', replace: a })}>
                      <RefreshCw className="size-3.5" aria-hidden />
                      جایگزینی
                    </Button>
                    <Button size="sm" variant="secondary" aria-label={`حذف آواتار ${a.id}`} onClick={() => setDialog({ kind: 'delete', avatar: a })}>
                      <Trash2 className="size-3.5 text-pink" aria-hidden />
                    </Button>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </Card>

      {dialog?.kind === 'upload' && query.data && (
        <UploadDialog
          replace={dialog.replace}
          limits={query.data}
          existing={query.data.items.map((a) => a.id)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'delete' && <DeleteDialog avatar={dialog.avatar} onClose={() => setDialog(null)} />}
    </div>
  )
}

function UploadDialog({
  replace, limits, existing, onClose,
}: {
  replace: AvatarEntry | null
  limits: AvatarList
  existing: string[]
  onClose: () => void
}) {
  const act = useAvatarAction()
  const { toast } = useToast()
  const [id, setId] = useState(replace?.id ?? '')
  const [file, setFile] = useState<File | null>(null)
  const [fileError, setFileError] = useState<string | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const input = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (!file) return setPreview(null)
    const url = URL.createObjectURL(file)
    setPreview(url)
    return () => URL.revokeObjectURL(url)
  }, [file])

  function pick(f: File | undefined) {
    if (!f) return
    const problem = validateAvatarFile(f, limits)
    setFileError(problem)
    setFile(problem ? null : f)
    if (problem && input.current) input.current.value = ''
  }

  const idOk = AVATAR_ID_RE.test(id)
  const taken = !replace && existing.includes(id)
  return (
    <ReasonDialog
      open
      onOpenChange={(o) => !o && onClose()}
      title={replace ? `جایگزینی آواتار ${replace.id}` : 'آواتار جدید'}
      description={`PNG، JPEG یا WebP، حداکثر ${formatNumber(Math.floor(limits.max_bytes / 1024))} کیلوبایت. تصویر مربع بهتر نمایش داده می‌شود.`}
      confirmLabel={replace ? 'جایگزین کن' : 'بارگذاری'}
      valid={idOk && !taken && file !== null}
      onSubmit={async (reason) => {
        if (!file) return
        await act.mutateAsync({ type: 'save', id, file, reason })
        toast({ title: replace ? 'آواتار جایگزین شد.' : 'آواتار افزوده شد.' })
      }}
    >
      {!replace && (
        <Input
          label="شناسه"
          dir="ltr"
          className="text-start"
          value={id}
          onChange={(e) => setId(e.target.value)}
          autoComplete="off"
          placeholder="lion"
          error={id && !idOk ? 'فقط حرف کوچک انگلیسی، عدد و _ (۲ تا ۲۴ نویسه، شروع با حرف).' : taken ? 'این شناسه از قبل وجود دارد؛ برای تعویض تصویر از «جایگزینی» استفاده کنید.' : undefined}
          hint="بازیکنان آن را نمی‌بینند و پس از ساخت قابل تغییر نیست."
        />
      )}
      <div className="flex flex-col gap-1.5">
        <label htmlFor="avatar-file" className="text-sm font-medium text-text">تصویر</label>
        <input
          ref={input}
          id="avatar-file"
          type="file"
          accept={limits.types.join(',')}
          onChange={(e) => pick(e.target.files?.[0])}
          aria-invalid={fileError ? true : undefined}
          aria-describedby={fileError ? 'avatar-file-err' : undefined}
          className="block w-full cursor-pointer rounded-lg border border-border bg-raised text-sm text-muted file:me-3 file:cursor-pointer file:border-0 file:bg-active file:px-3 file:py-2.5 file:text-sm file:text-text"
        />
        {fileError && <p id="avatar-file-err" role="alert" className="text-xs text-pink">{fileError}</p>}
      </div>
      {preview && file && (
        <div className="flex items-center gap-3">
          <Avatar name={id || '؟'} src={preview} className="size-16" />
          <p className="tabular text-xs text-muted">{formatNumber(Math.max(1, Math.round(file.size / 1024)))} کیلوبایت</p>
        </div>
      )}
    </ReasonDialog>
  )
}

function DeleteDialog({ avatar, onClose }: { avatar: AvatarEntry; onClose: () => void }) {
  const act = useAvatarAction()
  const { toast } = useToast()
  // Fresh count at the moment of confirmation (the grid's number may be a while old).
  const usage = useAvatarUsage(avatar.id)

  let note: string
  if (usage.isPending) note = 'در حال شمارش کاربران…'
  else if (usage.isError) note = `شمارش کاربران ممکن نشد (${messageOf(usage.error)})`
  else if (usage.data.users === 0) note = 'هیچ کاربری این آواتار را انتخاب نکرده است.'
  else {
    note = `${formatNumber(usage.data.users)} کاربر این آواتار را انتخاب کرده‌اند`
      + (usage.data.active_users > 0 ? ` (${formatNumber(usage.data.active_users)} نفر با اشتراک فعال آن را می‌بینند)` : ' (هیچ‌کدام اشتراک فعال ندارند)')
      + '. با حذف، آواتار همهٔ آن‌ها پاک می‌شود و حرف اول نامشان نمایش داده می‌شود.'
  }

  return (
    <ReasonDialog
      open
      onOpenChange={(o) => !o && onClose()}
      title={`حذف آواتار ${avatar.id}`}
      description="حذف آواتار قابل بازگشت نیست؛ برای برگرداندن باید تصویر دوباره بارگذاری شود."
      confirmLabel="حذف"
      danger
      requireText={avatar.id}
      valid={!usage.isPending}
      onSubmit={async (reason) => {
        const out = await act.mutateAsync({ type: 'delete', id: avatar.id, reason })
        toast({ title: 'آواتار حذف شد.', description: out.users_cleared > 0 ? `آواتار ${formatNumber(out.users_cleared)} کاربر پاک شد.` : undefined })
      }}
    >
      <div className="flex items-center gap-3">
        <img src={avatarImageUrl(avatar)} alt="" className="size-14 rounded-lg bg-raised object-cover" />
        <p role="status" className="text-sm text-text">{note}</p>
      </div>
    </ReasonDialog>
  )
}
