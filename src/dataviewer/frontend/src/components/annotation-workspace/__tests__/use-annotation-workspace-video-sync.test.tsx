import { act, renderHook } from '@testing-library/react'
import type { SyntheticEvent } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useAnnotationWorkspaceVideoSync } from '@/components/annotation-workspace/useAnnotationWorkspaceVideoSync'

describe('useAnnotationWorkspaceVideoSync', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  it('requests playback after metadata loads when autoplay is armed', () => {
    const togglePlayback = vi.fn()
    const { result } = renderHook(() => useAnnotationWorkspaceVideoSync({
      currentFrame: 0,
      totalFrames: 12,
      originalFrameIndex: 0,
      activePlaybackRange: null,
      playbackRangeStart: 0,
      playbackRangeEnd: 11,
      isPlaying: false,
      playbackSpeed: 1,
      autoPlay: true,
      autoLoop: false,
      shouldLoopPlaybackRange: false,
      datasetFps: 24,
      insertedFrames: new Map(),
      removedFrames: new Set(),
      videoSrc: '/videos/wrist.mp4',
      onSetCurrentFrame: vi.fn(),
      onTogglePlayback: togglePlayback,
      onSetFrameWithinPlaybackRange: vi.fn(),
      onRecordEvent: vi.fn(),
    }))

    const video = document.createElement('video')
    Object.defineProperty(video, 'duration', { configurable: true, value: 8.4 })

    act(() => {
      result.current.handleLoadedMetadata({ currentTarget: video } as SyntheticEvent<HTMLVideoElement>)
    })

    expect(togglePlayback).toHaveBeenCalledTimes(1)
  })

  it('jumps to the playback range start when the video ends in loop mode', () => {
    const setFrameWithinPlaybackRange = vi.fn()
    const { result } = renderHook(() => useAnnotationWorkspaceVideoSync({
      currentFrame: 8,
      totalFrames: 12,
      originalFrameIndex: 8,
      activePlaybackRange: [3, 9],
      playbackRangeStart: 3,
      playbackRangeEnd: 9,
      isPlaying: true,
      playbackSpeed: 1,
      autoPlay: false,
      autoLoop: true,
      shouldLoopPlaybackRange: true,
      datasetFps: 24,
      insertedFrames: new Map(),
      removedFrames: new Set(),
      videoSrc: '/videos/wrist.mp4',
      onSetCurrentFrame: vi.fn(),
      onTogglePlayback: vi.fn(),
      onSetFrameWithinPlaybackRange: setFrameWithinPlaybackRange,
      onRecordEvent: vi.fn(),
    }))

    act(() => {
      result.current.handleVideoEnded()
    })

    expect(setFrameWithinPlaybackRange).toHaveBeenCalledWith(3)
  })
})
