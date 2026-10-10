import { useEffect, useState } from 'react'

const NAMES = ['text', 'muted', 'border', 'surface', 'raised', 'blue', 'orange', 'pink', 'green', 'yellow'] as const
export type ChartColors = Record<(typeof NAMES)[number], string>

function read(): ChartColors {
  const style = getComputedStyle(document.documentElement)
  return Object.fromEntries(NAMES.map((n) => [n, style.getPropertyValue(`--${n}`).trim()])) as ChartColors
}

/**
 * Resolved design-token colours for canvas charts (which cannot read CSS
 * variables). Re-read whenever the theme attribute on <html> flips.
 */
export function useChartColors(): ChartColors {
  const [colors, setColors] = useState(read)
  useEffect(() => {
    const obs = new MutationObserver(() => setColors(read()))
    obs.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] })
    return () => obs.disconnect()
  }, [])
  return colors
}

/** `#rrggbb` + alpha → `rgba(...)`; anything else is returned unchanged. */
export function withAlpha(color: string, alpha: number): string {
  const m = /^#([0-9a-f]{6})$/i.exec(color)
  if (!m) return color
  const n = parseInt(m[1], 16)
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`
}
