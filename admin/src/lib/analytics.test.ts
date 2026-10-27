import { describe, expect, it } from 'vitest'
import { toFa } from './fa'
import {
  averageRetention,
  EVENT_NAMES,
  eventLabel,
  formatDuration,
  lastDays,
  retentionShare,
  screenLabel,
  type RetentionCohort,
} from './analytics'

const cohort = (size: number, retained: (number | null)[]): RetentionCohort => ({
  cohort: '2026-10-01',
  size,
  retained: [...retained, ...Array(31 - retained.length).fill(null)],
})

describe('retention helpers', () => {
  it('shares are fractions of the cohort and null for days not reached', () => {
    const c = cohort(10, [10, 4, null])
    expect(retentionShare(c, 0)).toBe(1)
    expect(retentionShare(c, 1)).toBe(0.4)
    expect(retentionShare(c, 2)).toBeNull()
    expect(retentionShare(cohort(0, [0]), 0)).toBeNull()
  })

  it('averages across cohorts weighted by size, skipping cohorts that have not reached a day', () => {
    const avg = averageRetention([cohort(10, [10, 5, 2]), cohort(30, [30, 6])])
    expect(avg[0]).toBe(1)
    expect(avg[1]).toBeCloseTo(11 / 40)
    expect(avg[2]).toBeCloseTo(2 / 10) // only the first cohort has a D2
    expect(avg[3]).toBeNull()
  })
})

describe('formatting', () => {
  it('formats durations in Persian units', () => {
    expect(formatDuration(45_000, toFa)).toBe('۴۵ ثانیه')
    expect(formatDuration(120_000, toFa)).toBe('۲ دقیقه')
    expect(formatDuration(83_000, toFa)).toBe('۱ دقیقه و ۲۳ ثانیه')
  })

  it('lists Iran calendar days oldest first', () => {
    // 22:00 UTC on the 26th is already the 27th in Iran (UTC+03:30).
    expect(lastDays(3, new Date('2026-10-26T22:00:00Z'))).toEqual(['2026-10-25', '2026-10-26', '2026-10-27'])
  })

  it('labels every event of the vocabulary and falls back to the raw name', () => {
    for (const n of EVENT_NAMES) expect(eventLabel(n)).not.toBe(n)
    expect(eventLabel('brand_new')).toBe('brand_new')
    expect(screenLabel('/home')).toBe('خانه')
    expect(screenLabel('/somewhere')).toBe('/somewhere')
  })

  it('knows exactly the events the server accepts', () => {
    // Mirror of service.AnalyticsEventNames and the Dart AnalyticsEvent enum.
    expect([...EVENT_NAMES].sort()).toEqual(
      [
        'app_open', 'session_start', 'session_end', 'screen_view', 'signup', 'login', 'identify',
        'game_start', 'game_end', 'continue_used', 'powerup_used', 'daily_start', 'daily_end',
        'queue_join', 'queue_leave', 'match_found', 'ad_watched', 'purchase_tap', 'share',
        'friend_request', 'challenge_sent',
      ].sort(),
    )
  })
})
