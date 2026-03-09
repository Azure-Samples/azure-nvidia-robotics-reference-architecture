import { type SyntheticEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react';

import {
  AnnotationWorkspaceDiagnosticsPanel,
} from '@/components/annotation-workspace/AnnotationWorkspaceDiagnosticsPanel';
import { AnnotationWorkspaceEditToolsPanel } from '@/components/annotation-workspace/AnnotationWorkspaceEditToolsPanel';
import { AnnotationWorkspaceEmptyState } from '@/components/annotation-workspace/AnnotationWorkspaceEmptyState';
import { AnnotationWorkspacePlaybackCard } from '@/components/annotation-workspace/AnnotationWorkspacePlaybackCard';
import { AnnotationWorkspaceSubtaskListCard } from '@/components/annotation-workspace/AnnotationWorkspaceSubtaskListCard';
import { AnnotationWorkspaceTopBar } from '@/components/annotation-workspace/AnnotationWorkspaceTopBar';
import { AnnotationWorkspaceTrajectoryTab } from '@/components/annotation-workspace/AnnotationWorkspaceTrajectoryTab';
import { useAnnotationWorkspaceDiagnostics } from '@/components/annotation-workspace/useAnnotationWorkspaceDiagnostics';
import { useAnnotationWorkspaceEpisodeActions } from '@/components/annotation-workspace/useAnnotationWorkspaceEpisodeActions';
import { useAnnotationWorkspacePlayback } from '@/components/annotation-workspace/useAnnotationWorkspacePlayback';
import { ExportDialog } from '@/components/export';
import { DetectionPanel } from '@/components/object-detection';
import { Tabs, TabsContent } from '@/components/ui/tabs';
import { useSaveEpisodeLabels } from '@/hooks/use-labels';
import { combineCssFilters } from '@/lib/css-filters';
import {
  isDiagnosticsEnabled,
  recordDiagnosticEvent,
} from '@/lib/playback-diagnostics';
import {
  clampFrameToPlaybackRange,
  computeEffectiveFps,
  computeSyncAction,
  resolvePlaybackTick,
  shouldRecoverPlaybackAfterDesync,
  shouldRestartPlaybackAfterLoop,
} from '@/lib/playback-utils';
import {
  useDatasetStore,
  useEditDirtyState,
  useEditStore,
  useEpisodeStore,
  usePlaybackControls,
  usePlaybackSettings,
  useViewerDisplay,
} from '@/stores';
import {
  getEffectiveFrameCount,
  getOriginalIndex,
  useFrameInsertionState,
} from '@/stores/edit-store';
import { useLabelStore } from '@/stores/label-store';
import { createDefaultSubtask } from '@/types/episode-edit';

const EMPTY_LABELS: string[] = [];
const PLAYBACK_RECOVERY_COOLDOWN_MS = 300;

interface AnnotationWorkspaceProps {
  diagnosticsVisible?: boolean;
  canGoPreviousEpisode?: boolean;
  onPreviousEpisode?: () => void;
  canGoNextEpisode?: boolean;
  onNextEpisode?: () => void;
  onSaveAndNextEpisode?: () => void;
}

/**
 * Unified annotation workspace integrating episode viewing, editing, and export.
 *
 * Uses native <video> for smooth playback and per-frame <img> for
 * frame-accurate scrubbing when paused.
 */
export function AnnotationWorkspace({
  diagnosticsVisible = isDiagnosticsEnabled(),
  canGoPreviousEpisode = false,
  onPreviousEpisode,
  canGoNextEpisode = false,
  onNextEpisode,
  onSaveAndNextEpisode,
}: AnnotationWorkspaceProps) {
  const [exportDialogOpen, setExportDialogOpen] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const currentFrameRef = useRef(0);
  const originalFrameIndexRef = useRef<number | null>(null);
  const shouldAutoPlayOnMetadataLoadRef = useRef(false);
  const skipNextPlaybackSyncRef = useRef(false);
  const playbackRetryTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastPlaybackRecoveryAtRef = useRef(0);
  const [interpolatedImageUrl, setInterpolatedImageUrl] = useState<string | null>(null);
  const [videoDuration, setVideoDuration] = useState(0);
  const [activeTab, setActiveTab] = useState('episode');

  const currentDataset = useDatasetStore((state) => state.currentDataset);
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);
  const labelDataLoaded = useLabelStore((state) => state.isLoaded);
  const availableLabels = useLabelStore((state) => state.availableLabels);
  const episodeLabels = useLabelStore((state) => state.episodeLabels);
  const savedEpisodeLabels = useLabelStore((state) => state.savedEpisodeLabels);
  const setEpisodeLabelsInStore = useLabelStore((state) => state.setEpisodeLabels);
  const removedFrames = useEditStore((state) => state.removedFrames);
  const initializeEdit = useEditStore((state) => state.initializeEdit);
  const clearTransforms = useEditStore((state) => state.clearTransforms);
  const saveEpisodeDraft = useEditStore((state) => state.saveEpisodeDraft);
  const editDatasetId = useEditStore((state) => state.datasetId);
  const editEpisodeIndex = useEditStore((state) => state.episodeIndex);
  const { insertedFrames } = useFrameInsertionState();
  const { isDirty: hasEdits, resetEdits } = useEditDirtyState();
  const { currentFrame, isPlaying, playbackSpeed, setCurrentFrame, togglePlayback, setPlaybackSpeed } = usePlaybackControls();
  const { displayAdjustment, isActive: displayActive } = useViewerDisplay();
  const { autoPlay, autoLoop, setAutoPlay, setAutoLoop } = usePlaybackSettings();
  const globalTransform = useEditStore((state) => state.globalTransform);
  const saveEpisodeLabels = useSaveEpisodeLabels();
  const subtasks = useEditStore((state) => state.subtasks);
  const addSubtask = useEditStore((state) => state.addSubtask);
  const currentEpisodeLabels = useMemo(() => {
    if (!currentEpisode) {
      return EMPTY_LABELS;
    }

    return episodeLabels[currentEpisode.meta.index] ?? EMPTY_LABELS;
  }, [currentEpisode, episodeLabels]);
  const savedLabelsForCurrentEpisode = useMemo(() => {
    if (!currentEpisode) {
      return EMPTY_LABELS;
    }

    return savedEpisodeLabels[currentEpisode.meta.index] ?? EMPTY_LABELS;
  }, [currentEpisode, savedEpisodeLabels]);

  useEffect(() => {
    return () => {
      if (playbackRetryTimeoutRef.current) {
        clearTimeout(playbackRetryTimeoutRef.current);
      }
    };
  }, []);

  const diagnosticsEnabled = diagnosticsVisible && isDiagnosticsEnabled();

  const {
    hasPendingEpisodeChanges,
    saveStatusMessage,
    handleResetAll,
    handleSaveAndNextEpisode,
  } = useAnnotationWorkspaceEpisodeActions({
    diagnosticsEnabled,
    currentDatasetId: currentDataset?.id ?? null,
    currentEpisodeIndex: currentEpisode?.meta.index ?? null,
    currentEpisodeLabels,
    savedLabelsForCurrentEpisode,
    availableLabels,
    labelDataLoaded,
    hasEdits,
    onResetEdits: resetEdits,
    onSetEpisodeLabels: setEpisodeLabelsInStore,
    onSaveEpisodeDraft: saveEpisodeDraft,
    onSaveEpisodeLabels: saveEpisodeLabels.mutateAsync,
    onRecordEvent: recordDiagnosticEvent,
    canGoNextEpisode,
    onAdvanceToNextEpisode: onSaveAndNextEpisode ?? onNextEpisode,
  });

  const displayFilter = useMemo(
    () => combineCssFilters(
      displayAdjustment, displayActive,
      globalTransform?.colorAdjustment, globalTransform?.colorFilter,
    ),
    [displayAdjustment, displayActive, globalTransform?.colorAdjustment, globalTransform?.colorFilter],
  );

  // Initialize edit store when dataset/episode changes
  useEffect(() => {
    if (currentDataset && currentEpisode) {
      const newDatasetId = currentDataset.id;
      const newEpisodeIndex = currentEpisode.meta.index;

      if (editDatasetId !== newDatasetId || editEpisodeIndex !== newEpisodeIndex) {
        initializeEdit(newDatasetId, newEpisodeIndex);
      }
    }
  }, [currentDataset, currentEpisode, editDatasetId, editEpisodeIndex, initializeEdit]);

  // Calculate original frame count from episode data
  const originalFrameCount = useMemo(() => {
    if (currentEpisode?.meta.length) {
      return currentEpisode.meta.length;
    }
    if (currentEpisode?.trajectoryData?.length) {
      return currentEpisode.trajectoryData.length;
    }
    return 100;
  }, [currentEpisode]);

  const datasetFps = currentDataset?.fps ?? 30;

  // Calculate effective frame count including insertions and removals
  const totalFrames = useMemo(() => {
    return getEffectiveFrameCount(originalFrameCount, insertedFrames, removedFrames);
  }, [originalFrameCount, insertedFrames, removedFrames]);

  // Map current effective frame to original frame index
  const originalFrameIndex = useMemo(() => {
    return getOriginalIndex(currentFrame, insertedFrames, removedFrames);
  }, [currentFrame, insertedFrames, removedFrames]);

  // Check if current frame is an inserted (interpolated) frame
  const isInsertedFrame = originalFrameIndex === null;

  // For inserted frames, find adjacent original frames
  const adjacentFrames = useMemo(() => {
    if (!isInsertedFrame) return null;

    const sortedInsertions = Array.from(insertedFrames.keys())
      .filter((afterIdx) => !removedFrames.has(afterIdx) && afterIdx < originalFrameCount - 1)
      .sort((a, b) => a - b);

    for (const afterIdx of sortedInsertions) {
      let insertPos = afterIdx + 1;
      for (const removedIdx of removedFrames) {
        if (removedIdx <= afterIdx) insertPos--;
      }
      for (const prevIdx of sortedInsertions) {
        if (prevIdx < afterIdx) insertPos++;
      }

      if (insertPos === currentFrame) {
        const insertion = insertedFrames.get(afterIdx);
        return {
          beforeFrame: afterIdx,
          afterFrame: afterIdx + 1,
          factor: insertion?.interpolationFactor ?? 0.5,
        };
      }
    }
    return null;
  }, [isInsertedFrame, currentFrame, insertedFrames, removedFrames, originalFrameCount]);

  // Keep refs in sync for the play/pause sync effect (avoids feedback loop)
  currentFrameRef.current = currentFrame;
  originalFrameIndexRef.current = originalFrameIndex;

  // Derive effective fps from the video's actual duration to avoid
  // mismatches between dataset metadata fps and video encoding fps.
  const fps = computeEffectiveFps(totalFrames, videoDuration, datasetFps);
  const ensureVideoPlaybackAtTime = useCallback((video: HTMLVideoElement, targetTime: number) => {
    const playbackStartTime = Number.isFinite(video.duration)
      ? Math.max(0, Math.min(targetTime + 0.001, Math.max(video.duration - 0.001, 0)))
      : Math.max(0, targetTime + 0.001);

    if (playbackRetryTimeoutRef.current) {
      clearTimeout(playbackRetryTimeoutRef.current);
      playbackRetryTimeoutRef.current = null;
    }

    video.pause();
    video.currentTime = playbackStartTime;
    video.playbackRate = playbackSpeed;
    video.play().catch(() => { /* autoplay may be blocked */ });

    playbackRetryTimeoutRef.current = setTimeout(() => {
      playbackRetryTimeoutRef.current = null;

      if (Math.abs(video.currentTime - playbackStartTime) <= 0.5 / fps) {
        video.pause();
        video.currentTime = playbackStartTime;
        video.playbackRate = playbackSpeed;
        video.play().catch(() => { /* autoplay may be blocked */ });
      }
    }, 180);
  }, [fps, playbackSpeed]);

  const seekVideoFrame = useCallback((frame: number, range: [number, number] | null, constrainToRange = true) => {
    const nextFrame = constrainToRange
      ? clampFrameToPlaybackRange(frame, totalFrames, range)
      : Math.max(0, Math.min(frame, Math.max(totalFrames - 1, 0)));

    setCurrentFrame(nextFrame);

    const video = videoRef.current;

    if (!video) {
      return nextFrame;
    }

    const targetOriginalFrame = getOriginalIndex(nextFrame, insertedFrames, removedFrames);
    const targetTime = (targetOriginalFrame ?? nextFrame) / fps;

    if (Math.abs(video.currentTime - targetTime) > 0.5 / fps) {
      video.currentTime = targetTime;
    }

    if (isPlaying) {
      ensureVideoPlaybackAtTime(video, targetTime);
    }

    return nextFrame;
  }, [ensureVideoPlaybackAtTime, fps, insertedFrames, isPlaying, removedFrames, setCurrentFrame, totalFrames]);

  const handleTabChange = useCallback((nextTab: string) => {
    setActiveTab(nextTab);
    recordDiagnosticEvent('workspace', 'tab-change', {
      previousTab: activeTab,
      nextTab,
    });

    if (nextTab === 'detection') {
      recordDiagnosticEvent('detection', 'tab-viewed', {
        previousTab: activeTab,
        episodeIndex: currentEpisode?.meta.index ?? null,
      });
    }
  }, [activeTab, currentEpisode?.meta.index]);

  const handleResumePlayback = useCallback((nextFrame: number) => {
    requestAnimationFrame(() => {
      const video = videoRef.current;

      if (!video) {
        return;
      }

      const targetOriginalFrame = getOriginalIndex(nextFrame, insertedFrames, removedFrames);
      const targetTime = (targetOriginalFrame ?? nextFrame) / fps;

      ensureVideoPlaybackAtTime(video, targetTime);
    });
  }, [ensureVideoPlaybackAtTime, fps, insertedFrames, removedFrames]);

  const {
    activePlaybackRange,
    clearPlaybackSelection,
    handleCreateSubtaskFromRange,
    handleDraftRangeChange,
    handleGraphSeek,
    handleSelectionComplete,
    handleSelectionStart,
    handleSubtaskSelectionChange,
    playbackRangeEnd,
    playbackRangeHighlight,
    playbackRangeLabel,
    playbackRangeStart,
    selectedRange,
    selectedSubtaskId,
    setFrameWithinPlaybackRange: setFrameWithinActivePlaybackRange,
    shouldLoopPlaybackRange,
    stepFrame,
  } = useAnnotationWorkspacePlayback({
    autoLoop,
    currentFrame,
    currentDatasetId: currentDataset?.id ?? null,
    currentEpisodeIndex: currentEpisode?.meta.index ?? null,
    isPlaying,
    subtasks,
    totalFrames,
    onSeekFrame: seekVideoFrame,
    onResumePlayback: handleResumePlayback,
    onTogglePlayback: togglePlayback,
    onSetCurrentFrame: setCurrentFrame,
    onRecordEvent: recordDiagnosticEvent,
  });

  const {
    diagnosticsStateSummary,
    availableDiagnosticsChannels,
    diagnosticsClipboardStatus,
    handleClearVisibleDiagnostics,
    handleCopyDiagnostics,
    handleDownloadDiagnostics,
    recentDiagnosticEvents,
    selectedDiagnosticsChannel,
    setSelectedDiagnosticsChannel,
  } = useAnnotationWorkspaceDiagnostics({
    diagnosticsVisible,
    activeTab,
    currentDatasetId: currentDataset?.id ?? null,
    currentEpisodeIndex: currentEpisode?.meta.index ?? null,
    currentFrame,
    totalFrames,
    isPlaying,
    selectedRange,
    selectedSubtaskId,
  });

  const handleCreateSubtaskFromSelection = useCallback((range: [number, number]) => {
    const nextSegment = createDefaultSubtask(range, subtasks);

    addSubtask(nextSegment);
    handleCreateSubtaskFromRange(nextSegment);
  }, [addSubtask, handleCreateSubtaskFromRange, subtasks]);

  // Resolve the first available camera from episode video URLs
  const cameraName = useMemo(() => {
    if (!currentEpisode?.videoUrls) return null;
    const keys = Object.keys(currentEpisode.videoUrls);
    return keys.length > 0 ? keys[0] : null;
  }, [currentEpisode?.videoUrls]);

  // Video src for native playback
  const videoSrc = useMemo(() => {
    if (!currentEpisode?.videoUrls || !cameraName) return null;
    return currentEpisode.videoUrls[cameraName];
  }, [currentEpisode?.videoUrls, cameraName]);

  useEffect(() => {
    shouldAutoPlayOnMetadataLoadRef.current = autoPlay;
  }, [autoPlay, currentDataset?.id, currentEpisode?.meta.index]);

  useEffect(() => {
    if (!selectedRange) {
      return;
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') {
        return;
      }

      clearPlaybackSelection();
    };

    window.addEventListener('keydown', handleKeyDown);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [clearPlaybackSelection, selectedRange]);

  // Build frame image URL (only used when paused for frame-accurate view)
  const frameImageUrl = useMemo(() => {
    if (!currentDataset || !currentEpisode || !cameraName) return null;
    if (originalFrameIndex === null) return null;
    return `/api/datasets/${currentDataset.id}/episodes/${currentEpisode.meta.index}/frames/${originalFrameIndex}?camera=${encodeURIComponent(cameraName)}`;
  }, [currentDataset, currentEpisode, originalFrameIndex, cameraName]);

  // Generate interpolated image for inserted frames
  useEffect(() => {
    if (!isInsertedFrame || !adjacentFrames || !currentDataset || !currentEpisode || !cameraName) {
      setInterpolatedImageUrl(null);
      return;
    }

    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const encodedCamera = encodeURIComponent(cameraName);
    const beforeUrl = `/api/datasets/${currentDataset.id}/episodes/${currentEpisode.meta.index}/frames/${adjacentFrames.beforeFrame}?camera=${encodedCamera}`;
    const afterUrl = `/api/datasets/${currentDataset.id}/episodes/${currentEpisode.meta.index}/frames/${adjacentFrames.afterFrame}?camera=${encodedCamera}`;

    const img1 = new Image();
    const img2 = new Image();
    let loadedCount = 0;

    const blend = () => {
      loadedCount++;
      if (loadedCount < 2) return;

      canvas.width = img1.width;
      canvas.height = img1.height;

      ctx.globalAlpha = 1 - adjacentFrames.factor;
      ctx.drawImage(img1, 0, 0);

      ctx.globalAlpha = adjacentFrames.factor;
      ctx.drawImage(img2, 0, 0);

      ctx.globalAlpha = 1;
      setInterpolatedImageUrl(canvas.toDataURL('image/jpeg', 0.9));
    };

    img1.onload = blend;
    img2.onload = blend;
    img1.src = beforeUrl;
    img2.src = afterUrl;

    return () => {
      img1.onload = null;
      img2.onload = null;
    };
  }, [isInsertedFrame, adjacentFrames, currentDataset, currentEpisode, cameraName]);

  // --- Video element synchronisation ---

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
    );

    recordDiagnosticEvent('playback', 'sync-action', {
      action: action.kind,
      currentFrame: currentFrameRef.current,
      playbackRangeStart,
      playbackRangeEnd,
      isPlaying,
      autoLoop,
      shouldLoopPlaybackRange,
      videoCurrentTime: Number(video.currentTime.toFixed(3)),
    });

    switch (action.kind) {
      case 'restart':
        setFrameWithinActivePlaybackRange(playbackRangeStart);
        ensureVideoPlaybackAtTime(video, playbackRangeStart / fps);
        break;
      case 'seek-and-play':
        ensureVideoPlaybackAtTime(video, action.seekTo);
        break;
      case 'play':
        ensureVideoPlaybackAtTime(video, video.currentTime);
        break;
      case 'pause':
        video.pause();
        break;
    }
  }, [autoLoop, ensureVideoPlaybackAtTime, fps, isPlaying, playbackRangeEnd, playbackRangeStart, playbackSpeed, setFrameWithinActivePlaybackRange, shouldLoopPlaybackRange, totalFrames]);

  // Track video duration for accurate frame↔time mapping
  const handleLoadedMetadata = useCallback((e: SyntheticEvent<HTMLVideoElement>) => {
    const video = e.currentTarget;

    setVideoDuration(video.duration);
    recordDiagnosticEvent('playback', 'loaded-metadata', {
      duration: Number(video.duration.toFixed(3)),
      isPlaying,
      shouldAutoPlayOnMetadataLoad: shouldAutoPlayOnMetadataLoadRef.current,
    });
    if (isPlaying) {
      skipNextPlaybackSyncRef.current = true;
      syncVideoElementPlayback(video);
      return;
    }

    if (shouldAutoPlayOnMetadataLoadRef.current) {
      shouldAutoPlayOnMetadataLoadRef.current = false;
      togglePlayback();
    }
  }, [isPlaying, syncVideoElementPlayback, togglePlayback]);

  // Sync play/pause and playback speed to native video element.
  // Reads currentFrame/originalFrameIndex from refs to avoid re-triggering
  // on every rAF frame update, which would fight the native playbackRate.
  useEffect(() => {
    const video = videoRef.current;
    if (!video || !videoSrc) return;

    if (skipNextPlaybackSyncRef.current) {
      skipNextPlaybackSyncRef.current = false;
      return;
    }

    syncVideoElementPlayback(video);
  }, [syncVideoElementPlayback, videoSrc]);

  // During playback, drive frame counter from video.currentTime via rAF
  useEffect(() => {
    if (!isPlaying) return;
    let rafId: number;
    let lastFrame = -1;
    const tick = () => {
      const video = videoRef.current;
      if (video) {
        const nextFrame = Math.floor(video.currentTime * fps);
        const resolved = resolvePlaybackTick(nextFrame, totalFrames, activePlaybackRange, shouldLoopPlaybackRange);
        const now = Date.now();

        if (shouldRecoverPlaybackAfterDesync(
          isPlaying,
          video.paused,
          now - lastPlaybackRecoveryAtRef.current,
          PLAYBACK_RECOVERY_COOLDOWN_MS,
        )) {
          lastPlaybackRecoveryAtRef.current = now;
          recordDiagnosticEvent('playback', 'desync-recover', {
            currentFrame: resolved.frame,
            nextFrame,
            videoCurrentTime: Number(video.currentTime.toFixed(3)),
            playbackRangeStart,
            playbackRangeEnd,
            autoLoop,
            shouldLoopPlaybackRange,
          });
          ensureVideoPlaybackAtTime(video, resolved.frame / fps);
        }

        if (resolved.frame !== lastFrame) {
          lastFrame = resolved.frame;
          setCurrentFrame(resolved.frame);
        }

        if (resolved.shouldStop) {
          if (isPlaying) {
            togglePlayback();
          }
          video.currentTime = resolved.frame / fps;
          video.pause();
          return;
        }

        if (resolved.frame !== nextFrame) {
          const didLoop = shouldRestartPlaybackAfterLoop(
            nextFrame,
            resolved.frame,
            activePlaybackRange,
            shouldLoopPlaybackRange,
          );

          if (didLoop) {
            recordDiagnosticEvent('playback', 'range-loop', {
              rangeStart: playbackRangeStart,
              rangeEnd: playbackRangeEnd,
              reportedFrame: nextFrame,
              resolvedFrame: resolved.frame,
              autoLoop,
              shouldLoopPlaybackRange,
            });
          }

          if (didLoop) {
            ensureVideoPlaybackAtTime(video, resolved.frame / fps);
          } else {
            video.currentTime = resolved.frame / fps;
          }
        }
      }
      rafId = requestAnimationFrame(tick);
    };
    rafId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafId);
  }, [activePlaybackRange, autoLoop, ensureVideoPlaybackAtTime, fps, isPlaying, playbackRangeEnd, playbackRangeStart, setCurrentFrame, shouldLoopPlaybackRange, togglePlayback, totalFrames]);

  // When paused, seek video to match store frame (slider scrub / step buttons)
  useEffect(() => {
    const video = videoRef.current;
    if (!video || isPlaying) return;
    const targetTime = (originalFrameIndex ?? currentFrame) / fps;
    if (Math.abs(video.currentTime - targetTime) > 0.5 / fps) {
      video.currentTime = targetTime;
    }
  }, [currentFrame, originalFrameIndex, fps, isPlaying]);

  // When the video ends, loop or stop based on autoLoop setting
  const handleVideoEnded = useCallback(() => {
    recordDiagnosticEvent('playback', 'video-ended', {
      playbackRangeStart,
      playbackRangeEnd,
      autoLoop,
      shouldLoopPlaybackRange,
    });
    if (shouldLoopPlaybackRange) {
      // Restart directly — the sync effect won't re-trigger since isPlaying
      // hasn't changed, so we must seek and play the video element ourselves.
      const video = videoRef.current;
      setFrameWithinActivePlaybackRange(playbackRangeStart);
      if (video) {
        ensureVideoPlaybackAtTime(video, playbackRangeStart / fps);
      }
    } else {
      if (isPlaying) togglePlayback();
      setFrameWithinActivePlaybackRange(playbackRangeEnd);
    }
  }, [autoLoop, ensureVideoPlaybackAtTime, fps, isPlaying, playbackRangeEnd, playbackRangeStart, setFrameWithinActivePlaybackRange, shouldLoopPlaybackRange, togglePlayback]);

  const handleOpenExportDialog = useCallback(() => {
    setExportDialogOpen(true);
    recordDiagnosticEvent('export', 'dialog-open', {
      activeTab,
      episodeIndex: currentEpisode?.meta.index ?? null,
    });
  }, [activeTab, currentEpisode?.meta.index]);

  const handleResetAllClick = useCallback(() => {
    recordDiagnosticEvent('workspace', 'reset-all', {
      activeTab,
      episodeIndex: currentEpisode?.meta.index ?? null,
      hasPendingEpisodeChanges,
    });
    void handleResetAll();
  }, [activeTab, currentEpisode?.meta.index, handleResetAll, hasPendingEpisodeChanges]);

  if (!currentDataset || !currentEpisode) {
    return <AnnotationWorkspaceEmptyState />;
  }

  const episodePlaybackCard = (
    <AnnotationWorkspacePlaybackCard
      canvasRef={canvasRef}
      videoRef={videoRef}
      videoSrc={videoSrc}
      onVideoEnded={handleVideoEnded}
      onLoadedMetadata={handleLoadedMetadata}
      displayFilter={displayFilter}
      isInsertedFrame={isInsertedFrame}
      interpolatedImageUrl={interpolatedImageUrl}
      currentFrame={currentFrame}
      totalFrames={totalFrames}
      resizeOutput={globalTransform?.resize ?? null}
      frameImageUrl={frameImageUrl}
      isPlaying={isPlaying}
      onTogglePlayback={togglePlayback}
      onStepFrame={stepFrame}
      playbackSpeed={playbackSpeed}
      onSetPlaybackSpeed={setPlaybackSpeed}
      autoPlay={autoPlay}
      onSetAutoPlay={setAutoPlay}
      autoLoop={autoLoop}
      onSetAutoLoop={setAutoLoop}
      playbackRangeStart={playbackRangeStart}
      playbackRangeEnd={playbackRangeEnd}
      onSetFrameWithinPlaybackRange={setFrameWithinActivePlaybackRange}
      playbackRangeHighlight={playbackRangeHighlight}
      playbackRangeLabel={playbackRangeLabel}
    />
  );

  const trajectoryPlaybackCard = (
    <AnnotationWorkspacePlaybackCard
      compact
      canvasRef={canvasRef}
      videoRef={videoRef}
      videoSrc={videoSrc}
      onVideoEnded={handleVideoEnded}
      onLoadedMetadata={handleLoadedMetadata}
      displayFilter={displayFilter}
      isInsertedFrame={isInsertedFrame}
      interpolatedImageUrl={interpolatedImageUrl}
      currentFrame={currentFrame}
      totalFrames={totalFrames}
      resizeOutput={globalTransform?.resize ?? null}
      frameImageUrl={frameImageUrl}
      isPlaying={isPlaying}
      onTogglePlayback={togglePlayback}
      onStepFrame={stepFrame}
      playbackSpeed={playbackSpeed}
      onSetPlaybackSpeed={setPlaybackSpeed}
      autoPlay={autoPlay}
      onSetAutoPlay={setAutoPlay}
      autoLoop={autoLoop}
      onSetAutoLoop={setAutoLoop}
      playbackRangeStart={playbackRangeStart}
      playbackRangeEnd={playbackRangeEnd}
      onSetFrameWithinPlaybackRange={setFrameWithinActivePlaybackRange}
      playbackRangeHighlight={playbackRangeHighlight}
      playbackRangeLabel={playbackRangeLabel}
    />
  );

  const episodeSubtaskListCard = (
    <AnnotationWorkspaceSubtaskListCard
      selectedSubtaskId={selectedSubtaskId}
      onSelectionChange={handleSubtaskSelectionChange}
      draftRange={selectedRange}
      maxFrame={Math.max(totalFrames - 1, 0)}
      onDraftRangeChange={handleDraftRangeChange}
      onCreateSubtaskFromRange={handleCreateSubtaskFromSelection}
    />
  );

  const trajectorySubtaskListCard = (
    <AnnotationWorkspaceSubtaskListCard
      compact
      selectedSubtaskId={selectedSubtaskId}
      onSelectionChange={handleSubtaskSelectionChange}
      draftRange={selectedRange}
      maxFrame={Math.max(totalFrames - 1, 0)}
      onDraftRangeChange={handleDraftRangeChange}
      onCreateSubtaskFromRange={handleCreateSubtaskFromSelection}
    />
  );

  return (
    <div className="flex h-full flex-col gap-2.5 px-3 py-2">
      {/* Main tabbed content area */}
      <Tabs value={activeTab} onValueChange={handleTabChange} className="flex-1 flex flex-col min-h-0">
        <AnnotationWorkspaceTopBar
          episodeIndex={currentEpisode.meta.index}
          canGoPreviousEpisode={canGoPreviousEpisode}
          onPreviousEpisode={onPreviousEpisode}
          hasPendingEpisodeChanges={hasPendingEpisodeChanges}
          onResetAllClick={handleResetAllClick}
          onOpenExportDialog={handleOpenExportDialog}
          canGoNextEpisode={canGoNextEpisode}
          canSaveAndNextEpisode={Boolean(onSaveAndNextEpisode) && !saveEpisodeLabels.isPending}
          onSaveAndNextEpisode={() => void handleSaveAndNextEpisode()}
          saveStatusMessage={saveStatusMessage}
        />

        <TabsContent value="episode" className="mt-2.5 flex-1 min-h-0">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 h-full">
            {/* Left panel: Video and timeline */}
            <div className="lg:col-span-2 min-h-0 overflow-y-auto">
              {episodePlaybackCard}
              {episodeSubtaskListCard}
            </div>

            {/* Right panel: Annotation/edit tools */}
            <AnnotationWorkspaceEditToolsPanel
              episodeIndex={currentEpisode.meta.index}
              onClearTransforms={clearTransforms}
              canResetTransforms={Boolean(globalTransform)}
            />
          </div>
        </TabsContent>

        <AnnotationWorkspaceTrajectoryTab
          playbackCard={trajectoryPlaybackCard}
          subtaskListCard={trajectorySubtaskListCard}
          selectedRange={selectedRange}
          selectedSubtaskId={selectedSubtaskId}
          onClearPlaybackSelection={clearPlaybackSelection}
          onDraftRangeChange={handleDraftRangeChange}
          onCreateSubtaskFromRange={handleCreateSubtaskFromSelection}
          onGraphSeek={handleGraphSeek}
          onSelectionStart={handleSelectionStart}
          onSelectionComplete={handleSelectionComplete}
          totalFrames={totalFrames}
          onSubtaskSelectionChange={handleSubtaskSelectionChange}
        />

        {/* Tab 2: Object Detection */}
        <TabsContent value="detection" className="mt-2.5 flex-1 min-h-0">
          <DetectionPanel />
        </TabsContent>
      </Tabs>

      {diagnosticsEnabled && (
        <AnnotationWorkspaceDiagnosticsPanel
          diagnosticsStateSummary={diagnosticsStateSummary}
          availableDiagnosticsChannels={availableDiagnosticsChannels}
          selectedDiagnosticsChannel={selectedDiagnosticsChannel}
          onSelectedDiagnosticsChannelChange={setSelectedDiagnosticsChannel}
          onClearVisibleDiagnostics={handleClearVisibleDiagnostics}
          onCopyDiagnostics={() => void handleCopyDiagnostics()}
          onDownloadDiagnostics={handleDownloadDiagnostics}
          diagnosticsClipboardStatus={diagnosticsClipboardStatus}
          recentDiagnosticEvents={recentDiagnosticEvents}
          playbackRangeStart={playbackRangeStart}
          playbackRangeEnd={playbackRangeEnd}
          shouldLoopPlaybackRange={shouldLoopPlaybackRange}
        />
      )}

      {/* Export Dialog */}
      <ExportDialog
        open={exportDialogOpen}
        onOpenChange={setExportDialogOpen}
        datasetId={currentDataset.id}
        episodeIndices={[currentEpisode.meta.index]}
      />
    </div>
  );
}
