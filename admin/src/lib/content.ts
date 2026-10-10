import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from './api'
import { withPrefix } from './base'

// ---- taunts ----

export interface Taunt {
  id: string
  text: string
  sort_order: number
}
export interface TauntList {
  items: Taunt[]
  max_text_runes: number
}

/** Same rules as the server (service.tauntIDRe / avatarIDRe) — the server stays the authority. */
export const TAUNT_ID_RE = /^[a-z][a-z0-9_]{1,31}$/
export const AVATAR_ID_RE = /^[a-z][a-z0-9_]{1,23}$/

/** Length in code points, like Go's utf8.RuneCountInString (emoji count as one). */
export function runeCount(s: string): number {
  return Array.from(s).length
}

export function useTaunts() {
  return useQuery({
    queryKey: ['admin', 'content', 'taunts'],
    queryFn: ({ signal }) => api<TauntList>('/taunts', { signal }),
  })
}

export type TauntAction =
  | { type: 'save'; id: string; text: string; reason: string }
  | { type: 'delete'; id: string; reason: string }
  | { type: 'reorder'; ids: string[]; reason: string }

function tauntRequest(a: TauntAction): Promise<unknown> {
  switch (a.type) {
    case 'save':
      return api(`/taunts/${encodeURIComponent(a.id)}`, { method: 'PUT', body: { text: a.text, reason: a.reason } })
    case 'delete':
      return api(`/taunts/${encodeURIComponent(a.id)}`, { method: 'DELETE', body: { reason: a.reason } })
    case 'reorder':
      return api('/taunts/reorder', { method: 'POST', body: { ids: a.ids, reason: a.reason } })
  }
}

export function useTauntAction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: tauntRequest,
    onSettled: () => void qc.invalidateQueries({ queryKey: ['admin', 'content', 'taunts'] }),
  })
}

// ---- avatars ----

export interface AvatarEntry {
  id: string
  sort_order: number
  content_type: string
  bytes: number
  updated_at: string
  users: number
  active_users: number
}
export interface AvatarList {
  items: AvatarEntry[]
  max_bytes: number
  types: string[]
}
export interface AvatarUsage {
  id: string
  users: number
  active_users: number
}

/** `?v=` busts the 1-day browser cache of the public image route after a replace. */
export function avatarImageUrl(a: Pick<AvatarEntry, 'id' | 'updated_at'>): string {
  return withPrefix(`/api/v1/avatars/${encodeURIComponent(a.id)}/image?v=${encodeURIComponent(a.updated_at)}`)
}

export function useAvatars() {
  return useQuery({
    queryKey: ['admin', 'content', 'avatars'],
    queryFn: ({ signal }) => api<AvatarList>('/avatars', { signal }),
  })
}

export function useAvatarUsage(id: string | null) {
  return useQuery({
    queryKey: ['admin', 'content', 'avatar-usage', id],
    queryFn: ({ signal }) => api<AvatarUsage>(`/avatars/${encodeURIComponent(id ?? '')}/usage`, { signal }),
    enabled: id !== null,
    gcTime: 0,
  })
}

export type AvatarAction =
  | { type: 'save'; id: string; file: File; reason: string }
  | { type: 'delete'; id: string; reason: string }

export function useAvatarAction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (a: AvatarAction): Promise<{ users_cleared: number }> => {
      if (a.type === 'delete') {
        return api<{ id: string; users_cleared: number }>(`/avatars/${encodeURIComponent(a.id)}`, {
          method: 'DELETE', body: { reason: a.reason },
        })
      }
      const form = new FormData()
      form.set('image', a.file)
      form.set('reason', a.reason)
      await api(`/avatars/${encodeURIComponent(a.id)}`, { method: 'PUT', body: form })
      return { users_cleared: 0 }
    },
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: ['admin', 'content', 'avatars'] })
      void qc.invalidateQueries({ queryKey: ['admin', 'users'] })
    },
  })
}

// ---- daily challenge ----

export type DayStatus = 'past' | 'today' | 'future'

export interface DailyDay {
  date: string
  day_number: number
  start_letter: string
  generated: boolean
  customized: boolean
  status: DayStatus
  editable: boolean
  players: number
  attempts: number
  best_score: number
}
export interface DailyList {
  from: string
  to: string
  today: string
  eligible_letters: string[]
  rows: DailyDay[]
}

export type PayoutState = 'not_due' | 'no_players' | 'paid' | 'pending' | 'missed'

// `attempts` here is the list of attempts; the day's attempt count is `stats.attempts`.
export interface DailyDetail extends Omit<DailyDay, 'attempts'> {
  seed: number
  eligible_letters: string[]
  stats: { players: number; attempts: number; retries: number; best_score: number; avg_score: number }
  board: { rank: number; user_id: string; username: string; score: number; chain_length: number; banned: boolean }[]
  attempts: {
    user_id: string
    username: string
    attempt: number
    score: number
    chain_length: number
    word_chain: string[]
    completed_at: string
  }[]
  payout: {
    state: PayoutState
    flagged: boolean
    rewards: { done_created: number; done_claimed: number; rank_created: number; rank_claimed: number; coins: number }
  }
}

export function useDailyList() {
  return useQuery({
    queryKey: ['admin', 'content', 'daily', 'list'],
    queryFn: ({ signal }) => api<DailyList>('/daily', { signal }),
  })
}

export function useDailyDetail(date: string) {
  return useQuery({
    queryKey: ['admin', 'content', 'daily', 'detail', date],
    queryFn: ({ signal }) => api<DailyDetail>(`/daily/${encodeURIComponent(date)}`, { signal }),
  })
}

export function useSetStartLetter() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: { date: string; letter: string; reason: string }) =>
      api(`/daily/${encodeURIComponent(v.date)}`, { method: 'PATCH', body: { start_letter: v.letter, reason: v.reason } }),
    onSettled: () => void qc.invalidateQueries({ queryKey: ['admin', 'content', 'daily'] }),
  })
}

// ---- leaderboards ----

export interface BoardEntry {
  rank: number
  user_id: string
  username: string
  score: number
  avatar_id: string
}
export interface Board {
  entries: BoardEntry[]
  limit: number
  resets_at?: string
}
export interface WeeklyRewards {
  weeks: {
    payout_date: string
    rewards: { rank: number; user_id: string; username: string; coins: number; awarded_at: string; banned: boolean }[]
  }[]
  prizes: number[]
}

export function useBoard(kind: 'weekly' | 'alltime', limit: number) {
  return useQuery({
    queryKey: ['admin', 'content', 'board', kind, limit],
    queryFn: ({ signal }) => api<Board>(`/leaderboards/${kind}?limit=${limit}`, { signal }),
    refetchInterval: 60_000,
  })
}

export function useWeeklyRewards() {
  return useQuery({
    queryKey: ['admin', 'content', 'board', 'rewards'],
    queryFn: ({ signal }) => api<WeeklyRewards>('/leaderboards/rewards', { signal }),
  })
}
