import * as DM from '@radix-ui/react-dropdown-menu'
import { Bell, ChevronDown, LogOut, Menu, Moon, Search, Sun } from 'lucide-react'
import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/auth/AuthContext'
import { Logo } from '@/components/Logo'
import { Avatar } from '@/components/ui/Avatar'
import { useToast } from '@/components/ui/Toast'
import { messageOf } from '@/lib/errors'
import type { Theme } from '@/lib/theme'
import { ROLE_LABEL } from './nav'

interface Props {
  theme: Theme
  onToggleTheme: () => void
  onOpenMenu: () => void
}

export function Topbar({ theme, onToggleTheme, onOpenMenu }: Props) {
  const { admin, logout } = useAuth()
  const navigate = useNavigate()
  const { toast } = useToast()
  const [q, setQ] = useState('')

  function onSearch(e: FormEvent) {
    e.preventDefault()
    const term = q.trim()
    if (term) navigate(`/users?q=${encodeURIComponent(term)}`)
  }

  async function onLogout() {
    try {
      await logout()
    } catch (e) {
      toast({ title: messageOf(e), tone: 'error' })
    }
  }

  const iconBtn =
    'grid size-10 shrink-0 cursor-pointer place-items-center rounded-lg text-muted transition hover:bg-active hover:text-text'

  return (
    <header className="sticky top-0 z-30 flex h-[72px] items-center gap-2 border-b border-border bg-sidebar px-4 sm:gap-3 sm:px-6">
      <button type="button" onClick={onOpenMenu} aria-label="باز کردن منو" className={`${iconBtn} lg:hidden`}>
        <Menu className="size-5" aria-hidden />
      </button>

      <Logo className="lg:hidden" />

      <form onSubmit={onSearch} role="search" className="relative hidden max-w-md flex-1 sm:block">
        <Search className="pointer-events-none absolute inset-y-0 start-3 my-auto size-4 text-muted" aria-hidden />
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="جستجوی کاربر…"
          aria-label="جستجو"
          className="h-10 w-full rounded-lg border border-transparent bg-raised ps-10 pe-3 text-sm text-text placeholder:text-muted focus:border-blue focus:outline-none"
        />
      </form>

      <div className="flex-1" />

      <button
        type="button"
        onClick={onToggleTheme}
        aria-label={theme === 'dark' ? 'تم روشن' : 'تم تیره'}
        className={iconBtn}
      >
        {theme === 'dark' ? <Sun className="size-5" aria-hidden /> : <Moon className="size-5" aria-hidden />}
      </button>
      {/* No notification source exists yet, so no count badge is shown. */}
      <button type="button" aria-label="اعلان‌ها" onClick={() => navigate('/notifications')} className={iconBtn}>
        <Bell className="size-5" aria-hidden />
      </button>

      <DM.Root dir="rtl">
        <DM.Trigger className="flex h-12 cursor-pointer items-center gap-3 rounded-lg border-s border-border ps-4 pe-1 text-start hover:bg-raised sm:ms-1">
          <Avatar name={admin?.username ?? '؟'} className="size-9" />
          <span className="hidden leading-tight sm:block">
            <span className="block text-sm font-medium text-text" dir="ltr">{admin?.username}</span>
            <span className="block text-xs text-muted">{admin ? ROLE_LABEL[admin.role] : ''}</span>
          </span>
          <ChevronDown className="hidden size-4 text-muted sm:block" aria-hidden />
        </DM.Trigger>
        <DM.Portal>
          <DM.Content align="start" sideOffset={6} className="z-50 min-w-44 rounded-lg border border-border bg-surface p-1 shadow-pop">
            <div className="px-3 py-2 text-xs text-muted sm:hidden">
              {admin?.username} · {admin ? ROLE_LABEL[admin.role] : ''}
            </div>
            <DM.Item
              onSelect={() => void onLogout()}
              className="flex cursor-pointer items-center gap-2 rounded-md px-3 py-2 text-sm text-text outline-none data-[highlighted]:bg-active"
            >
              <LogOut className="size-4" aria-hidden />
              خروج
            </DM.Item>
          </DM.Content>
        </DM.Portal>
      </DM.Root>
    </header>
  )
}
