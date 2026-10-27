import * as echarts from 'echarts/core'
import type { EChartsCoreOption } from 'echarts/core'
import { withAlpha, type ChartColors } from '@/components/charts/useChartColors'
import { eventLabel, type AnalyticsOverviewDay, type EventCountRow } from '@/lib/analytics'
import { formatJalaliDay } from '@/lib/fa'
import { axes, tooltipBase, tooltipRow } from '../dashboard/chartOptions'

function areaLine(c: ChartColors, name: string, color: string, values: number[]) {
  return {
    name,
    type: 'line',
    smooth: 0.3,
    showSymbol: false,
    symbolSize: 8,
    lineStyle: { width: 2, color },
    itemStyle: { color, borderColor: c.surface, borderWidth: 2 },
    areaStyle: {
      color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
        { offset: 0, color: withAlpha(color, 0.28) },
        { offset: 1, color: withAlpha(color, 0) },
      ]),
    },
    emphasis: { focus: 'series' },
    data: values,
  }
}

/** Active installs per day, with signed-in ones and new installs alongside. */
export function dauOption(c: ChartColors, days: AnalyticsOverviewDay[]): EChartsCoreOption {
  const rows = days.map((d) => ({ ...d, date: d.day }))
  return {
    animationDuration: 400,
    ...axes(c, rows),
    tooltip: {
      ...tooltipBase(c),
      trigger: 'axis',
      axisPointer: { type: 'line', lineStyle: { color: c.muted, type: 'dashed' } },
      formatter: (p: { dataIndex: number }[]) => {
        const d = days[p[0].dataIndex]
        return (
          `<div style="margin-bottom:4px;color:${c.muted}">${formatJalaliDay(d.day, 'yyyy/MM/dd')}</div>` +
          tooltipRow(c.blue, 'فعال', d.active) +
          tooltipRow(c.green, 'وارد شده', d.active_users) +
          tooltipRow(c.orange, 'نصب جدید', d.new_installs)
        )
      },
    },
    series: [
      areaLine(c, 'فعال', c.blue, days.map((d) => d.active)),
      areaLine(c, 'وارد شده', c.green, days.map((d) => d.active_users)),
      areaLine(c, 'نصب جدید', c.orange, days.map((d) => d.new_installs)),
    ],
  }
}

const SERIES_COLORS: (keyof ChartColors)[] = ['blue', 'orange', 'green', 'pink', 'yellow']

/** Daily counts of the chosen events (at most five, one colour each). */
export function eventsOption(c: ChartColors, dayList: string[], names: string[], rows: EventCountRow[]): EChartsCoreOption {
  const byKey = new Map(rows.map((r) => [`${r.day}|${r.name}`, r.count]))
  const valuesOf = (name: string) => dayList.map((d) => byKey.get(`${d}|${name}`) ?? 0)
  const axisRows = dayList.map((date) => ({ date }))
  return {
    animationDuration: 400,
    ...axes(c, axisRows),
    tooltip: {
      ...tooltipBase(c),
      trigger: 'axis',
      axisPointer: { type: 'line', lineStyle: { color: c.muted, type: 'dashed' } },
      formatter: (p: { dataIndex: number }[]) =>
        `<div style="margin-bottom:4px;color:${c.muted}">${formatJalaliDay(dayList[p[0].dataIndex], 'yyyy/MM/dd')}</div>` +
        names.map((n, i) => tooltipRow(c[SERIES_COLORS[i % SERIES_COLORS.length]], eventLabel(n), valuesOf(n)[p[0].dataIndex])).join(''),
    },
    series: names.map((n, i) => areaLine(c, eventLabel(n), c[SERIES_COLORS[i % SERIES_COLORS.length]], valuesOf(n))),
  }
}

export function seriesColor(c: ChartColors, i: number): string {
  return c[SERIES_COLORS[i % SERIES_COLORS.length]]
}
