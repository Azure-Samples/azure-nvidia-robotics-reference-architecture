import { type SyntheticEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react'

import { combineCssFilters } from '@/lib/css-filters'
import {
  clampFrameToPlaybackRange,
  computeEffectiveFps,
  computeSyncAction,
  resolvePlaybackTick,
  shouldRecoverPlaybackAfterDesync,
  shouldRestartPlaybackAfterLoop,
} from '@/lib/playback-utils'
import { getOriginalIndex } from '@/stores/edit-store-frame-utils'
import type { DatasetInfo, EpisodeData } from '@/types'
import type { ColorAdjustment, FrameInsertion, ImageTransform } from '@/types/episode-edit'

const PLAYBACK_RECOVERY_COOLDOWN_MS = 300

interface UseAnnotationWorkspaceMediaControllerOptions {
  currentDataset: DatasetInfo | null
  currentEpisode: EpisodeData | null
  currentFrame: number
  totalFrames: number
  originalFrameIndex: number | null
  activePlaybackRange: [number, number] | null
  playbackRangeStart: number
  playbackRangeEnd: number
  isPlaying: boolean
  playbackSpeed: number
  autoPlay: boolean
  autoLoop: boolean
  shouldLoopPlaybackRange: boolean
  displayAdjustment: ColorAdjustment | null
  displayActive: boolean
  globalTransform: ImageTransform | null
  insertedFrames: Map<number, FrameInsertion>
  removedFrames: Set<number>
  onSetCurrentFrame: (frame: number) => void
  onTogglePlayback: () => void
  onSetFrameWithinPlaybackRange: (frame: number) => void
  onRecordEvent: (channel: string, type: string, data?: Record<string, unknown>) => void
}

export function useAnnotationWorkspaceMediaController({
  currentDataset,
  currentEpisode,
  currentFrame,
  totalFrames,
  originalFrameIndex,
  activePlaybackRange,
  playbackRangeStart,
  playbackRangeEnd,
  isPlaying,
  playbackSpeed,
  autoPlay,
  autoLoop,
  shouldLoopPlaybackRange,
  displayAdjustment,
  displayActive,
  globalTransform,
  insertedFrames,
  removedFrames,
  onSetCurrentFrame,
  onTogglePlayback,
  onSetFrameWithinPlaybackRange,
  onRecordEvent,
}: UseAnnotationWorkspaceMediaControllerOptions) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const videoRef = useRef<HTMLVideoElement>(null)
  const currentFrameRef = useRef(0)
  const originalFrameIndexRef = useRef<number | null>(null)
  const shouldAutoPlayOnMetadataLoadRef = useRef(false)
  const skipNextPlaybackSyncRef = useRef(false)
  const playbackRetryTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastPlaybackRecoveryAtRef = useRef(0)
  const [interpolatedImageUrl, setInterpolatedImageUrl] = useState<string | null>(null)
  const [videoDuration, setVideoDuration] = useState(0)

  useEffect(() => {
    return () => {
      if (playbackRetryTimeoutRef.current) {
        clearTimeout(playbackRetryTimeoutRef.current)
      }
    }
  }, [])

  const displayFilter = useMemo(
    () => combineCssFilters(
      displayAdjustment ?? undefined,
      displayActive,
      globalTransform?.colorAdjustment,
      globalTransform?.colorFilter,
    ),
    [displayAdjustment, displayActive, globalTransform?.colorAdjustment, globalTransform?.colorFilter],
  )

  const cameraName = useMemo(() => {
    if (!currentEpisode?.videoUrls) {
      return null
    }

    const keys = Object.keys(currentEpisode.videoUrls)
    return keys.length > 0 ? keys[0] : null
  }, [currentEpisode?.videoUrls])

  const videoSrc = useMemo(() => {
    if (!currentEpisode?.videoUrls || !cameraName) {
      return null
    }

    return currentEpisode.videoUrls[cameraName]
  }, [cameraName, currentEpisode?.videoUrls])

  const isInsertedFrame = originalFrameIndex === null

  const adjacentFrames = useMemo(() => {
    if (!isInsertedFrame) {
      return null
    }

    const originalFrameCount = currentEpisode?.meta.length ?? currentEpisode?.trajectoryData?.length ?? totalFrames
    const sortedInsertions = Array.from(insertedFrames.keys())
      .filter((afterIdx) => !removedFrames.has(afterIdx) && afterIdx < originalFrameCount - 1)
      .sort((a, b) => a - b)

    for (const afterIdx of sortedInsertions) {
      let insertPos = afterIdx + 1

      for (const removedIdx of removedFrames) {
        if (removedIdx <= afterIdx) {
          insertPos--
        }
      }

      for (const prevIdx of sortedInsertions) {
        if (prevIdx < afterIdx) {
          insertPos++
        }
      }

      if (insertPos === currentFrame) {
        const insertion = insertedFrames.get(afterIdx)
        return {
          beforeFrame: afterIdx,
          afterFrame: afterIdx + 1,
          factor: insertion?.interpolationFactor ?? 0.5,
        }
      }
    }

    return null
  }, [currentEpisode?.meta.length, currentEpisode?.trajectoryData?.length, currentFrame, insertedFrames, isInsertedFrame, removedFrames, totalFrames])

  const frameImageUrl = useMemo(() => {
    if (!currentDataset || !currentEpisode || !cameraName || originalFrameIndex === null) {
      return null
    }

    return `/api/datasets/${currentDataset.id}/episodes/${currentEpisode.meta.index}/frames/${originalFrameIndex}?camera=${encodeURIComponent(cameraName)}`
  }, [cameraName, currentDataset, currentEpisode, originalFrameIndex])

  currentFrameRef.current = currentFrame
  originalFrameIndexRef.current = originalFrameIndex

  const datasetFps = currentDataset?.fps ?? 30
  const fps = computeEffectiveFps(totalFrames, videoDuration, datasetFps)

  const ensureVideoPlaybackAtTime = useCallback((video: HTMLVideoElement, targetTime: number) => {
    const playbackStartTime = Number.isFinite(video.duration)
      ? Math.max(0, Math.min(targetTime + 0.001, Math.max(video.duration - 0.001, 0)))
      : Math.max(0, targetTime + 0.001)

    if (playbackRetryTimeoutRef.current) {
      clearTimeout(playbackRetryTimeoutRef.current)
      playbackRetryTimeoutRef.current = null
    }

    video.pause()
    video.currentTime = playbackStartTime
    video.playbackRate = playbackSpeed
    video.play().catch(() => {})

    playbackRetryTimeoutRef.current = setTimeout(() => {
      playbackRetryTimeoutRef.current = null

      if (Math.abs(video.currentTime - playbackStartTime) <= 0.5 / fps) {
        video.pause()
        video.currentTime = playbackStartTime
        video.playbackRate = playbackSpeed
        video.play().catch(() => {})
      }
    }, 180)
  }, [fps, playbackSpeed])

  const seekVideoFrame = useCallback((frame: number, range: [number, number] | null, constrainToRange = true) => {
    const nextFrame = constrainToRange
      ? clampFrameToPlaybackRange(frame, totalFrames, range)
      : Math.max(0, Math.min(frame, Math.max(totalFrames - 1, 0)))

    onSetCurrentFrame(nextFrame)

    const video = videoRef.current

    if (!video) {
      return nextFrame
    }

    const targetOriginalFrame = getOriginalIndex(nextFrame, insertedFrames, removedFrames)
    const targetTime = (targetOriginalFrame ?? nextFrame) / fps

    if (Math.abs(video.currentTime - targetTime) > 0.5 / fps) {
      video.currentTime = targetTime
    }

    if (isPlaying) {
      ensureVideoPlaybackAtTime(video, targetTime)
    }

    return nextFrame
  }, [ensureVideoPlaybackAtTime, fps, insertedFrames, isPlaying, onSetCurrentFrame, removedFrames, totalFrames])

  const handleResumePlayback = useCallback((nextFrame: number) => {
    requestAnimationFrame(() => {
      const video = videoRef.current

      if (!video) {
        return
      }

      const targetOriginalFrame = getOriginalIndex(nextFrame, insertedFrames, removedFrames)
      const targetTime = (targetOriginalFrame ?? nextFrame) / fps

      ensureVideoPlaybackAtTime(video, targetTime)
    })
  }, [ensureVideoPlaybackAtTime, fps, insertedFrames, removedFrames])

  useEffect(() => {
    shouldAutoPlayOnMetadataLoadRef.current = autoPlay
  }, [autoPlay, currentDataset?.id, currentEpisode?.meta.index])

  useEffect(() => {
    if (!isInsertedFrame || !adjacentFrames || !currentDataset || !currentEpisode || !cameraName) {
      setInterpolatedImageUrl(null)
      return
    }

    const canvas = canvasRef.current
    if (!canvas) {
      return
    }

    const ctx = canvas.getContext('2d')
    if (!ctx) {
      return
    }

    const encodedCamera = encodeURIComponent(cameraName)
    const beforeUrl = `/api/datasets/${currentDataset.id}/episodes/${currentEpisode.meta.index}/frames/${adjacentFrames.beforeFrame}?camera=${encodedCamera}`
    const afterUrl = `/api/datasets/${currentDataset.id}/episodes/${currentEpisode.meta.index}/frames/${adjacentFrames.afterFrame}?camera=${encodedCamera}`

    const img1 = new Image()
    const img2 = new Image()
    let loadedCount = 0

    const blend = () => {
      loadedCount++
      if (loadedCount < 2) {
        return
      }

      canvas.width = img1.width
      canvas.height = img1.height

      ctx.globalAlpha = 1 - adjacentFrames.factor
      ctx.drawImage(img1, 0, 0)

      ctx.globalAlpha = adjacentFrames.factor
      ctx.drawImage(img2, 0, 0)

      ctx.globalAlpha = 1
      setInterpolatedImageUrl(canvas.toDataURL('image/jpeg', 0.9))
    }

    img1.onload = blend
    img2.onload = blend
    img1.src = beforeUrl
    img2.src = afterUrl

    return () => {
      img1.onload = null
      img2.onload = null
    }
  }, [adjacentFrames, cameraName, currentDataset, currentEpisode, isInsertedFrame])

  const syncVideoElementPlayback = useCallback((video: HTMLVideoElement) => {
    const action = computeSyncAction(
      isPlaying,
      playbackSpeed,
      currentFrameRef.current,
      totalFrames,
      originalFrameIndexRef.current,
      fps,
      video.currentTime,
      playbackRangeStart,
      playbackRangeEnd,
    )

    onRecordEvent('playback', 'sync-action', {
      action: action.kind,
      currentFrame: currentFrameRef.current,
      playbackRangeStart,
      playbackRangeEnd,
      isPlaying,
      autoLoop,
      shouldLoopPlaybackRange,
      videoCurrentTime: Number(video.currentTime.toFixed(3)),
    })

    switch (action.kind) {
      case 'restart':
        onSetFrameWithinPlaybackRange(playbackRangeStart)
        ensureVideoPlaybackAtTime(video, playbackRangeStart / fps)
        break
      case 'seek-and-play':
        ensureVideoPlaybackAtTime(video, action.seekTo)
        break
      case 'play':
        ensureVideoPlaybackAtTime(video, video.currentTime)
        break
      case 'pause':
        video.pause()
        break
    }
  }, [autoLoop, ensureVideoPlaybackAtTime, fps, isPlaying, onRecordEvent, onSetFrameWithinPlaybackRange, playbackRangeEnd, playbackRangeStart, playbackSpeed, shouldLoopPlaybackRange, totalFrames])

  const handleLoadedMetadata = useCallback((event: SyntheticEvent<HTMLVideoElement>) => {
    const video = event.currentTarget

    setVideoDuration(video.duration)
    onRecordEvent('playback', 'loaded-metadata', {
      duration: Number(video.duration.toFixed(3)),
      isPlaying,
      shouldAutoPlayOnMetadataLoad: shouldAutoPlayOnMetadataLoadRef.current,
    })

    if (isPlaying) {
      skipNextPlaybackSyncRef.current = true
      syncVideoElementPlayback(video)
      return
    }

    if (shouldAutoPlayOnMetadataLoadRef.current) {
      shouldAutoPlayOnMetadataLoadRef.current = false
      onTogglePlayback()
    }
  }, [isPlaying, onRecordEvent, onTogglePlayback, syncVideoElementPlayback])

  useEffect(() => {
    const video = videoRef.current
    if (!video || !videoSrc) {
      return
    }

    if (skipNextPlaybackSyncRef.current) {
      skipNextPlaybackSyncRef.current = false
      return
    }

    syncVideoElementPlayback(video)
  }, [syncVideoElementPlayback, videoSrc])

  useEffect(() => {
    if (!isPlaying) {
      return
    }

    let rafId: number
    let lastFrame = -1

    const tick = () => {
      const video = videoRef.current

      if (video) {
        const nextFrame = Math.floor(video.currentTime * fps)
        const resolved = resolvePlaybackTick(nextFrame, totalFrames, activePlaybackRange, shouldLoopPlaybackRange)
        const now = Date.now()

        if (shouldRecoverPlaybackAfterDesync(
          isPlaying,
          video.paused,
          now - lastPlaybackRecoveryAtRef.current,
          PLAYBACK_RECOVERY_COOLDOWN_MS,
        )) {
          lastPlaybackRecoveryAtRef.current = now
          onRecordEvent('playback', 'desync-recover', {
            currentFrame: resolved.frame,
            nextFrame,
            videoCurrentTime: Number(video.currentTime.toFixed(3)),
            playbackRangeStart,
            playbackRangeEnd,
            autoLoop,
            shouldLoopPlaybackRange,
          })
          ensureVideoPlaybackAtTime(video, resolved.frame / fps)
        }

        if (resolved.frame !== lastFrame) {
          lastFrame = resolved.frame
          onSetCurrentFrame(resolved.frame)
        }

        if (resolved.shouldStop) {
          if (isPlaying) {
            onTogglePlayback()
          }

          video.currentTime = resolved.frame / fps
          video.pause()
          return
        }

        if (resolved.frame !== nextFrame) {
          const didLoop = shouldRestartPlaybackAfterLoop(
            nextFrame,
            resolved.frame,
            activePlaybackRange,
            shouldLoopPlaybackRange,
          )

          if (didLoop) {
            onRecordEvent('playback', 'range-loop', {
              rangeStart: playbackRangeStart,
              rangeEnd: playbackRangeEnd,
              reportedFrame: nextFrame,
              resolvedFrame: resolved.frame,
              autoLoop,
              shouldLoopPlaybackRange,
            })
          }

          if (didLoop) {
            ensureVideoPlaybackAtTime(video, resolved.frame / fps)
          } else {
            video.currentTime = resolved.frame / fps
          }
        }
      }

      rafId = requestAnimationFrame(tick)
    }

    rafId = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(rafId)
  }, [activePlaybackRange, autoLoop, ensureVideoPlaybackAtTime, fps, isPlaying, onRecordEvent, onSetCurrentFrame, onTogglePlayback, playbackRangeEnd, playbackRangeStart, shouldLoopPlaybackRange, totalFrames])

  useEffect(() => {
    const video = videoRef.current
    if (!video || isPlaying) {
      return
    }

    const targetTime = (originalFrameIndex ?? currentFrame) / fps
    if (Math.abs(video.currentTime - targetTime) > 0.5 / fps) {
      video.currentTime = targetTime
    }
  }, [currentFrame, fps, isPlaying, originalFrameIndex])

  const handleVideoEnded = useCallback(() => {
    onRecordEvent('playback', 'video-ended', {
      playbackRangeStart,
      playbackRangeEnd,
      autoLoop,
      shouldLoopPlaybackRange,
    })

    if (shouldLoopPlaybackRange) {
      const video = videoRef.current
      onSetFrameWithinPlaybackRange(playbackRangeStart)

      if (video) {
        ensureVideoPlaybackAtTime(video, playbackRangeStart / fps)
      }

      return
    }

    if (isPlaying) {
      onTogglePlayback()
    }

    onSetFrameWithinPlaybackRange(playbackRangeEnd)
  }, [autoLoop, ensureVideoPlaybackAtTime, fps, isPlaying, onRecordEvent, onSetFrameWithinPlaybackRange, onTogglePlayback, playbackRangeEnd, playbackRangeStart, shouldLoopPlaybackRange])

  return {
    canvasRef,
    videoRef,
    cameraName,
    displayFilter,
    frameImageUrl,
    handleLoadedMetadata,
    handleResumePlayback,
    handleVideoEnded,
    interpolatedImageUrl,
    isInsertedFrame,
    seekVideoFrame,
    videoSrc,
  }
}
