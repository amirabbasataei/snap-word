import { Link } from 'react-router-dom'
import { Badge } from '@/components/ui/Badge'
import type { MatchPlayer } from '@/lib/matches'
import { formatNumber } from '@/lib/fa'

/** Status as a pill: finished green, running blue, the rest neutral. */
export function MatchStatusBadge({ status, label }: { status: string; label: string }) {
  return <Badge tone={status === 'finished' ? 'green' : status === 'active' ? 'blue' : 'neutral'}>{label}</Badge>
}

/** «۲:۰۵» / «۱ ساعت و ۲ دقیقه» style duration in Persian digits. */
export function formatDuration(sec: number | null): string {
  if (sec == null) return '—'
  if (sec < 60) return `${formatNumber(sec)} ثانیه`
  const m = Math.floor(sec / 60)
  const s = sec % 60
  if (m < 60) return s ? `${formatNumber(m)} دقیقه و ${formatNumber(s)} ثانیه` : `${formatNumber(m)} دقیقه`
  const h = Math.floor(m / 60)
  return `${formatNumber(h)} ساعت و ${formatNumber(m % 60)} دقیقه`
}

/** One player: linked name (AI is plain text), score, trophy/continue marks. */
export function PlayerLine({ p, winner }: { p: MatchPlayer; winner: boolean }) {
  return (
    <span className="inline-flex flex-wrap items-center gap-x-2 gap-y-1">
      {p.is_ai ? (
        <span className="text-muted">هوش مصنوعی</span>
      ) : (
        <Link to={`/users/${p.user_id}`} className="font-medium hover:text-blue">{p.username || 'بدون نام'}</Link>
      )}
      <span className="tabular text-muted">{formatNumber(p.score)}</span>
      {winner && <Badge tone="yellow">برنده</Badge>}
      {p.continue_used && <Badge tone="orange">ادامه</Badge>}
    </span>
  )
}
