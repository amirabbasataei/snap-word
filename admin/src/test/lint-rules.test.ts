// Mirrors the Flutter token_coverage_test: fails the build on hex colours outside
// tokens.css and on physical (non-RTL-safe) CSS/Tailwind in components.
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'
import { describe, expect, it } from 'vitest'

const SRC = join(__dirname, '..')

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((n) => {
    const p = join(dir, n)
    return statSync(p).isDirectory() ? files(p) : [p]
  })
}

const sources = files(SRC).filter((f) => /\.(tsx?|css)$/.test(f) && !/\.test\.tsx?$/.test(f))

function scan(pattern: RegExp, skip: (f: string) => boolean = () => false) {
  const hits: string[] = []
  for (const f of sources) {
    if (skip(f)) continue
    readFileSync(f, 'utf8').split('\n').forEach((line, i) => {
      if (pattern.test(line)) hits.push(`${relative(SRC, f)}:${i + 1}: ${line.trim()}`)
    })
  }
  return hits
}

describe('design rules', () => {
  it('has no hex colours outside tokens.css', () => {
    const hits = scan(/#[0-9a-fA-F]{3,8}\b/, (f) => f.endsWith('tokens.css'))
    expect(hits).toEqual([])
  })

  it('uses logical properties only (no left/right/ml/mr/pl/pr)', () => {
    const physical =
      /(?:^|[\s"'`:!])(?:-?(?:m|p)[lr]-|(?:left|right)-|text-(?:left|right)\b|rounded-[lr]-|border-[lr]-|border-[lr]\b|float-(?:left|right))|(?:^|[\s{;])(?:margin|padding|border)-(?:left|right)\s*:|(?:^|[\s{;])(?:left|right)\s*:/
    expect(scan(physical)).toEqual([])
  })
})
