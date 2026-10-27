import { ArrowRight } from 'lucide-react'
import { Link, useParams } from 'react-router-dom'
import { Timeline } from './analytics/Timeline'

/** One install's raw event history — also where a guest's timeline lives. */
export function InstallTimeline() {
  const { id = '' } = useParams()
  return (
    <div className="space-y-5">
      <Link to="/analytics" className="inline-flex items-center gap-1.5 text-sm text-muted hover:text-text">
        <ArrowRight className="size-4" aria-hidden />
        تحلیل رفتار
      </Link>
      <div>
        <h1 className="text-xl font-semibold text-text">رفتار یک دستگاه</h1>
        <p className="tabular text-xs text-muted" dir="ltr">{id}</p>
      </div>
      <Timeline kind="installs" id={id} />
    </div>
  )
}
