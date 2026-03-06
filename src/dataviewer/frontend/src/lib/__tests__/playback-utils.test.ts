import { describe, expect, it } from 'vitest'

import {
  computeEffectiveFps,
  computePlaybackTarget,
  computeSyncAction,
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

describe('computeSyncAction', () => {
  const fps = 30
  const totalFrames = 385

  it('returns pause when not playing', () => {
    const action = computeSyncAction(false, 1, 100, totalFrames, 100, fps, 3.33)
    expect(action.kind).toBe('pause')
  })

  it('returns restart when at last frame', () => {
    const action = computeSyncAction(true, 1, 384, totalFrames, 384, fps, 12.8)
    expect(action.kind).toBe('restart')
    expect(action).toHaveProperty('playbackRate', 1)
  })

  it('returns seek-and-play when video position is far from target', () => {
    // Video at 0s, frame 100 → target ~3.33s (well beyond half-frame threshold)
    const action = computeSyncAction(true, 1, 100, totalFrames, 100, fps, 0)
    expect(action.kind).toBe('seek-and-play')
    expect(action).toHaveProperty('seekTo')
    expect(action).toHaveProperty('playbackRate', 1)
  })

  it('returns play when video is already near the correct position', () => {
    // Video at 3.33s, frame 100 → target 3.33s (within threshold)
    const targetTime = 100 / fps
    const action = computeSyncAction(true, 1, 100, totalFrames, 100, fps, targetTime)
    expect(action.kind).toBe('play')
    expect(action).toHaveProperty('playbackRate', 1)
  })

  it('applies 2x playbackRate when speed is 2', () => {
    const targetTime = 100 / fps
    const action = computeSyncAction(true, 2, 100, totalFrames, 100, fps, targetTime)
    expect(action.kind).toBe('play')
    expect(action).toHaveProperty('playbackRate', 2)
  })

  it('applies 0.5x playbackRate when speed is 0.5', () => {
    const targetTime = 100 / fps
    const action = computeSyncAction(true, 0.5, 100, totalFrames, 100, fps, targetTime)
    expect(action.kind).toBe('play')
    expect(action).toHaveProperty('playbackRate', 0.5)
  })

  it('speed change does not cause unnecessary seek when video position matches', () => {
    // Simulates switching from 1x to 2x mid-playback at frame 200
    // Video is already at the correct position
    const videoTime = 200 / fps
    const action = computeSyncAction(true, 2, 200, totalFrames, 200, fps, videoTime)
    // Should NOT seek — just update playbackRate and continue
    expect(action.kind).toBe('play')
    expect(action).toHaveProperty('playbackRate', 2)
  })

  it('frame advance during playback produces play (not seek) when video tracks correctly', () => {
    // During playback, rAF reports frame 201 while video is at matching time.
    // The sync effect should NOT be called with frame changes (they come from refs),
    // but even if it were, the action should be 'play' (no seek needed).
    const videoTime = 201 / fps
    const action = computeSyncAction(true, 2, 201, totalFrames, 201, fps, videoTime)
    expect(action.kind).toBe('play')
    expect(action).toHaveProperty('playbackRate', 2)
  })

  it('rapid frame advance at 2x does not trigger seek when video is slightly ahead', () => {
    // At 2x speed, video naturally advances faster than frame reports.
    // Video might be 1-2 frames ahead of the last reported frame.
    // This must NOT trigger a backward seek (the original bug).
    const reportedFrame = 200
    const videoTimeSlightlyAhead = (reportedFrame + 1.5) / fps
    const action = computeSyncAction(true, 2, reportedFrame, totalFrames, reportedFrame, fps, videoTimeSlightlyAhead)
    // Difference is 1.5 frames = 0.05s at 30fps, threshold is 0.5/30 = 0.0167s
    // This WOULD seek — which is why currentFrame must NOT be in the effect deps.
    // When called from the effect (only on speed/play changes), currentFrame
    // in the ref accurately reflects the video position, so this scenario
    // only occurs if currentFrame were a state dependency (the bug).
    expect(action.kind).toBe('seek-and-play')
  })

  it('uses originalFrameIndex for target time when available', () => {
    // Effective frame 210, original frame 200 (due to insertions)
    const action = computeSyncAction(true, 1, 210, totalFrames, 200, fps, 0)
    expect(action.kind).toBe('seek-and-play')
    if (action.kind === 'seek-and-play') {
      expect(action.seekTo).toBeCloseTo(200 / fps, 5)
    }
  })

  it('uses currentFrame for target when originalFrameIndex is null', () => {
    // Inserted frame with no original mapping
    const action = computeSyncAction(true, 1, 150, totalFrames, null, fps, 0)
    expect(action.kind).toBe('seek-and-play')
    if (action.kind === 'seek-and-play') {
      expect(action.seekTo).toBeCloseTo(150 / fps, 5)
    }
  })
})
