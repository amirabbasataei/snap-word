import ReactEChartsCoreModule from 'echarts-for-react/lib/core'
import * as echarts from 'echarts/core'
import { BarChart, LineChart, PieChart } from 'echarts/charts'
import { AriaComponent, GridComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { EChartsCoreOption } from 'echarts/core'

// The package is CJS: in the production bundle the default import can arrive as the
// module namespace ({ default: Component }) instead of the component itself.
const ReactEChartsCore: typeof ReactEChartsCoreModule =
  (ReactEChartsCoreModule as unknown as { default?: typeof ReactEChartsCoreModule }).default ?? ReactEChartsCoreModule

echarts.use([LineChart, BarChart, PieChart, GridComponent, TooltipComponent, AriaComponent, CanvasRenderer])

interface Props {
  option: EChartsCoreOption
  height: number
  /** Accessible summary of what the chart shows (the canvas itself is opaque). */
  label: string
}

/** Tree-shaken ECharts canvas; options are replaced (not merged) on change. */
export function EChart({ option, height, label }: Props) {
  return (
    <div role="img" aria-label={label} dir="ltr">
      <ReactEChartsCore echarts={echarts} option={option} notMerge style={{ height, width: '100%' }} />
    </div>
  )
}
