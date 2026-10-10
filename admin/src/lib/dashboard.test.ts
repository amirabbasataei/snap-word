import { describe, expect, it } from 'vitest'
import { matchesOf, sumLast, weekOverWeek, type DashboardDay } from './dashboard'
import { formatJalaliDay } from './fa'

const day = (n: number, over: Partial<DashboardDay> = {}): DashboardDay => ({
  date: `2026-10-${String(n).padStart(2, '0')}`,
  signups: 0,
  matches_solo: 0,
  matches_versus: 0,
  matches_ai_online: 0,
  matches_daily: 0,
  daily_attempts: 0,
  coins_claimed: 0,
  ...over,
})

describe('dashboard helpers', () => {
  it('adds every match kind', () => {
    expect(matchesOf(day(1, { matches_solo: 1, matches_versus: 2, matches_ai_online: 3, matches_daily: 4 }))).toBe(10)
  })

  it('sums the trailing window', () => {
    const days = [1, 2, 3, 4].map((n) => day(n, { signups: n }))
    expect(sumLast(days, 2, (d) => d.signups)).toBe(7)
  })

  it('compares the last 7 days with the 7 before', () => {
    const days = Array.from({ length: 14 }, (_, i) => day(i + 1, { signups: i < 7 ? 2 : 3 }))
    expect(weekOverWeek(days, (d) => d.signups)).toBeCloseTo(0.5)
  })

  it('has no delta without a baseline', () => {
    const short = Array.from({ length: 10 }, (_, i) => day(i + 1, { signups: 1 }))
    expect(weekOverWeek(short, (d) => d.signups)).toBeUndefined()
    const flat = Array.from({ length: 14 }, (_, i) => day(i + 1, { signups: i < 7 ? 0 : 5 }))
    expect(weekOverWeek(flat, (d) => d.signups)).toBeUndefined()
  })
})

describe('formatJalaliDay', () => {
  it('renders an Iran calendar day in Jalali with Persian digits', () => {
    // 2026-10-10 is 18 Mehr 1405.
    expect(formatJalaliDay('2026-10-10')).toBe('۰۷/۱۸')
    expect(formatJalaliDay('2026-10-10', 'yyyy/MM/dd')).toBe('۱۴۰۵/۰۷/۱۸')
    expect(formatJalaliDay('garbage')).toBe('—')
  })
})
