import { describe, expect, it } from 'vitest'
import { formatCompact, formatJalaliDate, formatJalaliDateTime, formatNumber, formatPercent, formatRelative, toFa } from './fa'

describe('toFa', () => {
  it('converts ASCII digits and leaves the rest alone', () => {
    expect(toFa('0123456789')).toBe('۰۱۲۳۴۵۶۷۸۹')
    expect(toFa('v2 -٫5')).toBe('v۲ -٫۵')
    expect(toFa(1405)).toBe('۱۴۰۵')
  })
})

describe('formatNumber', () => {
  it('groups thousands with «٬» and uses Persian digits', () => {
    expect(formatNumber(0)).toBe('۰')
    expect(formatNumber(999)).toBe('۹۹۹')
    expect(formatNumber(1240)).toBe('۱٬۲۴۰')
    expect(formatNumber(1234567)).toBe('۱٬۲۳۴٬۵۶۷')
    expect(formatNumber(-15000)).toBe('-۱۵٬۰۰۰')
  })
  it('uses «٫» for decimals and trims trailing zeros', () => {
    expect(formatNumber(1.5, 1)).toBe('۱٫۵')
    expect(formatNumber(2, 1)).toBe('۲')
  })
  it('renders non-finite values as a dash', () => {
    expect(formatNumber(NaN)).toBe('—')
  })
})

describe('formatCompact / formatPercent', () => {
  it('abbreviates large numbers in Persian', () => {
    expect(formatCompact(950)).toBe('۹۵۰')
    expect(formatCompact(1500)).toBe('۱٫۵ هزار')
    expect(formatCompact(6_200_000)).toBe('۶٫۲ میلیون')
  })
  it('formats ratios as percentages with optional sign', () => {
    expect(formatPercent(0.25, true)).toBe('+۲۵٪')
    expect(formatPercent(-0.1, true)).toBe('-۱۰٪')
    expect(formatPercent(0.5)).toBe('۵۰٪')
  })
})

describe('Jalali dates (Iran time, UTC+3:30)', () => {
  it('converts an instant to Jalali', () => {
    // 2026-10-10T12:00:00Z = 1405-07-18 15:30 in Iran
    expect(formatJalaliDate('2026-10-10T12:00:00Z')).toBe('۱۴۰۵/۰۷/۱۸')
    expect(formatJalaliDateTime('2026-10-10T12:00:00Z')).toBe('۱۴۰۵/۰۷/۱۸ ۱۵:۳۰')
  })
  it('rolls the day over at Iran midnight, not UTC midnight', () => {
    // 20:30Z = 00:00 next day in Iran
    expect(formatJalaliDate('2026-10-10T20:29:00Z')).toBe('۱۴۰۵/۰۷/۱۸')
    expect(formatJalaliDate('2026-10-10T20:30:00Z')).toBe('۱۴۰۵/۰۷/۱۹')
  })
  it('returns a dash for missing or invalid input', () => {
    expect(formatJalaliDate(null)).toBe('—')
    expect(formatJalaliDateTime('nope')).toBe('—')
  })
})

describe('formatRelative', () => {
  it('describes the distance in Persian digits', () => {
    const now = new Date('2026-10-10T12:00:00Z')
    const out = formatRelative('2026-10-10T09:00:00Z', now)
    expect(out).toMatch(/^[^0-9]*[۰-۹]+/u)
    expect(out).toContain('۳')
  })
})
