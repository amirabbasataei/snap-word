import { describe, expect, it } from 'vitest'
import type { ChartColors } from '@/components/charts/useChartColors'
import type { DashboardDay } from '@/lib/dashboard'
import { activityOption, matchesBarOption, modeDonutOption, modeTotals } from './chartOptions'

// Plain strings stand in for resolved CSS tokens.
const C = Object.fromEntries(
  ['text', 'muted', 'border', 'surface', 'raised', 'blue', 'orange', 'pink', 'green', 'yellow'].map((n) => [n, `tok-${n}`]),
) as ChartColors

const days: DashboardDay[] = [
  { date: '2026-10-09', signups: 1, matches_solo: 2, matches_versus: 3, matches_ai_online: 0, matches_daily: 1, daily_attempts: 1, coins_claimed: 0 },
  { date: '2026-10-10', signups: 0, matches_solo: 1, matches_versus: 0, matches_ai_online: 4, matches_daily: 0, daily_attempts: 0, coins_claimed: 5 },
]

describe('chart options', () => {
  it('totals each mode across the window', () => {
    expect(modeTotals(days)).toEqual({ solo: 3, versus: 3, daily: 1, ai_online: 4 })
  })

  it('runs the time axis right-to-left with the value axis at the start side', () => {
    const o = activityOption(C, days) as { xAxis: { inverse: boolean }; yAxis: { position: string } }
    expect(o.xAxis.inverse).toBe(true)
    expect(o.yAxis.position).toBe('right')
  })

  it('formats axis labels and tooltips with Persian digits', () => {
    const o = activityOption(C, days) as {
      xAxis: { axisLabel: { formatter: (v: string) => string } }
      tooltip: { formatter: (p: { dataIndex: number }[]) => string }
    }
    expect(o.xAxis.axisLabel.formatter('2026-10-10')).toBe('۰۷/۱۸')
    const html = o.tooltip.formatter([{ dataIndex: 1 }])
    expect(html).toContain('۱۴۰۵/۰۷/۱۸')
    expect(html.replace(/#[0-9a-f]+|tok-\w+|\d+px|\d+%|rgba?\([^)]*\)/gi, '')).not.toMatch(/[0-9]/)
  })

  it('stacks four modes with a surface-coloured gap, and drops empty donut slices', () => {
    const bar = matchesBarOption(C, days) as { series: { stack: string; itemStyle: { borderColor: string; borderWidth: number } }[] }
    expect(bar.series).toHaveLength(4)
    expect(bar.series.every((s) => s.stack === 'matches' && s.itemStyle.borderColor === 'tok-surface' && s.itemStyle.borderWidth === 2)).toBe(true)
    const donut = modeDonutOption(C, { solo: 3, versus: 0, daily: 1, ai_online: 0 }) as { series: { data: unknown[] }[] }
    expect(donut.series[0].data).toHaveLength(2)
  })
})
