import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { ConfirmDialog } from './Dialog'
import { DataTable } from './DataTable'
import { StatCard } from './StatCard'
import { Activity } from 'lucide-react'

const cols = [{ key: 'n', header: 'نام', cell: (r: { n: string }) => r.n }]

describe('DataTable', () => {
  it('shows skeleton rows while loading, then rows', () => {
    const { rerender } = render(<DataTable columns={cols} rows={undefined} rowKey={(r) => r.n} />)
    expect(screen.queryByText('علی')).not.toBeInTheDocument()
    rerender(<DataTable columns={cols} rows={[{ n: 'علی' }]} rowKey={(r) => r.n} />)
    expect(screen.getByText('علی')).toBeInTheDocument()
  })

  it('shows the empty state', () => {
    render(<DataTable columns={cols} rows={[]} rowKey={(r) => r.n} emptyText="خالی است" />)
    expect(screen.getByText('خالی است')).toBeInTheDocument()
  })

  it('shows the error with a working retry', async () => {
    const retry = vi.fn()
    render(<DataTable columns={cols} rows={[]} rowKey={(r) => r.n} error="خطا" onRetry={retry} />)
    expect(screen.getByRole('alert')).toHaveTextContent('خطا')
    await userEvent.click(screen.getByRole('button', { name: 'تلاش دوباره' }))
    expect(retry).toHaveBeenCalled()
  })

  it('paginates with Persian digits and disables edges', async () => {
    const onPage = vi.fn()
    render(<DataTable columns={cols} rows={[{ n: 'a' }]} rowKey={(r) => r.n} page={1} pageSize={10} total={25} onPageChange={onPage} />)
    expect(screen.getByText(/۲۵ مورد · صفحه ۱ از ۳/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'صفحه قبل' })).toBeDisabled()
    await userEvent.click(screen.getByRole('button', { name: 'صفحه بعد' }))
    expect(onPage).toHaveBeenCalledWith(2)
  })

  it('toggles sort on sortable headers', async () => {
    const onSort = vi.fn()
    render(
      <DataTable
        columns={[{ ...cols[0], sortable: true }]}
        rows={[{ n: 'a' }]}
        rowKey={(r) => r.n}
        sort={{ key: 'n', dir: 'desc' }}
        onSortChange={onSort}
      />,
    )
    await userEvent.click(screen.getByRole('button', { name: 'نام' }))
    expect(onSort).toHaveBeenCalledWith({ key: 'n', dir: 'asc' })
  })
})

describe('ConfirmDialog', () => {
  it('requires the typed text before confirming', async () => {
    const onConfirm = vi.fn()
    render(<ConfirmDialog open onOpenChange={() => {}} title="حذف" confirmLabel="حذف کن" requireText="حذف" onConfirm={onConfirm} />)
    const btn = screen.getByRole('button', { name: 'حذف کن' })
    expect(btn).toBeDisabled()
    await userEvent.type(screen.getByRole('textbox'), 'حذف')
    expect(btn).toBeEnabled()
    await userEvent.click(btn)
    expect(onConfirm).toHaveBeenCalled()
  })
})

describe('StatCard', () => {
  it('renders value, 14 bars and a signed delta', () => {
    const { container } = render(
      <StatCard title="کاربران" value="۱٬۲۰۰" icon={Activity} series={Array.from({ length: 14 }, (_, i) => i)} delta={-0.1} />,
    )
    expect(screen.getByText('۱٬۲۰۰')).toBeInTheDocument()
    expect(screen.getByText('-۱۰٪')).toBeInTheDocument()
    expect(container.querySelectorAll('span[style]')).toHaveLength(14)
  })
})
