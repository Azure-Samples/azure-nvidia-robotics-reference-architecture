import { describe, expect, it } from 'vitest'

import {
  computeEffectiveFps,
  computePlaybackTarget,
  needsSeekBeforePlay,
} from '../playback-utils'

describe('computeEffectiveFps', () => {
  it('derives fps from totalFrames / videoDuration when both are positive', () => {
    // 385 frames in 12.833s ≈ 30 fps
    expect(computeEffectiveFps(385, 12.833, 15)).toBeCloseTo(30.0, 0)
  })

  it('returns dataset fps when video duration is zero', () => {
    expect(computeEffectiveFps(385, 0, 15)).toBe(15)
  })

  it('returns dataset fps when video duration is negative', () => {
    expect(computeEffectiveFps(385, -1, 15)).toBe(15)
  })

  it('returns dataset fps when totalFrames is zero', () => {
    expect(computeEffectiveFps(0, 12.833, 15)).toBe(15)
  })

  it('handles exact integer fps', () => {
    expect(computeEffectiveFps(300, 10, 30)).toBe(30)
  })

  it('handles non-standard fps', () => {
    // 500 frames in 10s = 50 fps
    expect(computeEffectiveFps(500, 10, 30)).toBe(50)
  })

  it('handles very short video durations', () => {
    // 10 frames in 0.5s = 20 fps
    expect(computeEffectiveFps(10, 0.5, 30)).toBe(20)
  })
})

describe('computePlaybackTarget', () => {
  it('returns shouldRestart=true when at the last frame', () => {
    const result = computePlaybackTarget(384, 385, 384, 30)
    expect(result.shouldRestart).toBe(true)
    expect(result.targetTime).toBe(0)
  })

  it('returns shouldRestart=true when beyond the last frame', () => {
    const result = computePlaybackTarget(999, 385, 999, 30)
    expect(result.shouldRestart).toBe(true)
    expect(result.targetTime).toBe(0)
  })

  it('returns shouldRestart=false and correct time for mid-frame', () => {
    const result = computePlaybackTarget(200, 385, 200, 30)
    expect(result.shouldRestart).toBe(false)
    expect(result.targetTime).toBeCloseTo(200 / 30, 5)
  })

  it('returns shouldRestart=false and correct time for frame 0', () => {
    const result = computePlaybackTarget(0, 385, 0, 30)
    expect(result.shouldRestart).toBe(false)
    expect(result.targetTime).toBe(0)
  })

  it('uses originalFrameIndex when available', () => {
    const result = computePlaybackTarget(210, 385, 200, 30)
    expect(result.shouldRestart).toBe(false)
    expect(result.targetTime).toBeCloseTo(200 / 30, 5)
  })

  it('uses currentFrame when originalFrameIndex is null (inserted frame)', () => {
    const result = computePlaybackTarget(150, 385, null, 30)
    expect(result.shouldRestart).toBe(false)
    expect(result.targetTime).toBeCloseTo(150 / 30, 5)
  })

  it('handles single-frame episode', () => {
    const result = computePlaybackTarget(0, 1, 0, 30)
    expect(result.shouldRestart).toBe(true)
  })
})

describe('needsSeekBeforePlay', () => {
  it('returns true when position differs by more than half a frame', () => {
    // At 30fps, half frame = 0.0167s. Difference of 1s should need seek.
    expect(needsSeekBeforePlay(0, 1, 30)).toBe(true)
  })

  it('returns false when position is within half a frame', () => {
    // Difference of 0.01s at 30fps (half-frame = 0.0167s) should not need seek
    expect(needsSeekBeforePlay(6.66, 6.67, 30)).toBe(false)
  })

  it('returns false when positions are equal', () => {
    expect(needsSeekBeforePlay(5.0, 5.0, 30)).toBe(false)
  })

  it('handles very high fps with tighter threshold', () => {
    // At 120fps, half frame = 0.00417s
    expect(needsSeekBeforePlay(1.0, 1.005, 120)).toBe(true)
    expect(needsSeekBeforePlay(1.0, 1.003, 120)).toBe(false)
  })

  it('handles negative time difference', () => {
    // Video is ahead of target
    expect(needsSeekBeforePlay(10, 5, 30)).toBe(true)
  })

  it('returns true for video at beginning when target is mid-video', () => {
    // Reproduces the original bug: video at 0, target at 6.667
    expect(needsSeekBeforePlay(0, 6.667, 30)).toBe(true)
  })

  it('returns true for video at end when target is mid-video', () => {
    // Video at duration end, target mid-way
    expect(needsSeekBeforePlay(12.833, 6.667, 30)).toBe(true)
  })
})
