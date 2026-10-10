import { ArrowDown, ArrowUp, ChevronRight, ChevronLeft, Inbox } from 'lucide-react'
import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'
import { formatNumber } from '@/lib/fa'
import { Button } from './Button'
import { Skeleton } from './Skeleton'

export interface Column<T> {
  key: string
  header: ReactNode
  cell: (row: T) => ReactNode
  sortable?: boolean
  /** Extra classes on both th and td (width, hiding on mobile, …). */
  className?: string
}

export interface SortState {
  key: string
  dir: 'asc' | 'desc'
}

interface Props<T> {
  columns: Column<T>[]
  /** `undefined` while the first load is in flight. */
  rows: T[] | undefined
  rowKey: (row: T) => string
  loading?: boolean
  /** Persian error text; shows a retry state instead of rows. */
  error?: string | null
  onRetry?: () => void
  emptyText?: string
  // Server-side pagination (1-based page).
  page?: number
  pageSize?: number
  total?: number
  onPageChange?: (page: number) => void
  // Server-side sorting.
  sort?: SortState | null
  onSortChange?: (sort: SortState) => void
}

export function DataTable<T>({
  columns, rows, rowKey, loading, error, onRetry, emptyText = 'موردی برای نمایش نیست.',
  page = 1, pageSize = 20, total, onPageChange, sort, onSortChange,
}: Props<T>) {
  const showSkeleton = loading || rows === undefined
  const pages = total !== undefined ? Math.max(1, Math.ceil(total / pageSize)) : 1

  function toggleSort(key: string) {
    if (!onSortChange) return
    onSortChange({ key, dir: sort?.key === key && sort.dir === 'desc' ? 'asc' : 'desc' })
  }

  return (
    <div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-max border-collapse text-sm">
          <thead>
            <tr className="border-b border-border text-start text-xs text-muted">
              {columns.map((c) => {
                const active = sort?.key === c.key
                return (
                  <th
                    key={c.key}
                    scope="col"
                    aria-sort={active ? (sort.dir === 'asc' ? 'ascending' : 'descending') : undefined}
                    className={cn('px-4 py-3 text-start font-medium', c.className)}
                  >
                    {c.sortable && onSortChange ? (
                      <button
                        type="button"
                        onClick={() => toggleSort(c.key)}
                        className="inline-flex cursor-pointer items-center gap-1 hover:text-text"
                      >
                        {c.header}
                        {active && (sort.dir === 'asc' ? <ArrowUp className="size-3.5" aria-hidden /> : <ArrowDown className="size-3.5" aria-hidden />)}
                      </button>
                    ) : (
                      c.header
                    )}
                  </th>
                )
              })}
            </tr>
          </thead>
          <tbody>
            {error ? null : showSkeleton ? (
              Array.from({ length: 5 }, (_, i) => (
                <tr key={i} className="border-b border-border last:border-0">
                  {columns.map((c) => (
                    <td key={c.key} className={cn('px-4 py-3.5', c.className)}>
                      <Skeleton className="h-4 w-full max-w-32" />
                    </td>
                  ))}
                </tr>
              ))
            ) : (
              rows.map((row) => (
                <tr key={rowKey(row)} className="border-b border-border transition last:border-0 hover:bg-raised">
                  {columns.map((c) => (
                    <td key={c.key} className={cn('tabular px-4 py-3 text-text', c.className)}>
                      {c.cell(row)}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {error && (
        <div role="alert" className="flex flex-col items-center gap-3 px-4 py-10 text-center">
          <p className="text-sm text-pink">{error}</p>
          {onRetry && (
            <Button variant="secondary" size="sm" onClick={onRetry}>
              تلاش دوباره
            </Button>
          )}
        </div>
      )}
      {!error && !showSkeleton && rows.length === 0 && (
        <div className="flex flex-col items-center gap-2 px-4 py-10 text-center text-muted">
          <Inbox className="size-8" aria-hidden />
          <p className="text-sm">{emptyText}</p>
        </div>
      )}

      {onPageChange && total !== undefined && total > 0 && (
        <nav aria-label="صفحه‌بندی" className="flex items-center justify-between gap-3 border-t border-border px-4 py-3 text-xs text-muted">
          <span className="tabular">
            {formatNumber(total)} مورد · صفحه {formatNumber(page)} از {formatNumber(pages)}
          </span>
          <div className="flex gap-1.5">
            <Button variant="secondary" size="sm" disabled={page <= 1} onClick={() => onPageChange(page - 1)} aria-label="صفحه قبل">
              <ChevronRight className="size-4" aria-hidden />
            </Button>
            <Button variant="secondary" size="sm" disabled={page >= pages} onClick={() => onPageChange(page + 1)} aria-label="صفحه بعد">
              <ChevronLeft className="size-4" aria-hidden />
            </Button>
          </div>
        </nav>
      )}
    </div>
  )
}
