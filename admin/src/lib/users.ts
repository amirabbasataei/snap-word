import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from './api'

export type UserFilter = 'all' | 'premium' | 'banned' | 'new'
export type UserSortKey = 'created' | 'coins' | 'xp' | 'matches' | 'username'

export interface UserListParams {
  q: string
  filter: UserFilter
  sort: UserSortKey
  order: 'asc' | 'desc'
  page: number
}
export const USERS_PAGE_SIZE = 25

export interface UserItem {
  id: string
  username: string
  /** Already masked server-side unless the viewer is an owner. */
  phone: string
  phone_masked: boolean
  coins: number
  xp: number
  level: number
  total_matches: number
  premium: boolean
  premium_until: string | null
  avatar_id: string
  created_at: string
  banned: boolean
  banned_at: string | null
}

export interface UserPage {
  items: UserItem[]
  total: number
  page: number
  page_size: number
}

export type MatchKind = 'solo' | 'versus' | 'ai' | 'daily'

export interface UserDetail extends UserItem {
  referral_code: string
  ban_reason: string
  joined_at: string | null
  xp_in_level: number
  xp_for_next: number
  stats: {
    total_matches: number
    wins: number
    longest_word: string
    best_match_streak: number
    daily_streak: number
    longest_daily_streak: number
    last_played_date: string | null
    total_score: number
  }
  friends_count: number
  device_tokens: number
  referrer: { id: string; username: string } | null
  referred_count: number
  referred: { id: string; username: string; created_at: string }[]
  rewards: {
    id: string
    kind: string
    detail: string
    coins: number
    claimed: boolean
    claimed_at: string | null
    created_at: string
  }[]
  matches: {
    id: string
    mode: string
    status: string
    kind: MatchKind
    score: number
    won: boolean
    at: string
    ended_at: string | null
    player_count: number
  }[]
  daily_attempts: { date: string; attempt: number; score: number; chain_length: number; completed_at: string }[]
}

export function avatarUrl(u: { avatar_id: string; premium: boolean }): string | undefined {
  // A lapsed subscription hides the avatar in the app, so the panel mirrors that.
  return u.avatar_id && u.premium ? `/api/v1/avatars/${encodeURIComponent(u.avatar_id)}/image` : undefined
}

function listQuery(p: UserListParams): string {
  const qs = new URLSearchParams()
  if (p.q) qs.set('q', p.q)
  if (p.filter !== 'all') qs.set('filter', p.filter)
  qs.set('sort', p.sort)
  qs.set('order', p.order)
  qs.set('page', String(p.page))
  qs.set('page_size', String(USERS_PAGE_SIZE))
  return qs.toString()
}

export function useUsers(params: UserListParams) {
  return useQuery({
    queryKey: ['admin', 'users', 'list', params],
    queryFn: ({ signal }) => api<UserPage>(`/users?${listQuery(params)}`, { signal }),
    placeholderData: keepPreviousData,
  })
}

export function useUser(id: string) {
  return useQuery({
    queryKey: ['admin', 'users', 'detail', id],
    queryFn: ({ signal }) => api<UserDetail>(`/users/${encodeURIComponent(id)}`, { signal }),
  })
}

export type UserAction =
  | { type: 'coins'; mode: 'direct' | 'reward'; amount: number; reason: string }
  | { type: 'premium_grant'; days: number; reason: string }
  | { type: 'premium_revoke'; reason: string }
  | { type: 'rename'; username: string; reason: string }
  | { type: 'avatar_clear'; reason: string }
  | { type: 'ban'; reason: string }
  | { type: 'unban'; reason: string }

function request(id: string, a: UserAction): Promise<unknown> {
  const base = `/users/${encodeURIComponent(id)}`
  switch (a.type) {
    case 'coins':
      return api(`${base}/coins`, { method: 'POST', body: { mode: a.mode, amount: a.amount, reason: a.reason } })
    case 'premium_grant':
      return api(`${base}/premium`, { method: 'POST', body: { action: 'grant', days: a.days, reason: a.reason } })
    case 'premium_revoke':
      return api(`${base}/premium`, { method: 'POST', body: { action: 'revoke', reason: a.reason } })
    case 'rename':
      return api(`${base}/username`, { method: 'PATCH', body: { username: a.username, reason: a.reason } })
    case 'avatar_clear':
      return api(`${base}/avatar/clear`, { method: 'POST', body: { reason: a.reason } })
    case 'ban':
      return api(`${base}/ban`, { method: 'POST', body: { reason: a.reason } })
    case 'unban':
      return api(`${base}/unban`, { method: 'POST', body: { reason: a.reason } })
  }
}

/** Runs one audited action and refreshes everything that shows the user. */
export function useUserAction(id: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: UserAction) => request(id, a),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['admin', 'users'] })
      void qc.invalidateQueries({ queryKey: ['admin', 'dashboard'] })
    },
  })
}
