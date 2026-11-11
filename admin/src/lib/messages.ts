import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { api } from './api'
import { iranDay, type MatchRange } from './matches'

export const MESSAGES_PAGE_SIZE = 25

export type MessageKind = 'preset' | 'custom'
export type MessageKindFilter = MessageKind | 'all'

export interface MessageListParams {
  q: string
  kind: MessageKindFilter
  range: MatchRange
  page: number
}

export interface PlayerMessage {
  id: string
  at: string
  kind: MessageKind
  /** Catalogue id of a preset; empty for free text. */
  taunt_id: string
  text: string
  /** Empty when the match is unknown. */
  match_id: string
  sender_id: string
  sender_name: string
  sender_banned: boolean
  opponent_id: string
  opponent_name: string
}

export interface MessagePage {
  items: PlayerMessage[]
  total: number
  page: number
  page_size: number
}

function listQuery(p: MessageListParams): string {
  const qs = new URLSearchParams()
  if (p.q) qs.set('q', p.q)
  if (p.kind !== 'all') qs.set('kind', p.kind)
  if (p.range !== 'all') {
    qs.set('from', iranDay(p.range === 'today' ? 0 : p.range === '7d' ? 6 : 29))
    qs.set('to', iranDay(0))
  }
  qs.set('page', String(p.page))
  qs.set('page_size', String(MESSAGES_PAGE_SIZE))
  return qs.toString()
}

export function useMessages(params: MessageListParams) {
  return useQuery({
    queryKey: ['admin', 'messages', 'list', params],
    queryFn: ({ signal }) => api<MessagePage>(`/messages?${listQuery(params)}`, { signal }),
    placeholderData: keepPreviousData,
  })
}
