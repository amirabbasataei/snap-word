import { ChevronsLeft, ChevronsRight } from 'lucide-react'
import { NavLink } from 'react-router-dom'
import { useAuth } from '@/auth/AuthContext'
import { Logo } from '@/components/Logo'
import { cn } from '@/lib/cn'
import { NAV, roleAtLeast } from './nav'

interface Props {
  collapsed: boolean
  onToggleCollapsed?: () => void
  /** Called after a nav click (closes the mobile drawer). */
  onNavigate?: () => void
}

/** Sidebar body, shared by the desktop rail and the mobile drawer. */
export function Sidebar({ collapsed, onToggleCollapsed, onNavigate }: Props) {
  const { admin } = useAuth()
  const role = admin?.role ?? 'viewer'

  return (
    <div className="flex h-full flex-col bg-sidebar">
      <div className={cn('flex h-[72px] shrink-0 items-center border-b border-border px-4', collapsed ? 'justify-center' : 'justify-between')}>
        <Logo showText={!collapsed} />
        {onToggleCollapsed && !collapsed && (
          <button
            type="button"
            onClick={onToggleCollapsed}
            aria-label="جمع کردن منو"
            className="grid size-8 cursor-pointer place-items-center rounded-md text-muted hover:bg-active hover:text-text"
          >
            <ChevronsRight className="size-5" aria-hidden />
          </button>
        )}
      </div>

      <nav aria-label="منوی اصلی" className="flex-1 overflow-y-auto px-3 py-4">
        {NAV.map((group, gi) => {
          const items = group.items.filter((i) => !i.minRole || roleAtLeast(role, i.minRole))
          if (items.length === 0) return null
          return (
            <div key={gi} className={cn(gi > 0 && 'mt-5')}>
              {group.label &&
                (collapsed ? (
                  <hr className="mx-2 mb-2 border-border" />
                ) : (
                  <p className="mb-2 px-3 text-xs font-medium text-muted">{group.label}</p>
                ))}
              <ul className="flex flex-col gap-1">
                {items.map(({ to, label, icon: Icon }) => (
                  <li key={to}>
                    <NavLink
                      to={to}
                      end={to === '/'}
                      onClick={onNavigate}
                      title={collapsed ? label : undefined}
                      className={({ isActive }) =>
                        cn(
                          'flex h-11 items-center gap-3 rounded-lg px-3 text-sm transition',
                          collapsed && 'justify-center px-0',
                          isActive ? 'bg-active font-medium text-text' : 'text-muted hover:bg-raised hover:text-text',
                        )
                      }
                    >
                      <Icon className="size-5 shrink-0" aria-hidden />
                      {!collapsed && <span>{label}</span>}
                      {collapsed && <span className="sr-only">{label}</span>}
                    </NavLink>
                  </li>
                ))}
              </ul>
            </div>
          )
        })}
      </nav>

      {onToggleCollapsed && collapsed && (
        <div className="border-t border-border p-3">
          <button
            type="button"
            onClick={onToggleCollapsed}
            aria-label="باز کردن منو"
            className="grid h-10 w-full cursor-pointer place-items-center rounded-md text-muted hover:bg-active hover:text-text"
          >
            <ChevronsLeft className="size-5" aria-hidden />
          </button>
        </div>
      )}
    </div>
  )
}
