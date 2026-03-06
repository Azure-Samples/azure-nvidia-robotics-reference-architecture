import { describe, expect, it } from 'vitest'

import { buildCssFilter } from '../css-filters'

describe('buildCssFilter', () => {
  it('returns empty string when no adjustments are active', () => {
    expect(buildCssFilter()).toBe('')
    expect(buildCssFilter(undefined, undefined)).toBe('')
    expect(buildCssFilter(undefined, 'none')).toBe('')
  })

  it('applies brightness adjustment', () => {
    expect(buildCssFilter({ brightness: 0.5 })).toBe('brightness(1.5)')
    expect(buildCssFilter({ brightness: -0.5 })).toBe('brightness(0.5)')
  })

  it('applies contrast adjustment', () => {
    expect(buildCssFilter({ contrast: 0.3 })).toBe('contrast(1.3)')
  })

  it('applies saturation adjustment', () => {
    expect(buildCssFilter({ saturation: -0.5 })).toBe('saturate(0.5)')
  })

  it('applies hue rotation', () => {
    expect(buildCssFilter({ hue: 90 })).toBe('hue-rotate(90deg)')
  })

  it('applies gamma correction as brightness approximation', () => {
    const result = buildCssFilter({ gamma: 0.5 })
    expect(result).toMatch(/^brightness\(\d+\.\d+\)$/)
  })

  it('ignores zero/default values', () => {
    expect(buildCssFilter({ brightness: 0, contrast: 0, saturation: 0, gamma: 1, hue: 0 })).toBe('')
  })

  it('combines multiple adjustments', () => {
    const result = buildCssFilter({ brightness: 0.2, contrast: 0.3 })
    expect(result).toContain('brightness(1.2)')
    expect(result).toContain('contrast(1.3)')
  })

  it('applies grayscale preset', () => {
    expect(buildCssFilter(undefined, 'grayscale')).toBe('grayscale(1)')
  })

  it('applies sepia preset', () => {
    expect(buildCssFilter(undefined, 'sepia')).toBe('sepia(1)')
  })

  it('applies invert preset', () => {
    expect(buildCssFilter(undefined, 'invert')).toBe('invert(1)')
  })

  it('applies warm preset', () => {
    expect(buildCssFilter(undefined, 'warm')).toBe('sepia(0.3) saturate(1.2)')
  })

  it('applies cool preset', () => {
    expect(buildCssFilter(undefined, 'cool')).toBe('hue-rotate(180deg) saturate(0.7)')
  })

  it('combines adjustments with preset', () => {
    const result = buildCssFilter({ brightness: 0.5 }, 'grayscale')
    expect(result).toContain('brightness(1.5)')
    expect(result).toContain('grayscale(1)')
  })
})
