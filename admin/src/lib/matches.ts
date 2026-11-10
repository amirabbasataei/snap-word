import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { api } from './api'
import { IRAN_OFFSET_MINUTES } from './fa'
import type { MatchKind } from './users'

export const MATCHES_PAGE_SIZE = 25

export type MatchStatusFilter = 'all' | 'active' | 'finished' | 'abandoned' | 'pending'
export type MatchRange = 'all' | 'today' | '7d' | '30d'

export interface MatchListParams {
  q: string
  kind: MatchKind | 'all'
  status: MatchStatusFilter
  range: MatchRange
  page: number
}

export interface MatchPlayer {
  user_id: string
  username: string
  score: number
  is_ai: boolean
  continue_used: boolean
  /** Rating («جام») around this match; null when it was unrated. */
  rating_before: number | null
  rating_after: number | null
  rating_delta: number | null
}

export interface MatchItem {
  id: string
  mode: string
  status: string
  kind: MatchKind
  at: string
  started_at: string | null
  ended_at: string | null
  duration_sec: number | null
  chain_length: number
  /** Empty = draw / no winner recorded. */
  winner_id: string
  players: MatchPlayer[]
}

export interface MatchPage {
  items: MatchItem[]
  total: number
  page: number
  page_size: number
}

export interface MatchDetail extends MatchItem {
  word_chain: string[]
}

/** `YYYY-MM-DD` of the Iran calendar day `daysAgo` days before now. */
export function iranDay(daysAgo: number, now: Date = new Date()): string {
  const shifted = new Date(now.getTime() + IRAN_OFFSET_MINUTES * 60_000 - daysAgo * 86_400_000)
  return shifted.toISOString().slice(0, 10)
}

function listQuery(p: MatchListParams): string {
  const qs = new URLSearchParams()
  if (p.q) qs.set('q', p.q)
  if (p.kind !== 'all') qs.set('kind', p.kind)
  if (p.status !== 'all') qs.set('status', p.status)
  if (p.range !== 'all') {
    qs.set('from', iranDay(p.range === 'today' ? 0 : p.range === '7d' ? 6 : 29))
    qs.set('to', iranDay(0))
  }
  qs.set('page', String(p.page))
  qs.set('page_size', String(MATCHES_PAGE_SIZE))
  return qs.toString()
}

export function useMatches(params: MatchListParams) {
  return useQuery({
    queryKey: ['admin', 'matches', 'list', params],
    queryFn: ({ signal }) => api<MatchPage>(`/matches?${listQuery(params)}`, { signal }),
    placeholderData: keepPreviousData,
  })
}

export function useMatch(id: string) {
  return useQuery({
    queryKey: ['admin', 'matches', 'detail', id],
    queryFn: ({ signal }) => api<MatchDetail>(`/matches/${encodeURIComponent(id)}`, { signal }),
  })
}
