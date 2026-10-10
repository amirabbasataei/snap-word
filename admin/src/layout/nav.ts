import {
  Bell, Gamepad2, LayoutDashboard, Medal, Radio, ScrollText, Shield, Smile, Swords, Trophy, UserRound, Users,
  type LucideIcon,
} from 'lucide-react'
import type { AdminRole } from '@/auth/AuthContext'

export interface NavItem {
  to: string
  label: string
  icon: LucideIcon
  /** Hidden for roles below this. */
  minRole?: AdminRole
}
export interface NavGroup {
  /** Small grey section label; omitted for the top group. */
  label?: string
  items: NavItem[]
}

export const NAV: NavGroup[] = [
  {
    items: [
      { to: '/', label: 'داشبورد', icon: LayoutDashboard },
      { to: '/users', label: 'کاربران', icon: Users },
    ],
  },
  {
    label: 'محتوا',
    items: [
      { to: '/content/taunts', label: 'تیکه‌ها', icon: Smile },
      { to: '/content/avatars', label: 'آواتارها', icon: UserRound },
      { to: '/content/daily', label: 'چالش روزانه', icon: Trophy },
      { to: '/content/leaderboards', label: 'جدول امتیازات', icon: Medal },
    ],
  },
  {
    label: 'عملیات زنده',
    items: [
      { to: '/live', label: 'اتاق‌های زنده', icon: Radio },
      { to: '/matches', label: 'مسابقه‌ها', icon: Swords },
      { to: '/notifications', label: 'اعلان‌ها', icon: Bell },
    ],
  },
  {
    label: 'مدیریت',
    items: [
      { to: '/admins', label: 'مدیران', icon: Shield, minRole: 'owner' },
      { to: '/audit', label: 'گزارش فعالیت', icon: ScrollText },
    ],
  },
]

// Pages that exist only as placeholders until their stage lands.
export const PLACEHOLDERS: { to: string; title: string; stage: string; icon: LucideIcon }[] = [
  { to: '/live', title: 'اتاق‌های زنده', stage: 'A6', icon: Radio },
  { to: '/matches', title: 'مسابقه‌ها', stage: 'A6', icon: Gamepad2 },
  { to: '/notifications', title: 'اعلان‌ها', stage: 'A6', icon: Bell },
  { to: '/admins', title: 'مدیران', stage: 'A7', icon: Shield },
  { to: '/audit', title: 'گزارش فعالیت', stage: 'A7', icon: ScrollText },
]

export const ROLE_LABEL: Record<AdminRole, string> = {
  owner: 'مالک',
  operator: 'اپراتور',
  viewer: 'بیننده',
}

const RANK: Record<AdminRole, number> = { viewer: 0, operator: 1, owner: 2 }
export function roleAtLeast(role: AdminRole, min: AdminRole): boolean {
  return RANK[role] >= RANK[min]
}
