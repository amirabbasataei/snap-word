import {
  closestCenter, DndContext, KeyboardSensor, PointerSensor, useSensor, useSensors,
  type Announcements, type DragEndEvent,
} from '@dnd-kit/core'
import {
  arrayMove, SortableContext, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy,
} from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { ArrowDown, ArrowUp, GripVertical, Pencil, Plus, Trash2 } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useAuth } from '@/auth/AuthContext'
import { Button } from '@/components/ui/Button'
import { Card, CardHeader } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { ReasonDialog } from '@/components/ui/ReasonDialog'
import { Skeleton } from '@/components/ui/Skeleton'
import { useToast } from '@/components/ui/Toast'
import { roleAtLeast } from '@/layout/nav'
import { runeCount, TAUNT_ID_RE, useTaunts, useTauntAction, type Taunt } from '@/lib/content'
import { messageOf } from '@/lib/errors'
import { formatNumber } from '@/lib/fa'
import { cn } from '@/lib/cn'

type Dialog =
  | { kind: 'add' }
  | { kind: 'save'; taunt: Taunt; text: string }
  | { kind: 'delete'; taunt: Taunt }
  | { kind: 'reorder' }

export function Taunts() {
  const { admin } = useAuth()
  const canEdit = admin ? roleAtLeast(admin.role, 'operator') : false
  const query = useTaunts()
  const act = useTauntAction()
  const { toast } = useToast()

  const serverIds = useMemo(() => query.data?.items.map((t) => t.id) ?? [], [query.data])
  // The order being rearranged locally; null = exactly what the server has.
  const [order, setOrder] = useState<string[] | null>(null)
  const [editing, setEditing] = useState<{ id: string; text: string } | null>(null)
  const [dialog, setDialog] = useState<Dialog | null>(null)

  // A refetch that changes the set (someone else added/removed a taunt) invalidates a half-done reorder.
  useEffect(() => {
    setOrder((cur) => (cur && cur.length === serverIds.length && cur.every((id) => serverIds.includes(id)) ? cur : null))
  }, [serverIds])

  const byId = useMemo(() => new Map((query.data?.items ?? []).map((t) => [t.id, t])), [query.data])
  const shownIds = order ?? serverIds
  const dirty = order !== null && order.some((id, i) => id !== serverIds[i])
  const max = query.data?.max_text_runes ?? 60

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  )

  function move(from: number, to: number) {
    if (to < 0 || to >= shownIds.length) return
    setOrder(arrayMove(shownIds, from, to))
  }
  function onDragEnd(e: DragEndEvent) {
    if (!e.over || e.active.id === e.over.id) return
    move(shownIds.indexOf(String(e.active.id)), shownIds.indexOf(String(e.over.id)))
  }

  const announcements: Announcements = {
    onDragStart: ({ active }) => `تیکهٔ «${byId.get(String(active.id))?.text ?? ''}» برداشته شد.`,
    onDragOver: ({ active, over }) =>
      over ? `تیکهٔ «${byId.get(String(active.id))?.text ?? ''}» به جای مورد ${formatNumber(shownIds.indexOf(String(over.id)) + 1)} می‌رود.` : undefined,
    onDragEnd: ({ active, over }) =>
      over ? `تیکهٔ «${byId.get(String(active.id))?.text ?? ''}» در جایگاه ${formatNumber(shownIds.indexOf(String(over.id)) + 1)} قرار گرفت.` : 'جابه‌جایی لغو شد.',
    onDragCancel: () => 'جابه‌جایی لغو شد.',
  }

  async function run(action: Parameters<typeof act.mutateAsync>[0], done: string) {
    await act.mutateAsync(action)
    toast({ title: done })
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">تیکه‌ها</h1>
        <p className="text-xs text-muted">
          پیام‌های آماده‌ای که بازیکنان دارای اشتراک ویژه در بازی رودررو می‌فرستند؛ همهٔ بازیکنان آن را می‌بینند. تغییرها بلافاصله برای بازیکنان جدید اعمال می‌شود.
        </p>
      </div>

      <Card>
        <CardHeader
          title={`فهرست تیکه‌ها${query.data ? ` (${formatNumber(query.data.items.length)})` : ''}`}
          actions={
            canEdit && (
              <Button size="sm" onClick={() => setDialog({ kind: 'add' })} disabled={dirty || !query.data}>
                <Plus className="size-4" aria-hidden />
                افزودن
              </Button>
            )
          }
        />

        {dirty && (
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border bg-raised px-5 py-3 text-sm">
            <span className="text-text">ترتیب تغییر کرده و هنوز ذخیره نشده است.</span>
            <div className="flex gap-2">
              <Button size="sm" variant="secondary" onClick={() => setOrder(null)}>
                لغو
              </Button>
              <Button size="sm" onClick={() => setDialog({ kind: 'reorder' })}>
                ذخیرهٔ ترتیب
              </Button>
            </div>
          </div>
        )}

        {query.isPending ? (
          <div className="space-y-3 p-5" aria-busy>
            {Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="h-12 w-full" />)}
          </div>
        ) : query.isError ? (
          <div role="alert" className="flex flex-col items-center gap-3 px-4 py-10 text-center">
            <p className="text-sm text-pink">{messageOf(query.error)}</p>
            <Button variant="secondary" size="sm" onClick={() => void query.refetch()}>تلاش دوباره</Button>
          </div>
        ) : shownIds.length === 0 ? (
          <p className="px-4 py-10 text-center text-sm text-muted">هنوز تیکه‌ای تعریف نشده است.</p>
        ) : (
          <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragEnd={onDragEnd}
            accessibility={{
              announcements,
              screenReaderInstructions: {
                draggable: 'برای برداشتن تیکه، کلید فاصله را بزنید؛ با کلیدهای جهت‌دار جابه‌جا کنید و دوباره فاصله بزنید تا جای آن ثبت شود. Escape لغو می‌کند.',
              },
            }}
          >
            <SortableContext items={shownIds} strategy={verticalListSortingStrategy}>
              <ul className="divide-y divide-border">
                {shownIds.map((id, i) => {
                  const taunt = byId.get(id)
                  if (!taunt) return null
                  return (
                    <TauntRow
                      key={id}
                      taunt={taunt}
                      index={i}
                      count={shownIds.length}
                      canEdit={canEdit}
                      frozen={dirty}
                      max={max}
                      editingText={editing?.id === id ? editing.text : null}
                      onEditStart={() => setEditing({ id, text: taunt.text })}
                      onEditChange={(text) => setEditing({ id, text })}
                      onEditCancel={() => setEditing(null)}
                      onEditSave={() => editing && setDialog({ kind: 'save', taunt, text: editing.text.trim() })}
                      onDelete={() => setDialog({ kind: 'delete', taunt })}
                      onMove={(to) => move(i, to)}
                    />
                  )
                })}
              </ul>
            </SortableContext>
          </DndContext>
        )}
      </Card>

      {dialog?.kind === 'add' && (
        <AddDialog
          existing={serverIds}
          max={max}
          onClose={() => setDialog(null)}
          onSubmit={(id, text, reason) => run({ type: 'save', id, text, reason }, 'تیکه افزوده شد.')}
        />
      )}
      {dialog?.kind === 'save' && (
        <ReasonDialog
          open
          onOpenChange={(o) => !o && setDialog(null)}
          title="ذخیرهٔ ویرایش تیکه"
          description={`«${dialog.taunt.text}» با «${dialog.text}» جایگزین می‌شود.`}
          confirmLabel="ذخیره"
          valid={runeCount(dialog.text) >= 1 && runeCount(dialog.text) <= max}
          onSubmit={async (reason) => {
            await run({ type: 'save', id: dialog.taunt.id, text: dialog.text, reason }, 'تیکه ذخیره شد.')
            setEditing(null)
          }}
        />
      )}
      {dialog?.kind === 'delete' && (
        <ReasonDialog
          open
          onOpenChange={(o) => !o && setDialog(null)}
          title="حذف تیکه"
          description={`«${dialog.taunt.text}» از فهرست بازیکنان حذف می‌شود. بازیکنانی که فهرست قدیمی را در دست دارند، ارسال آن را بی‌اثر می‌بینند.`}
          confirmLabel="حذف"
          danger
          requireText={dialog.taunt.id}
          onSubmit={(reason) => run({ type: 'delete', id: dialog.taunt.id, reason }, 'تیکه حذف شد.')}
        />
      )}
      {dialog?.kind === 'reorder' && (
        <ReasonDialog
          open
          onOpenChange={(o) => !o && setDialog(null)}
          title="ذخیرهٔ ترتیب تیکه‌ها"
          description="ترتیب جدید در فهرست انتخاب بازیکنان اعمال می‌شود."
          confirmLabel="ذخیرهٔ ترتیب"
          onSubmit={async (reason) => {
            await run({ type: 'reorder', ids: shownIds, reason }, 'ترتیب ذخیره شد.')
            setOrder(null)
          }}
        />
      )}
    </div>
  )
}

function Counter({ n, max }: { n: number; max: number }) {
  return (
    <span className={cn('tabular text-xs', n > max || n === 0 ? 'text-pink' : 'text-muted')}>
      {formatNumber(n)} / {formatNumber(max)}
    </span>
  )
}

interface RowProps {
  taunt: Taunt
  index: number
  count: number
  canEdit: boolean
  /** Another action is pending (unsaved reorder): lock editing. */
  frozen: boolean
  max: number
  editingText: string | null
  onEditStart: () => void
  onEditChange: (text: string) => void
  onEditCancel: () => void
  onEditSave: () => void
  onDelete: () => void
  onMove: (to: number) => void
}

function TauntRow(p: RowProps) {
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, transform, transition, isDragging } = useSortable({ id: p.taunt.id })
  const editing = p.editingText !== null
  const n = runeCount((p.editingText ?? '').trim())
  const unchanged = editing && p.editingText!.trim() === p.taunt.text
  const iconBtn = 'grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-muted transition hover:bg-active hover:text-text disabled:cursor-not-allowed disabled:opacity-40'

  return (
    <li
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition }}
      className={cn('flex flex-wrap items-center gap-x-3 gap-y-2 bg-surface px-4 py-3', isDragging && 'relative z-10 shadow-pop')}
    >
      {p.canEdit && (
        <div className="flex shrink-0 items-center gap-0.5">
          <button
            ref={setActivatorNodeRef}
            type="button"
            className={cn(iconBtn, 'cursor-grab touch-none')}
            aria-label={`جابه‌جایی تیکهٔ ${p.taunt.text}`}
            disabled={editing}
            {...attributes}
            {...listeners}
          >
            <GripVertical className="size-4" aria-hidden />
          </button>
          <button type="button" className={iconBtn} aria-label="انتقال به بالا" disabled={p.index === 0 || editing} onClick={() => p.onMove(p.index - 1)}>
            <ArrowUp className="size-4" aria-hidden />
          </button>
          <button type="button" className={iconBtn} aria-label="انتقال به پایین" disabled={p.index === p.count - 1 || editing} onClick={() => p.onMove(p.index + 1)}>
            <ArrowDown className="size-4" aria-hidden />
          </button>
        </div>
      )}
      <span className="tabular w-6 shrink-0 text-center text-xs text-muted">{formatNumber(p.index + 1)}</span>

      <div className="min-w-0 flex-1 basis-56">
        {editing ? (
          <form
            className="flex flex-col gap-1.5"
            onSubmit={(e) => {
              e.preventDefault()
              if (n >= 1 && n <= p.max && !unchanged) p.onEditSave()
            }}
          >
            <Input
              aria-label="متن تیکه"
              value={p.editingText ?? ''}
              onChange={(e) => p.onEditChange(e.target.value)}
              onKeyDown={(e) => e.key === 'Escape' && p.onEditCancel()}
              autoFocus
              autoComplete="off"
            />
            <div className="flex items-center justify-between gap-3">
              <Counter n={n} max={p.max} />
              <div className="flex gap-2">
                <Button type="button" size="sm" variant="secondary" onClick={p.onEditCancel}>انصراف</Button>
                <Button type="submit" size="sm" disabled={n < 1 || n > p.max || unchanged}>ذخیره</Button>
              </div>
            </div>
          </form>
        ) : (
          <>
            <p className="text-sm text-text">{p.taunt.text}</p>
            <p dir="ltr" className="text-start text-xs text-muted">{p.taunt.id}</p>
          </>
        )}
      </div>

      {p.canEdit && !editing && (
        <div className="flex shrink-0 gap-0.5">
          <button type="button" className={iconBtn} aria-label={`ویرایش تیکهٔ ${p.taunt.text}`} disabled={p.frozen} onClick={p.onEditStart}>
            <Pencil className="size-4" aria-hidden />
          </button>
          <button type="button" className={cn(iconBtn, 'hover:text-pink')} aria-label={`حذف تیکهٔ ${p.taunt.text}`} disabled={p.frozen} onClick={p.onDelete}>
            <Trash2 className="size-4" aria-hidden />
          </button>
        </div>
      )}
    </li>
  )
}

function AddDialog({
  existing, max, onClose, onSubmit,
}: {
  existing: string[]
  max: number
  onClose: () => void
  onSubmit: (id: string, text: string, reason: string) => Promise<void>
}) {
  const [id, setId] = useState('')
  const [text, setText] = useState('')
  const n = runeCount(text.trim())
  const idOk = TAUNT_ID_RE.test(id)
  const taken = existing.includes(id)
  return (
    <ReasonDialog
      open
      onOpenChange={(o) => !o && onClose()}
      title="افزودن تیکه"
      description="تیکهٔ جدید در انتهای فهرست قرار می‌گیرد."
      confirmLabel="افزودن"
      valid={idOk && !taken && n >= 1 && n <= max}
      onSubmit={(reason) => onSubmit(id, text.trim(), reason)}
    >
      <Input
        label="شناسه"
        dir="ltr"
        className="text-start"
        value={id}
        onChange={(e) => setId(e.target.value)}
        autoComplete="off"
        placeholder="good_luck"
        error={id && !idOk ? 'فقط حرف کوچک انگلیسی، عدد و _ (۲ تا ۳۲ نویسه، شروع با حرف).' : taken ? 'این شناسه از قبل وجود دارد.' : undefined}
        hint="بازیکنان آن را نمی‌بینند و پس از ساخت قابل تغییر نیست."
      />
      <Input
        label="متن تیکه"
        value={text}
        onChange={(e) => setText(e.target.value)}
        autoComplete="off"
        hint={`${formatNumber(n)} از ${formatNumber(max)} نویسه`}
        error={n > max ? `${formatNumber(n)} از ${formatNumber(max)} نویسه — متن بلندتر از حد مجاز است.` : undefined}
      />
    </ReasonDialog>
  )
}
