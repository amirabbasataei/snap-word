import * as echarts from 'echarts/core'
import type { EChartsCoreOption } from 'echarts/core'
import { withAlpha, type ChartColors } from '@/components/charts/useChartColors'
import { formatJalaliDay, formatNumber, toFa } from '@/lib/fa'
import { matchesOf, type DashboardDay } from '@/lib/dashboard'

/** Mode shares, in the fixed categorical order validated against both surfaces. */
export const MODE_KEYS = ['solo', 'versus', 'daily', 'ai_online'] as const
export type ModeKey = (typeof MODE_KEYS)[number]
export const MODE_LABEL: Record<ModeKey, string> = {
  solo: 'تک‌نفره و هوش مصنوعی (روی دستگاه)',
  versus: 'رودررو (۱ به ۱)',
  daily: 'چالش روزانه',
  ai_online: 'هوش مصنوعی آنلاین',
}
export const MODE_COLOR: Record<ModeKey, keyof ChartColors> = {
  solo: 'blue',
  versus: 'orange',
  daily: 'yellow',
  ai_online: 'green',
}
const MODE_FIELD: Record<ModeKey, (d: DashboardDay) => number> = {
  solo: (d) => d.matches_solo,
  versus: (d) => d.matches_versus,
  daily: (d) => d.matches_daily,
  ai_online: (d) => d.matches_ai_online,
}

export function modeTotals(days: DashboardDay[]): Record<ModeKey, number> {
  return Object.fromEntries(MODE_KEYS.map((k) => [k, days.reduce((a, d) => a + MODE_FIELD[k](d), 0)])) as Record<ModeKey, number>
}

const FONT = 'Estedad, system-ui, sans-serif'

function tooltipBase(c: ChartColors) {
  return {
    backgroundColor: c.raised,
    borderColor: c.border,
    borderWidth: 1,
    padding: [8, 12],
    textStyle: { color: c.text, fontFamily: FONT, fontSize: 12 },
    extraCssText: 'direction: rtl; text-align: start; box-shadow: none; border-radius: 8px;',
  }
}

function tooltipRow(color: string, label: string, value: number): string {
  return (
    `<div style="display:flex;align-items:center;gap:8px;justify-content:space-between;min-width:150px">` +
    `<span style="display:inline-flex;align-items:center;gap:6px">` +
    `<span style="width:8px;height:8px;border-radius:50%;background:${color};display:inline-block"></span>${label}</span>` +
    `<b>${formatNumber(value)}</b></div>`
  )
}

// ECharts only has physical `left`/`right` keys; they are quoted so the
// logical-CSS lint (which targets CSS/Tailwind) does not mistake them for styles.
// The time axis is reversed for RTL reading, so the value axis sits on the reading-start side.
function axes(c: ChartColors, days: DashboardDay[]) {
  return {
    grid: { top: 12, bottom: 28, 'left': 8, 'right': 44 },
    xAxis: {
      type: 'category' as const,
      inverse: true,
      data: days.map((d) => d.date),
      axisTick: { show: false },
      axisLine: { lineStyle: { color: c.border } },
      axisLabel: {
        color: c.muted,
        fontFamily: FONT,
        hideOverlap: true,
        margin: 10,
        formatter: (v: string) => formatJalaliDay(v),
      },
    },
    yAxis: {
      type: 'value' as const,
      position: 'right' as const,
      minInterval: 1,
      splitNumber: 4,
      axisLabel: { color: c.muted, fontFamily: FONT, formatter: (v: number) => formatNumber(v) },
      splitLine: { lineStyle: { color: c.border, type: 'dashed' as const, opacity: 0.6 } },
    },
  }
}

/** «فعالیت روزانه»: signups vs matches on one shared axis, last 30 days. */
export function activityOption(c: ChartColors, days: DashboardDay[]): EChartsCoreOption {
  const mk = (name: string, color: string, values: number[]) => ({
    name,
    type: 'line',
    smooth: 0.3,
    showSymbol: false,
    symbolSize: 8,
    lineStyle: { width: 2, color },
    itemStyle: { color, borderColor: c.surface, borderWidth: 2 },
    areaStyle: {
      color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
        { offset: 0, color: withAlpha(color, 0.32) },
        { offset: 1, color: withAlpha(color, 0) },
      ]),
    },
    emphasis: { focus: 'series' },
    data: values,
  })
  return {
    animationDuration: 400,
    ...axes(c, days),
    tooltip: {
      ...tooltipBase(c),
      trigger: 'axis',
      axisPointer: { type: 'line', lineStyle: { color: c.muted, type: 'dashed' } },
      formatter: (p: { dataIndex: number }[]) => {
        const d = days[p[0].dataIndex]
        return (
          `<div style="margin-bottom:4px;color:${c.muted}">${formatJalaliDay(d.date, 'yyyy/MM/dd')}</div>` +
          tooltipRow(c.blue, 'مسابقه‌ها', matchesOf(d)) +
          tooltipRow(c.green, 'ثبت‌نام‌ها', d.signups)
        )
      },
    },
    series: [mk('مسابقه‌ها', c.blue, days.map(matchesOf)), mk('ثبت‌نام‌ها', c.green, days.map((d) => d.signups))],
  }
}

/** «مسابقه‌ها در ۷ روز»: stacked by mode, 2px surface gap between segments. */
export function matchesBarOption(c: ChartColors, days: DashboardDay[]): EChartsCoreOption {
  return {
    animationDuration: 400,
    ...axes(c, days),
    tooltip: {
      ...tooltipBase(c),
      trigger: 'axis',
      axisPointer: { type: 'shadow', shadowStyle: { color: withAlpha(c.muted, 0.12) } },
      formatter: (p: { dataIndex: number }[]) => {
        const d = days[p[0].dataIndex]
        return (
          `<div style="margin-bottom:4px;color:${c.muted}">${formatJalaliDay(d.date, 'yyyy/MM/dd')}</div>` +
          MODE_KEYS.map((k) => tooltipRow(c[MODE_COLOR[k]], MODE_LABEL[k], MODE_FIELD[k](d))).join('') +
          `<div style="margin-top:4px;border-top:1px solid ${c.border};padding-top:4px">${tooltipRow(c.muted, 'جمع', matchesOf(d))}</div>`
        )
      },
    },
    series: MODE_KEYS.map((k) => ({
      name: MODE_LABEL[k],
      type: 'bar',
      stack: 'matches',
      barMaxWidth: 28,
      itemStyle: { color: c[MODE_COLOR[k]], borderColor: c.surface, borderWidth: 2, borderRadius: 4 },
      data: days.map(MODE_FIELD[k]),
    })),
  }
}

/** «سهم حالت‌ها»: donut over the whole window. */
export function modeDonutOption(c: ChartColors, totals: Record<ModeKey, number>): EChartsCoreOption {
  const sum = MODE_KEYS.reduce((a, k) => a + totals[k], 0)
  return {
    animationDuration: 400,
    tooltip: {
      ...tooltipBase(c),
      trigger: 'item',
      formatter: (p: { name: string; value: number; color: string }) =>
        tooltipRow(p.color, p.name, p.value) +
        `<div style="color:${c.muted};margin-top:2px">${toFa(Math.round((p.value / sum) * 100))}٪ از کل</div>`,
    },
    series: [
      {
        type: 'pie',
        radius: ['62%', '86%'],
        avoidLabelOverlap: true,
        label: { show: false },
        labelLine: { show: false },
        itemStyle: { borderColor: c.surface, borderWidth: 2, borderRadius: 4 },
        data: MODE_KEYS.filter((k) => totals[k] > 0).map((k) => ({
          name: MODE_LABEL[k],
          value: totals[k],
          itemStyle: { color: c[MODE_COLOR[k]] },
        })),
      },
    ],
  }
}
