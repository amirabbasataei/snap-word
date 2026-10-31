import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from './api'

export type Channel = 'push' | 'inapp'
export type AudienceType = 'all' | 'segment' | 'users'

export interface Segment {
  premium: 'any' | 'yes' | 'no'
  activity: 'any' | 'active' | 'inactive'
  days: number
  joined_within_days: number
  push: 'any' | 'enabled' | 'disabled'
}

export interface Audience {
  type: AudienceType
  segment?: Segment
  user_ids?: string[]
}

/** The state of one account's push permission, best device wins. */
export type PushState = 'granted' | 'unknown' | 'denied' | 'not_determined' | 'none'

/** Deep links the app understands; the server whitelists the same set. */
export const ROUTE_OPTIONS: { value: string; label: string }[] = [
  { value: '', label: 'فقط باز شدن برنامه' },
  { value: '/home', label: 'صفحهٔ اصلی' },
  { value: '/daily', label: 'چالش روزانه' },
  { value: '/friends', label: 'دوستان' },
  { value: '/leaderboard', label: 'جدول امتیازات' },
  { value: '/rewards', label: 'جایزه‌ها' },
  { value: '/profile', label: 'پروفایل' },
  { value: '/messages', label: 'اعلان‌ها (صندوق پیام)' },
]
export const ROUTE_LABEL: Record<string, string> = Object.fromEntries(ROUTE_OPTIONS.map((o) => [o.value, o.label]))

export const TITLE_MAX = 60
export const BODY_MAX = 240
export const MAX_TARGET_USERS = 200

export const PUSH_STATE_LABEL: Record<PushState, string> = {
  granted: 'مجاز',
  unknown: 'نامشخص (نسخهٔ قدیمی برنامه)',
  denied: 'ردشده',
  not_determined: 'هنوز پرسیده نشده',
  none: 'بدون دستگاه',
}

export interface Preview {
  recipients: number
  fcm_configured: boolean
  push: { deliverable: number; granted: number; unknown: number; denied: number; not_determined: number; none: number }
}

export interface Reach {
  fcm_configured: boolean
  users: number
  deliverable: number
  granted: number
  unknown: number
  denied: number
  not_determined: number
  none: number
  devices: { platform: 'android' | 'ios'; permission: string; count: number }[] | null
}

export interface Campaign {
  id: string
  title: string
  body: string
  route: string
  push: boolean
  inapp: boolean
  audience: Audience
  created_by: string
  created_at: string
  recipients: number
  inapp_delivered: number
  inapp_read: number
  push_status: 'none' | 'sending' | 'done' | 'failed' | 'interrupted'
  push_users: number
  push_devices: number
  push_sent: number
  push_failed: number
  push_removed: number
  push_finished_at: string | null
}

export interface CampaignDetail extends Campaign {
  users: { id: string; username: string; read_at: string | null }[]
}

export interface CampaignPage {
  items: Campaign[]
  total: number
  page: number
  page_size: number
}

export const HISTORY_PAGE_SIZE = 20

export interface SendInput {
  title: string
  body: string
  route: string
  channels: Channel[]
  audience: Audience
}

const KEY = ['admin', 'notifications'] as const

export function useReach() {
  return useQuery({
    queryKey: [...KEY, 'reach'],
    queryFn: ({ signal }) => api<Reach>('/notifications/reach', { signal }),
  })
}

/** Sizes the audience as the operator edits it. `enabled=false` skips the call (e.g. no users picked yet). */
export function usePreview(audience: Audience, enabled: boolean) {
  return useQuery({
    queryKey: [...KEY, 'preview', audience],
    queryFn: ({ signal }) => api<Preview>('/notifications/preview', { method: 'POST', body: { audience }, signal }),
    enabled,
    placeholderData: keepPreviousData,
    staleTime: 15_000,
  })
}

export function useCampaigns(page: number) {
  return useQuery({
    queryKey: [...KEY, 'list', page],
    queryFn: ({ signal }) => api<CampaignPage>(`/notifications?page=${page}&page_size=${HISTORY_PAGE_SIZE}`, { signal }),
    placeholderData: keepPreviousData,
    // A push still being delivered finishes within moments; keep the row fresh.
    refetchInterval: (q) => (q.state.data?.items.some((c) => c.push_status === 'sending') ? 3000 : false),
  })
}

export function useCampaign(id: string | null) {
  return useQuery({
    queryKey: [...KEY, 'one', id],
    queryFn: ({ signal }) => api<CampaignDetail>(`/notifications/${id}`, { signal }),
    enabled: id !== null,
    refetchInterval: (q) => (q.state.data?.push_status === 'sending' ? 3000 : false),
  })
}

export function useSendNotification() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: SendInput) => api<Campaign>('/notifications', { method: 'POST', body: v }),
    onSuccess: () => qc.invalidateQueries({ queryKey: KEY }),
  })
}

/** One-line Persian description of who a campaign went to. */
export function describeAudience(a: Audience): string {
  if (a.type === 'all') return 'همهٔ کاربران'
  if (a.type === 'users') return `${a.user_ids?.length ?? 0} کاربر مشخص`
  const s = a.segment
  if (!s) return 'گروه'
  const parts: string[] = []
  if (s.premium === 'yes') parts.push('دارای اشتراک ویژه')
  if (s.premium === 'no') parts.push('بدون اشتراک ویژه')
  if (s.activity === 'active') parts.push(`فعال در ${s.days} روز اخیر`)
  if (s.activity === 'inactive') parts.push(`غیرفعال بیش از ${s.days} روز`)
  if (s.joined_within_days > 0) parts.push(`عضو شده در ${s.joined_within_days} روز اخیر`)
  if (s.push === 'enabled') parts.push('اعلان فعال')
  if (s.push === 'disabled') parts.push('بدون اعلان فعال')
  return parts.length ? parts.join(' · ') : 'همهٔ کاربران (گروه)'
}
