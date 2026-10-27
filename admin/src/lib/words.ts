import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from './api'

export type WordKind = 'add' | 'remove'
export type WordStatusFilter = 'pending' | 'approved' | 'rejected' | 'all'
export type WordSort = 'reporters' | 'recent'
/** What an approved removal does: drop the word or only keep the AI from playing it. */
export type RemoveOutcome = 'remove' | 'ai_block'
export type WordOverrideAction = 'add' | 'remove' | 'ai_block' | 'ai_unblock'

export const WORDS_PAGE_SIZE = 50

export interface WordSuggestion {
  id: number
  word: string
  kind: WordKind
  status: 'pending' | 'approved' | 'rejected'
  outcome: string
  reporters: number
  not_a_word: number
  inappropriate: number
  review_note: string
  reviewed_by: string
  reviewed_at: string | null
  created_at: string
  last_reported_at: string
  in_dictionary: boolean
  ai_blocked: boolean
  known_rejected: boolean
  warnings: string[]
}

export interface WordQueue {
  items: WordSuggestion[]
  total: number
  page: number
  page_size: number
  pending: Record<WordKind, number>
}

export interface WordQueueParams {
  kind: WordKind
  status: WordStatusFilter
  q: string
  sort: WordSort
  page: number
}

/** Hints from the server's policy check; the reviewer still decides. */
export const WARNING_LABEL: Record<string, string> = {
  suffix_of_known: 'شکل جمع/صفتِ یک کلمهٔ موجود',
  verb_prefix: 'صرف فعل (می‌… / نمی‌…)',
  ends_in_hamza: 'پایان با «ء»',
}

export const STATUS_LABEL: Record<string, string> = {
  pending: 'در انتظار',
  approved: 'تأییدشده',
  rejected: 'ردشده',
}

/** External dictionary search for a word, to help the reviewer decide. */
export function lookupUrl(word: string): string {
  return `https://www.vajehyab.com/?q=${encodeURIComponent(word)}`
}

const KEY = ['admin', 'words'] as const

export function useWordQueue(p: WordQueueParams) {
  const qs = new URLSearchParams({
    kind: p.kind, status: p.status, sort: p.sort, page: String(p.page), page_size: String(WORDS_PAGE_SIZE),
  })
  if (p.q) qs.set('q', p.q)
  return useQuery({
    queryKey: [...KEY, 'queue', p],
    queryFn: ({ signal }) => api<WordQueue>(`/words/suggestions?${qs}`, { signal }),
    placeholderData: keepPreviousData,
  })
}

export type WordDecision =
  | { type: 'approve'; id: number; outcome?: RemoveOutcome; note: string }
  | { type: 'reject'; id: number; note: string }
  | { type: 'bulk'; ids: number[]; action: 'approve' | 'reject'; note: string }

export interface BulkResult {
  done: number
  failed: { id: number; error: string }[]
}

function decide(d: WordDecision): Promise<unknown> {
  switch (d.type) {
    case 'approve':
      return api(`/words/suggestions/${d.id}/approve`, { method: 'POST', body: { outcome: d.outcome ?? '', note: d.note } })
    case 'reject':
      return api(`/words/suggestions/${d.id}/reject`, { method: 'POST', body: { note: d.note } })
    case 'bulk':
      return api<BulkResult>('/words/bulk', { method: 'POST', body: { ids: d.ids, action: d.action, note: d.note } })
  }
}

export function useWordDecision() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: decide,
    onSettled: () => void qc.invalidateQueries({ queryKey: KEY }),
  })
}

export interface WordMiss {
  word: string
  count: number
  in_dictionary: boolean
  known_rejected: boolean
  warnings: string[]
}

export function useMisses() {
  return useQuery({
    queryKey: [...KEY, 'misses'],
    queryFn: ({ signal }) => api<{ items: WordMiss[] }>('/dictionary/misses?limit=100', { signal }),
  })
}

export interface WordLookup {
  word: string
  in_dictionary: boolean
  in_base: boolean
  ai_blocked: boolean
  known_rejected: boolean
  warnings: string[]
  suggestions: WordSuggestion[]
}

export function useWordLookup(word: string) {
  return useQuery({
    queryKey: [...KEY, 'lookup', word],
    queryFn: ({ signal }) => api<WordLookup>(`/dictionary/lookup?word=${encodeURIComponent(word)}`, { signal }),
    enabled: word !== '',
  })
}

export interface WordExport {
  seq: number
  added: string[]
  removed: string[]
  ai_blocked: string[]
}

export function useWordExport(enabled: boolean) {
  return useQuery({
    queryKey: [...KEY, 'export'],
    queryFn: ({ signal }) => api<WordExport>('/dictionary/export', { signal }),
    enabled,
  })
}

export type DictAction =
  | { type: 'set'; word: string; action: WordOverrideAction; reason: string }
  | { type: 'dismiss'; word: string }

function dictRequest(a: DictAction): Promise<unknown> {
  return a.type === 'set'
    ? api('/dictionary/words', { method: 'POST', body: { word: a.word, action: a.action, reason: a.reason } })
    : api('/dictionary/misses/dismiss', { method: 'POST', body: { word: a.word } })
}

export function useDictAction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: dictRequest,
    onSettled: () => void qc.invalidateQueries({ queryKey: KEY }),
  })
}
