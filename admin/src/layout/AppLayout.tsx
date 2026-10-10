import * as RD from '@radix-ui/react-dialog'
import { useCallback, useEffect, useState } from 'react'
import { Outlet } from 'react-router-dom'
import { applyTheme, readTheme, type Theme } from '@/lib/theme'
import { cn } from '@/lib/cn'
import { toFa } from '@/lib/fa'
import { Sidebar } from './Sidebar'
import { Topbar } from './Topbar'
import { jalaliYear } from './year'

const COLLAPSE_KEY = 'zanjir-admin-sidebar'

function readCollapsed(): boolean {
  try {
    return localStorage.getItem(COLLAPSE_KEY) === '1'
  } catch {
    return false
  }
}

export function AppLayout() {
  const [theme, setTheme] = useState<Theme>(readTheme)
  const [collapsed, setCollapsed] = useState(readCollapsed)
  const [drawer, setDrawer] = useState(false)

  useEffect(() => applyTheme(theme), [theme])

  const toggleCollapsed = useCallback(() => {
    setCollapsed((c) => {
      try {
        localStorage.setItem(COLLAPSE_KEY, c ? '0' : '1')
      } catch {
        /* ignore */
      }
      return !c
    })
  }, [])

  return (
    <div className="flex min-h-screen">
      {/* Desktop rail — first in DOM order, so it sits at the inline start (the right in RTL). */}
      <aside
        className={cn(
          'sticky top-0 hidden h-screen shrink-0 border-e border-border transition-[width] duration-200 lg:block',
          collapsed ? 'w-[76px]' : 'w-[272px]',
        )}
      >
        <Sidebar collapsed={collapsed} onToggleCollapsed={toggleCollapsed} />
      </aside>

      {/* Mobile drawer */}
      <RD.Root open={drawer} onOpenChange={setDrawer}>
        <RD.Portal>
          <RD.Overlay className="fixed inset-0 z-40 animate-[fade-in_150ms_ease-out] bg-scrim lg:hidden" />
          <RD.Content
            dir="rtl"
            aria-describedby={undefined}
            className="fixed inset-y-0 start-0 z-50 w-[280px] max-w-[85vw] animate-[slide-in-start_200ms_ease-out] border-e border-border shadow-pop lg:hidden"
          >
            <RD.Title className="sr-only">منوی اصلی</RD.Title>
            <Sidebar collapsed={false} onNavigate={() => setDrawer(false)} />
          </RD.Content>
        </RD.Portal>
      </RD.Root>

      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar theme={theme} onToggleTheme={() => setTheme((t) => (t === 'dark' ? 'light' : 'dark'))} onOpenMenu={() => setDrawer(true)} />
        <main className="flex-1 px-4 py-6 sm:px-6">
          <Outlet />
        </main>
        <footer className="border-t border-border bg-sidebar px-6 py-4 text-center text-xs text-muted">
          © {toFa(jalaliYear())} زنجیر — پنل مدیریت
        </footer>
      </div>
    </div>
  )
}
