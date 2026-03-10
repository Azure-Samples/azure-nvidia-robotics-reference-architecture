import { act, renderHook } from '@testing-library/react'
import type { SyntheticEvent } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useAnnotationWorkspaceVideoSync } from '@/components/annotation-workspace/useAnnotationWorkspaceVideoSync'
import type { FrameInsertion } from '@/types/episode-edit'

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

  it('re-arms autoplay when videoSrc changes between episodes', () => {
    const togglePlayback = vi.fn()
    const baseProps = {
      currentFrame: 0,
      totalFrames: 12,
      originalFrameIndex: 0,
      activePlaybackRange: null as [number, number] | null,
      playbackRangeStart: 0,
      playbackRangeEnd: 11,
      isPlaying: false,
      playbackSpeed: 1,
      autoPlay: true,
      autoLoop: false,
      shouldLoopPlaybackRange: false,
      datasetFps: 24,
      insertedFrames: new Map<number, FrameInsertion>(),
      removedFrames: new Set<number>(),
      videoSrc: '/videos/episode-0.mp4',
      onSetCurrentFrame: vi.fn(),
      onTogglePlayback: togglePlayback,
      onSetFrameWithinPlaybackRange: vi.fn(),
      onRecordEvent: vi.fn(),
    }

    const { result, rerender } = renderHook(
      (props) => useAnnotationWorkspaceVideoSync(props),
      { initialProps: baseProps },
    )

    const video = document.createElement('video')
    Object.defineProperty(video, 'duration', { configurable: true, value: 8.4 })

    act(() => {
      result.current.handleLoadedMetadata({ currentTarget: video } as SyntheticEvent<HTMLVideoElement>)
    })

    expect(togglePlayback).toHaveBeenCalledTimes(1)

    rerender({ ...baseProps, videoSrc: '/videos/episode-1.mp4' })

    act(() => {
      result.current.handleLoadedMetadata({ currentTarget: video } as SyntheticEvent<HTMLVideoElement>)
    })

    expect(togglePlayback).toHaveBeenCalledTimes(2)
  })

  it('re-arms autoplay when totalFrames changes between frame-only episodes', () => {
    const togglePlayback = vi.fn()
    const baseProps = {
      currentFrame: 0,
      totalFrames: 100,
      originalFrameIndex: 0,
      activePlaybackRange: null as [number, number] | null,
      playbackRangeStart: 0,
      playbackRangeEnd: 99,
      isPlaying: false,
      playbackSpeed: 1,
      autoPlay: true,
      autoLoop: false,
      shouldLoopPlaybackRange: false,
      datasetFps: 30,
      insertedFrames: new Map<number, FrameInsertion>(),
      removedFrames: new Set<number>(),
      videoSrc: null,
      onSetCurrentFrame: vi.fn(),
      onTogglePlayback: togglePlayback,
      onSetFrameWithinPlaybackRange: vi.fn(),
      onRecordEvent: vi.fn(),
    }

    const { rerender } = renderHook(
      (props) => useAnnotationWorkspaceVideoSync(props),
      { initialProps: baseProps },
    )

    expect(togglePlayback).toHaveBeenCalledTimes(1)

    rerender({ ...baseProps, isPlaying: true })
    rerender({ ...baseProps, totalFrames: 185, playbackRangeEnd: 184, isPlaying: false })

    expect(togglePlayback).toHaveBeenCalledTimes(2)

    rerender({ ...baseProps, totalFrames: 185, playbackRangeEnd: 184, isPlaying: true })
    rerender({ ...baseProps, totalFrames: 118, playbackRangeEnd: 117, isPlaying: false })

    expect(togglePlayback).toHaveBeenCalledTimes(3)
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
