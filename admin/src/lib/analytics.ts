import { useQuery } from '@tanstack/react-query'
import { api } from './api'

export const ANALYTICS_REFRESH_MS = 5 * 60_000
export const ANALYTICS_RANGES = [7, 14, 30, 90] as const
export const RETENTION_MAX_OFFSET = 30

/** Persian names for the fixed event vocabulary (mirrors service.AnalyticsEventNames). */
export const EVENT_LABEL: Record<string, string> = {
  app_open: 'باز کردن برنامه',
  session_start: 'شروع نشست',
  session_end: 'پایان نشست',
  screen_view: 'مشاهدهٔ صفحه',
  signup: 'ثبت‌نام',
  login: 'ورود',
  identify: 'شناسایی حساب',
  game_start: 'شروع بازی',
  game_end: 'پایان بازی',
  continue_used: 'ادامه با سکه یا تبلیغ',
  powerup_used: 'استفاده از آیتم',
  daily_start: 'شروع چالش روزانه',
  daily_end: 'پایان چالش روزانه',
  queue_join: 'ورود به صف حریف',
  queue_leave: 'خروج از صف حریف',
  match_found: 'پیدا شدن حریف',
  ad_watched: 'تماشای تبلیغ',
  purchase_tap: 'لمس خرید',
  share: 'اشتراک‌گذاری',
  friend_request: 'درخواست دوستی',
  challenge_sent: 'ارسال چالش',
  word_suggest: 'پیشنهاد کلمه',
}
export const EVENT_NAMES = Object.keys(EVENT_LABEL)

export function eventLabel(name: string): string {
  return EVENT_LABEL[name] ?? name
}

const SCREEN_LABEL: Record<string, string> = {
  '/home': 'خانه',
  '/leaderboard': 'جدول',
  '/friends': 'دوستان',
  '/profile': 'من',
  '/game': 'بازی',
  '/lobby': 'میدان',
  '/daily': 'چالش روزانه',
  '/daily/board': 'جدول امروز',
  '/messages': 'اعلان‌ها',
  '/rewards': 'پاداش‌ها',
  '/login': 'ورود (شماره)',
  '/login/otp': 'ورود (کد)',
}

export function screenLabel(screen: string): string {
  return SCREEN_LABEL[screen] ?? screen
}

export interface AnalyticsOverviewDay {
  day: string
  active: number
  active_users: number
  new_installs: number
  sessions: number
}

export interface AnalyticsOverview {
  generated_at: string
  dau: number
  wau: number
  mau: number
  /** DAU / MAU, 0..1. */
  stickiness: number
  new_installs_today: number
  new_installs_7d: number
  avg_session_ms: number
  total_installs: number
  linked_installs: number
  days: AnalyticsOverviewDay[]
}

export interface RetentionCohort {
  cohort: string
  size: number
  /** Index = days after the cohort day; null = that day has not happened yet. */
  retained: (number | null)[]
}

export interface RetentionResult {
  by: 'install' | 'user'
  cohorts: RetentionCohort[]
}

export interface FunnelStep {
  name: string
  count: number
  pct_of_first: number
  pct_of_prev: number
}

export interface ScreenRow {
  screen: string
  views: number
  avg_ms: number
  median_ms: number
}

export interface EventCountRow {
  day: string
  name: string
  count: number
  uniques: number
}

export interface TimelineItem {
  ts: string
  name: string
  screen?: string
  props?: Record<string, unknown>
  session_id?: string
  install_id: string
  platform?: string
  app_version?: string
}

export interface TimelineInstall {
  install_id: string
  user_id?: string
  first_seen: string
  last_seen: string
  platform?: string
  app_version?: string
}

export interface Timeline {
  installs: TimelineInstall[]
  events: TimelineItem[]
  next_before?: string
}

const key = (...parts: unknown[]) => ['admin', 'analytics', ...parts]

export function useAnalyticsOverview(days: number) {
  return useQuery({
    queryKey: key('overview', days),
    queryFn: ({ signal }) => api<AnalyticsOverview>(`/analytics/overview?days=${days}`, { signal }),
    refetchInterval: ANALYTICS_REFRESH_MS,
  })
}

/** Cohorts over the last `days` days (the server caches this for five minutes). */
export function useRetention(days: number, by: 'install' | 'user') {
  return useQuery({
    queryKey: key('retention', days, by),
    queryFn: ({ signal }) => {
      const to = new Date()
      const from = new Date(to.getTime() - (days - 1) * 86_400_000)
      return api<RetentionResult>(`/analytics/retention?from=${ymd(from)}&to=${ymd(to)}&by=${by}`, { signal })
    },
  })
}

export function useFunnel(steps: string[], days: number) {
  return useQuery({
    queryKey: key('funnel', steps.join(','), days),
    queryFn: async ({ signal }) =>
      (await api<{ steps: FunnelStep[] }>(`/analytics/funnel?steps=${steps.join(',')}&days=${days}`, { signal })).steps,
    enabled: steps.length >= 2,
  })
}

export function useScreens(days: number) {
  return useQuery({
    queryKey: key('screens', days),
    queryFn: async ({ signal }) => (await api<{ screens: ScreenRow[] }>(`/analytics/screens?days=${days}`, { signal })).screens,
  })
}

export function useEventCounts(days: number) {
  return useQuery({
    queryKey: key('events', days),
    queryFn: async ({ signal }) => (await api<{ events: EventCountRow[] }>(`/analytics/events?days=${days}`, { signal })).events,
  })
}

export function useTimeline(kind: 'users' | 'installs', id: string) {
  return useQuery({
    queryKey: key('timeline', kind, id),
    queryFn: ({ signal }) => api<Timeline>(`/analytics/${kind}/${id}/timeline?limit=200`, { signal }),
  })
}

/** Older events for the timeline's «بیشتر» button. */
export function fetchTimelinePage(kind: 'users' | 'installs', id: string, before: string) {
  return api<Timeline>(`/analytics/${kind}/${id}/timeline?limit=200&before=${encodeURIComponent(before)}`)
}

/** The last `n` Iran calendar days, oldest first, ending today. */
export function lastDays(n: number, now: Date = new Date()): string[] {
  return Array.from({ length: n }, (_, i) => ymd(new Date(now.getTime() - (n - 1 - i) * 86_400_000)))
}

function ymd(d: Date): string {
  // Iran calendar day (UTC+03:30), matching the server's rollup days.
  const iran = new Date(d.getTime() + (3 * 60 + 30) * 60_000)
  return iran.toISOString().slice(0, 10)
}

/** `83_000` → «۱ دقیقه و ۲۳ ثانیه»; under a minute → seconds. */
export function formatDuration(ms: number, toFaFn: (n: number) => string): string {
  const s = Math.round(ms / 1000)
  if (s < 60) return `${toFaFn(s)} ثانیه`
  const m = Math.floor(s / 60)
  const rest = s % 60
  return rest === 0 ? `${toFaFn(m)} دقیقه` : `${toFaFn(m)} دقیقه و ${toFaFn(rest)} ثانیه`
}

/** Heat-map fill: share of the cohort still active, as a 0..1 blend strength. */
export function retentionShare(cohort: RetentionCohort, offset: number): number | null {
  const v = cohort.retained[offset]
  if (v == null || cohort.size === 0) return null
  return v / cohort.size
}

/** Weighted average retention per offset across cohorts that have reached it. */
export function averageRetention(cohorts: RetentionCohort[]): (number | null)[] {
  return Array.from({ length: RETENTION_MAX_OFFSET + 1 }, (_, off) => {
    let kept = 0
    let size = 0
    for (const c of cohorts) {
      const v = c.retained[off]
      if (v == null) continue
      kept += v
      size += c.size
    }
    return size === 0 ? null : kept / size
  })
}
