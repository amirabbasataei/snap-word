import { format, formatDistanceStrict } from 'date-fns-jalali'
import { faIR } from 'date-fns-jalali/locale/fa-IR'

// Mirror of client/lib/core/utils/persian_digits.dart — keep behaviour in sync.
const FA_DIGITS = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹']
const THOUSANDS = '٬'
const DECIMAL = '٫'

/** Iran Standard Time is a fixed UTC+03:30 (no DST since 2022). */
export const IRAN_OFFSET_MINUTES = 3 * 60 + 30

/** Converts every ASCII digit to its Persian equivalent; other chars pass through. */
export function toFa(input: string | number): string {
  return String(input).replace(/[0-9]/g, (d) => FA_DIGITS[Number(d)])
}

/** `1240` → `۱٬۲۴۰`; non-integers keep up to `maxFraction` digits after «٫». */
export function formatNumber(value: number, maxFraction = 0): string {
  if (!Number.isFinite(value)) return '—'
  const negative = value < 0
  const fixed = Math.abs(value).toFixed(maxFraction)
  const [int, frac] = fixed.split('.')
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, THOUSANDS)
  const trimmed = frac ? frac.replace(/0+$/, '') : ''
  const out = trimmed ? `${grouped}${DECIMAL}${trimmed}` : grouped
  return toFa(negative ? `-${out}` : out)
}

/** `1500` → `۱٫۵ هزار`, `2_300_000` → `۲٫۳ میلیون`. */
export function formatCompact(value: number): string {
  const abs = Math.abs(value)
  if (abs >= 1_000_000_000) return `${formatNumber(value / 1_000_000_000, 1)} میلیارد`
  if (abs >= 1_000_000) return `${formatNumber(value / 1_000_000, 1)} میلیون`
  if (abs >= 1_000) return `${formatNumber(value / 1_000, 1)} هزار`
  return formatNumber(value)
}

/** `0.256` → `٪۲۶`; signed variant for deltas: `+٪۲۵`. */
export function formatPercent(ratio: number, signed = false): string {
  const n = Math.round(ratio * 100)
  const sign = signed && n > 0 ? '+' : ''
  return `${sign}${formatNumber(n)}٪`
}

/** Shifts a Date so its UTC fields read as Iran wall-clock time. */
function toIranWallClock(date: Date): Date {
  return new Date(date.getTime() + IRAN_OFFSET_MINUTES * 60_000)
}

function parse(input: Date | string | number): Date | null {
  const d = input instanceof Date ? input : new Date(input)
  return Number.isNaN(d.getTime()) ? null : d
}

// date-fns formats in the host timezone, so format the shifted instant in UTC:
// build a local Date carrying the Iran wall-clock components.
function iranLocal(date: Date): Date {
  const w = toIranWallClock(date)
  return new Date(w.getUTCFullYear(), w.getUTCMonth(), w.getUTCDate(), w.getUTCHours(), w.getUTCMinutes(), w.getUTCSeconds())
}

/** Jalali date in Iran time, e.g. `۱۴۰۵/۰۷/۱۸`. */
export function formatJalaliDate(input: Date | string | number | null | undefined): string {
  const d = input == null ? null : parse(input)
  if (!d) return '—'
  return toFa(format(iranLocal(d), 'yyyy/MM/dd'))
}

/** Jalali date + 24h time in Iran time, e.g. `۱۴۰۵/۰۷/۱۸ ۱۴:۰۵`. */
export function formatJalaliDateTime(input: Date | string | number | null | undefined): string {
  const d = input == null ? null : parse(input)
  if (!d) return '—'
  return toFa(format(iranLocal(d), 'yyyy/MM/dd HH:mm'))
}

/** «۳ ساعت پیش» style relative time. */
export function formatRelative(input: Date | string | number | null | undefined, now: Date = new Date()): string {
  const d = input == null ? null : parse(input)
  if (!d) return '—'
  const text = formatDistanceStrict(d, now, { locale: faIR, addSuffix: true })
  return toFa(text)
}
