// Dev-only gallery of the component kit (route exists only under `pnpm dev`).
// Every figure here is sample data, labelled as such — never shown in prod.
import { Activity, Coins, Crown, UserPlus } from 'lucide-react'
import { useState } from 'react'
import { Avatar } from '@/components/ui/Avatar'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card, CardBody, CardHeader } from '@/components/ui/Card'
import { ConfirmDialog, Dialog } from '@/components/ui/Dialog'
import { DataTable, type SortState } from '@/components/ui/DataTable'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { Skeleton } from '@/components/ui/Skeleton'
import { StatCard } from '@/components/ui/StatCard'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/Tabs'
import { useToast } from '@/components/ui/Toast'
import { formatCompact, formatJalaliDateTime, formatNumber } from '@/lib/fa'

const SERIES = [3, 5, 4, 8, 6, 9, 7, 12, 10, 8, 14, 11, 13, 16]
const ROWS = Array.from({ length: 7 }, (_, i) => ({ id: String(i), name: `نمونه ${i + 1}`, coins: 1250 * (i + 1), at: Date.now() - i * 3_600_000 * 7 }))

export function Kit() {
  const { toast } = useToast()
  const [dlg, setDlg] = useState(false)
  const [confirm, setConfirm] = useState(false)
  const [sel, setSel] = useState('a')
  const [sort, setSort] = useState<SortState | null>({ key: 'coins', dir: 'desc' })
  const [page, setPage] = useState(1)
  const [mode, setMode] = useState<'ok' | 'loading' | 'empty' | 'error'>('ok')

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-text">کیت اجزا <Badge tone="yellow">نمونه — فقط توسعه</Badge></h1>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard title="کل کاربران" value={formatNumber(8052)} icon={UserPlus} tone="blue" series={SERIES} delta={0.25} />
        <StatCard title="سکه در گردش" value={formatCompact(6_200_000)} icon={Coins} tone="pink" series={SERIES} delta={0.15} />
        <StatCard title="مسابقه امروز" value={formatNumber(1300)} icon={Activity} tone="green" series={SERIES} delta={-0.1} />
        <StatCard title="پرمیوم فعال" value={formatNumber(956)} icon={Crown} tone="yellow" series={SERIES} delta={-0.14} />
      </div>

      <Card>
        <CardHeader title="دکمه‌ها و فرم" menu={[{ label: 'نمونه', onSelect: () => toast({ title: 'انتخاب شد' }) }]} />
        <CardBody className="flex flex-wrap items-end gap-3">
          <Button>اصلی</Button>
          <Button variant="secondary">ثانویه</Button>
          <Button variant="ghost">شفاف</Button>
          <Button variant="danger">خطرناک</Button>
          <Button loading>در حال کار</Button>
          <Input label="نام" placeholder="مثلاً علی" className="w-48" />
          <Select value={sel} onValueChange={setSel} label="انتخاب" options={[{ value: 'a', label: 'گزینه اول' }, { value: 'b', label: 'گزینه دوم' }]} />
          <Avatar name="Ali" />
          <Badge tone="green">فعال</Badge>
          <Badge tone="pink">مسدود</Badge>
          <Badge>عادی</Badge>
          <Skeleton className="h-8 w-24" />
          <Button variant="secondary" onClick={() => setDlg(true)}>دیالوگ</Button>
          <Button variant="danger" onClick={() => setConfirm(true)}>تأیید تایپی</Button>
          <Button variant="secondary" onClick={() => toast({ title: 'ذخیره شد', description: 'تغییرات اعمال شد.' })}>توست موفق</Button>
          <Button variant="secondary" onClick={() => toast({ title: 'خطا', tone: 'error' })}>توست خطا</Button>
        </CardBody>
      </Card>

      <Card>
        <CardHeader
          title="جدول"
          actions={(['ok', 'loading', 'empty', 'error'] as const).map((m) => (
            <Button key={m} size="sm" variant={mode === m ? 'primary' : 'secondary'} onClick={() => setMode(m)}>{m}</Button>
          ))}
        />
        <DataTable
          columns={[
            { key: 'name', header: 'نام', cell: (r) => r.name },
            { key: 'coins', header: 'سکه', sortable: true, cell: (r) => formatNumber(r.coins) },
            { key: 'at', header: 'زمان', cell: (r) => formatJalaliDateTime(r.at) },
          ]}
          rows={mode === 'empty' ? [] : ROWS}
          rowKey={(r) => r.id}
          loading={mode === 'loading'}
          error={mode === 'error' ? 'بارگذاری ناموفق بود.' : null}
          onRetry={() => setMode('ok')}
          page={page}
          pageSize={7}
          total={mode === 'ok' ? 40 : 0}
          onPageChange={setPage}
          sort={sort}
          onSortChange={setSort}
        />
      </Card>

      <Tabs defaultValue="one">
        <TabsList>
          <TabsTrigger value="one">خلاصه</TabsTrigger>
          <TabsTrigger value="two">مسابقه‌ها</TabsTrigger>
        </TabsList>
        <TabsContent value="one" className="py-4 text-sm text-muted">محتوای تب اول</TabsContent>
        <TabsContent value="two" className="py-4 text-sm text-muted">محتوای تب دوم</TabsContent>
      </Tabs>

      <Dialog open={dlg} onOpenChange={setDlg} title="دیالوگ نمونه" description="توضیح کوتاه" footer={<Button onClick={() => setDlg(false)}>باشه</Button>}>
        <p className="text-sm text-text">محتوای دیالوگ.</p>
      </Dialog>
      <ConfirmDialog open={confirm} onOpenChange={setConfirm} title="حذف نمونه" description="این کار قابل بازگشت نیست." confirmLabel="حذف" requireText="حذف" onConfirm={() => setConfirm(false)} />
    </div>
  )
}
