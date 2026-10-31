import { Search, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Badge } from '@/components/ui/Badge'
import { Input } from '@/components/ui/Input'
import { messageOf } from '@/lib/errors'
import { formatNumber } from '@/lib/fa'
import { MAX_TARGET_USERS } from '@/lib/notifications'
import { useUsers } from '@/lib/users'

export interface PickedUser {
  id: string
  username: string
}

/** Search accounts by username (or phone, for owners) and collect the ones to address. */
export function UserPicker({ picked, onChange }: { picked: PickedUser[]; onChange: (u: PickedUser[]) => void }) {
  const [text, setText] = useState('')
  const [q, setQ] = useState('')
  useEffect(() => {
    const t = setTimeout(() => setQ(text.trim()), 300)
    return () => clearTimeout(t)
  }, [text])

  const results = useUsers({ q, filter: 'all', sort: 'created', order: 'desc', page: 1 }, q.length >= 2)
  const full = picked.length >= MAX_TARGET_USERS
  const has = (id: string) => picked.some((p) => p.id === id)

  return (
    <div className="space-y-3">
      <Input
        label="جست‌وجوی کاربر"
        placeholder="نام کاربری…"
        value={text}
        onChange={(e) => setText(e.target.value)}
        startAdornment={<Search className="size-4" aria-hidden />}
        autoComplete="off"
        hint={`${formatNumber(picked.length)} از ${formatNumber(MAX_TARGET_USERS)} کاربر انتخاب شده`}
      />
      {q.length >= 2 && (
        <div className="rounded-lg border border-border bg-raised">
          {results.isError ? (
            <p role="alert" className="px-3 py-2 text-sm text-pink">{messageOf(results.error)}</p>
          ) : results.data && results.data.items.length === 0 ? (
            <p className="px-3 py-2 text-sm text-muted">کاربری پیدا نشد.</p>
          ) : (
            <ul className="divide-y divide-border">
              {results.data?.items.slice(0, 8).map((u) => (
                <li key={u.id}>
                  <button
                    type="button"
                    disabled={u.banned || has(u.id) || full}
                    onClick={() => onChange([...picked, { id: u.id, username: u.username || u.id.slice(0, 8) }])}
                    className="flex w-full cursor-pointer items-center justify-between gap-3 px-3 py-2 text-start text-sm text-text hover:bg-active disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    <span>{u.username || '—'}</span>
                    <span className="text-xs text-muted">{u.banned ? 'مسدود' : has(u.id) ? 'انتخاب شده' : 'افزودن'}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
      {picked.length > 0 && (
        <ul className="flex flex-wrap gap-1.5" aria-label="کاربران انتخاب‌شده">
          {picked.map((p) => (
            <li key={p.id}>
              <Badge tone="blue" className="gap-1.5 ps-1.5">
                <button
                  type="button"
                  aria-label={`حذف ${p.username}`}
                  onClick={() => onChange(picked.filter((x) => x.id !== p.id))}
                  className="grid size-4 cursor-pointer place-items-center rounded-full hover:bg-active"
                >
                  <X className="size-3" aria-hidden />
                </button>
                {p.username}
              </Badge>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
