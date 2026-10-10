import { useQuery } from '@tanstack/react-query'
import { api } from './api'

export const DASHBOARD_REFRESH_MS = 60_000
/** Days fetched once and shared by the charts, sparklines and deltas. */
export const DASHBOARD_DAYS = 30

export interface DashboardSummary {
  generated_at: string
  users: { total: number; new_today: number; new_7d: number; premium_active: number }
  coins_in_circulation: number
  matches_today: { solo: number; versus: number; ai_online: number; daily: number; total: number }
  daily_participants_today: number
  unclaimed_rewards: { count: number; coins: number }
  live: {
    rooms: number
    waiting_rooms: number
    active_rooms: number
    connected_players: number
    queue_length: number
  }
  fcm_configured: boolean
}

export interface DashboardDay {
  /** Iran calendar day, `YYYY-MM-DD`. */
  date: string
  signups: number
  matches_solo: number
  matches_versus: number
  matches_ai_online: number
  matches_daily: number
  daily_attempts: number
  coins_claimed: number
}

export function useDashboardSummary() {
  return useQuery({
    queryKey: ['admin', 'dashboard', 'summary'],
    queryFn: ({ signal }) => api<DashboardSummary>('/dashboard/summary', { signal }),
    refetchInterval: DASHBOARD_REFRESH_MS,
  })
}

export function useDashboardTimeseries() {
  return useQuery({
    queryKey: ['admin', 'dashboard', 'timeseries', DASHBOARD_DAYS],
    queryFn: async ({ signal }) =>
      (await api<{ days: DashboardDay[] }>(`/dashboard/timeseries?days=${DASHBOARD_DAYS}`, { signal })).days,
    refetchInterval: DASHBOARD_REFRESH_MS,
  })
}

export function matchesOf(d: DashboardDay): number {
  return d.matches_solo + d.matches_versus + d.matches_ai_online + d.matches_daily
}

/** Sum of `pick` over the last `n` days (today included). */
export function sumLast(days: DashboardDay[], n: number, pick: (d: DashboardDay) => number): number {
  return days.slice(-n).reduce((acc, d) => acc + pick(d), 0)
}

/**
 * Last 7 days vs the 7 before, as a ratio (0.25 = +25%). Undefined when there
 * is no previous-week baseline to compare against.
 */
export function weekOverWeek(days: DashboardDay[], pick: (d: DashboardDay) => number): number | undefined {
  if (days.length < 14) return undefined
  const prev = sumLast(days.slice(0, -7), 7, pick)
  if (prev === 0) return undefined
  return (sumLast(days, 7, pick) - prev) / prev
}
