import { getYear } from 'date-fns-jalali'

export function jalaliYear(now: Date = new Date()): number {
  return getYear(now)
}
