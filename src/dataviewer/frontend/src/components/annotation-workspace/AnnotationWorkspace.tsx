import { Activity, Download, Pause, Play, Repeat, RotateCcw, Scan, SkipBack, SkipForward, Video } from 'lucide-react';
import { type SyntheticEvent,useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { LabelPanel } from '@/components/annotation-panel';
import { TrajectoryPlot } from '@/components/episode-viewer';
import { ExportDialog } from '@/components/export';
import { ColorAdjustmentControls,FrameInsertionToolbar, FrameRemovalToolbar, TrajectoryEditor, TransformControls } from '@/components/frame-editor';
import { DetectionPanel } from '@/components/object-detection';
import { PlaybackControlStrip } from '@/components/playback/PlaybackControlStrip';
import { SubtaskTimelineTrack, SubtaskToolbar } from '@/components/subtask-timeline';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ViewerDisplayControls } from '@/components/viewer-display';
import { useSaveEpisodeLabels } from '@/hooks/use-labels';
import { combineCssFilters } from '@/lib/css-filters';
import { computeEffectiveFps, computeSyncAction } from '@/lib/playback-utils';
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

const EMPTY_LABELS: string[] = [];

interface AnnotationWorkspaceProps {
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
  canGoPreviousEpisode = false,
  onPreviousEpisode,
  canGoNextEpisode = false,
  onNextEpisode,
  onSaveAndNextEpisode,
}: AnnotationWorkspaceProps) {
  const [exportDialogOpen, setExportDialogOpen] = useState(false);
  const [showSavedStatus, setShowSavedStatus] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const currentFrameRef = useRef(0);
  const originalFrameIndexRef = useRef<number | null>(null);
  const saveStatusTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [interpolatedImageUrl, setInterpolatedImageUrl] = useState<string | null>(null);
  const [videoDuration, setVideoDuration] = useState(0);

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

  const announceSave = useCallback(() => {
    setShowSavedStatus(true);

    if (saveStatusTimeoutRef.current) {
      clearTimeout(saveStatusTimeoutRef.current);
    }

    saveStatusTimeoutRef.current = setTimeout(() => {
      setShowSavedStatus(false);
      saveStatusTimeoutRef.current = null;
    }, 2400);
  }, []);

  useEffect(() => {
    return () => {
      if (saveStatusTimeoutRef.current) {
        clearTimeout(saveStatusTimeoutRef.current);
      }
    };
  }, []);

  const hasLabelChanges = useMemo(() => {
    if (!currentEpisode || !labelDataLoaded) {
      return false;
    }

    const current = [...currentEpisodeLabels].sort();
    const initial = [...savedLabelsForCurrentEpisode].sort();

    if (current.length !== initial.length) {
      return true;
    }

    return current.some((label, index) => label !== initial[index]);
  }, [currentEpisode, currentEpisodeLabels, labelDataLoaded, savedLabelsForCurrentEpisode]);

  const hasPendingEpisodeChanges = hasLabelChanges || hasEdits;
  const saveStatusMessage = hasPendingEpisodeChanges
    ? 'Unsaved episode changes.'
    : showSavedStatus
      ? 'Episode changes saved.'
      : null;

  const handleResetAll = useCallback(async () => {
    resetEdits();

    if (!currentEpisode || !hasLabelChanges) {
      return;
    }

    const nextLabels = savedLabelsForCurrentEpisode.filter((label) =>
      availableLabels.includes(label),
    );

    setEpisodeLabelsInStore(currentEpisode.meta.index, nextLabels);
  }, [availableLabels, currentEpisode, hasLabelChanges, resetEdits, savedLabelsForCurrentEpisode, setEpisodeLabelsInStore]);

  const handleSaveAndNextEpisode = useCallback(async () => {
    const advanceToNextEpisode = onSaveAndNextEpisode ?? onNextEpisode;

    if (!canGoNextEpisode || !advanceToNextEpisode) {
      return;
    }

    if (currentEpisode && currentDataset && hasLabelChanges) {
      await saveEpisodeLabels.mutateAsync({
        episodeIdx: currentEpisode.meta.index,
        labels: currentEpisodeLabels,
      });
    }

    if (hasEdits) {
      saveEpisodeDraft();
    }

    if (hasPendingEpisodeChanges) {
      announceSave();
    }

    advanceToNextEpisode();
  }, [announceSave, canGoNextEpisode, currentDataset, currentEpisode, currentEpisodeLabels, hasEdits, hasLabelChanges, hasPendingEpisodeChanges, onNextEpisode, onSaveAndNextEpisode, saveEpisodeDraft, saveEpisodeLabels]);

  // Combined CSS filter: viewer display adjustments + edit color transforms
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

  // Track video duration for accurate frame↔time mapping
  const handleLoadedMetadata = useCallback((e: SyntheticEvent<HTMLVideoElement>) => {
    setVideoDuration(e.currentTarget.duration);
    // Auto-play when video loads and autoPlay is enabled
    if (autoPlay && !isPlaying) {
      togglePlayback();
    }
  }, [autoPlay, isPlaying, togglePlayback]);

  // Sync play/pause and playback speed to native video element.
  // Reads currentFrame/originalFrameIndex from refs to avoid re-triggering
  // on every rAF frame update, which would fight the native playbackRate.
  useEffect(() => {
    const video = videoRef.current;
    if (!video || !videoSrc) return;

    const action = computeSyncAction(
      isPlaying, playbackSpeed,
      currentFrameRef.current, totalFrames, originalFrameIndexRef.current,
      fps, video.currentTime,
    );

    switch (action.kind) {
      case 'restart':
        video.playbackRate = action.playbackRate;
        setCurrentFrame(0);
        video.currentTime = 0;
        video.play().catch(() => { /* autoplay may be blocked */ });
        break;
      case 'seek-and-play':
        video.playbackRate = action.playbackRate;
        video.currentTime = action.seekTo;
        video.play().catch(() => { /* autoplay may be blocked */ });
        break;
      case 'play':
        video.playbackRate = action.playbackRate;
        video.play().catch(() => { /* autoplay may be blocked */ });
        break;
      case 'pause':
        video.pause();
        break;
    }
  }, [isPlaying, playbackSpeed, videoSrc, fps, totalFrames, setCurrentFrame]);

  // During playback, drive frame counter from video.currentTime via rAF
  useEffect(() => {
    if (!isPlaying) return;
    let rafId: number;
    let lastFrame = -1;
    const tick = () => {
      const video = videoRef.current;
      if (video) {
        const frame = Math.round(video.currentTime * fps);
        if (frame !== lastFrame) {
          lastFrame = frame;
          setCurrentFrame(frame);
        }
      }
      rafId = requestAnimationFrame(tick);
    };
    rafId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafId);
  }, [isPlaying, fps, setCurrentFrame]);

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
    if (autoLoop) {
      // Restart directly — the sync effect won't re-trigger since isPlaying
      // hasn't changed, so we must seek and play the video element ourselves.
      const video = videoRef.current;
      setCurrentFrame(0);
      if (video) {
        video.currentTime = 0;
        video.play().catch(() => { /* autoplay may be blocked */ });
      }
    } else {
      if (isPlaying) togglePlayback();
      setCurrentFrame(totalFrames - 1);
    }
  }, [autoLoop, isPlaying, togglePlayback, setCurrentFrame, totalFrames]);

  // Step forward / backward one frame (when paused)
  const stepFrame = useCallback(
    (delta: number) => {
      const next = Math.max(0, Math.min(totalFrames - 1, currentFrame + delta));
      setCurrentFrame(next);
    },
    [currentFrame, totalFrames, setCurrentFrame],
  );

  const renderPlaybackCard = useCallback((compact = false) => (
    <Card className={compact ? 'h-full min-h-0' : 'flex-shrink-0'}>
      <CardContent className={compact ? 'flex h-full min-h-0 flex-col p-3' : 'p-4'}>
        <ViewerDisplayControls />
        <div
          className={compact
            ? 'mt-2 aspect-[4/3] min-h-0 rounded-lg bg-black relative flex items-center justify-center overflow-hidden'
            : 'mt-2 aspect-video rounded-lg bg-black relative flex items-center justify-center overflow-hidden'}
        >
          <canvas ref={canvasRef} className="hidden" />

          {videoSrc ? (
            <video
              ref={videoRef}
              src={videoSrc}
              onEnded={handleVideoEnded}
              onLoadedMetadata={handleLoadedMetadata}
              muted
              playsInline
              preload="auto"
              className="max-w-full max-h-full object-contain"
              style={displayFilter ? { filter: displayFilter } : undefined}
            />
          ) : isInsertedFrame && interpolatedImageUrl ? (
            <img
              src={interpolatedImageUrl}
              alt={`Interpolated frame ${currentFrame}`}
              className="max-w-full max-h-full object-contain"
              style={displayFilter ? { filter: displayFilter } : undefined}
            />
          ) : frameImageUrl ? (
            <img
              src={frameImageUrl}
              alt={`Frame ${currentFrame}`}
              className="max-w-full max-h-full object-contain"
              style={displayFilter ? { filter: displayFilter } : undefined}
            />
          ) : (
            <span className="text-white">Frame {currentFrame + 1} of {totalFrames}</span>
          )}

          {isInsertedFrame && (
            <div className="absolute top-2 left-2 rounded bg-blue-500/80 px-2 py-1 text-xs text-white">
              Interpolated Frame
            </div>
          )}

          {globalTransform?.resize && (
            <div className="absolute top-2 right-2 rounded bg-green-600/80 px-2 py-1 text-xs text-white">
              Output: {globalTransform.resize.width} × {globalTransform.resize.height}
            </div>
          )}
        </div>

        <PlaybackControlStrip
          currentFrame={currentFrame}
          totalFrames={totalFrames}
          className={compact ? 'mt-2' : 'mt-3'}
          controls={
            compact ? (
              <div data-testid="trajectory-compact-controls" className="flex w-full items-center justify-between gap-2">
                <div className="flex shrink-0 items-center gap-1">
                  <Button
                    size="icon"
                    onClick={togglePlayback}
                    aria-label={isPlaying ? 'Pause playback' : 'Play playback'}
                    title={isPlaying ? 'Pause playback' : 'Play playback'}
                    className="h-8 w-8"
                  >
                    {isPlaying ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
                  </Button>
                  <Button
                    size="icon"
                    variant="outline"
                    onClick={() => stepFrame(-1)}
                    disabled={isPlaying}
                    aria-label="Previous frame"
                    title="Previous frame"
                    className="h-8 w-8"
                  >
                    <SkipBack className="h-4 w-4" />
                  </Button>
                  <Button
                    size="icon"
                    variant="outline"
                    onClick={() => stepFrame(1)}
                    disabled={isPlaying}
                    aria-label="Next frame"
                    title="Next frame"
                    className="h-8 w-8"
                  >
                    <SkipForward className="h-4 w-4" />
                  </Button>
                  <Button
                    size="icon"
                    variant="outline"
                    onClick={() => setCurrentFrame(0)}
                    aria-label="Reset playback"
                    title="Reset playback"
                    className="h-8 w-8"
                  >
                    <RotateCcw className="h-4 w-4" />
                  </Button>
                </div>
                <div className="flex shrink-0 items-center gap-1">
                  {[0.5, 1, 2].map((speed) => (
                    <Button
                      key={speed}
                      size="sm"
                      variant={playbackSpeed === speed ? 'default' : 'outline'}
                      onClick={() => setPlaybackSpeed(speed)}
                      aria-label={`Set playback speed to ${speed}x`}
                      className="h-8 min-w-[2.5rem] px-1.5 text-xs"
                    >
                      {speed}x
                    </Button>
                  ))}
                  <Button
                    size="icon"
                    variant={autoPlay ? 'default' : 'outline'}
                    onClick={() => setAutoPlay(!autoPlay)}
                    aria-label="Toggle auto-play"
                    title={autoPlay ? 'Auto-play on (click to disable)' : 'Auto-play off (click to enable)'}
                    className="h-8 w-8"
                  >
                    <Play className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="icon"
                    variant={autoLoop ? 'default' : 'outline'}
                    onClick={() => setAutoLoop(!autoLoop)}
                    aria-label="Toggle loop playback"
                    title={autoLoop ? 'Loop on (click to disable)' : 'Loop off (click to enable)'}
                    className="h-8 w-8"
                  >
                    <Repeat className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>
            ) : (
              <>
                <Button
                  size="sm"
                  onClick={togglePlayback}
                  className="gap-1 min-w-[5rem]"
                >
                  {isPlaying ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
                  {isPlaying ? 'Pause' : 'Play'}
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => stepFrame(-1)}
                  disabled={isPlaying}
                  title="Previous frame"
                >
                  <SkipBack className="h-4 w-4" />
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => stepFrame(1)}
                  disabled={isPlaying}
                  title="Next frame"
                >
                  <SkipForward className="h-4 w-4" />
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => setCurrentFrame(0)}
                >
                  <RotateCcw className="h-4 w-4" />
                </Button>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm">Speed:</span>
                  {[0.5, 1, 2].map((speed) => (
                    <Button
                      key={speed}
                      size="sm"
                      variant={playbackSpeed === speed ? 'default' : 'outline'}
                      onClick={() => setPlaybackSpeed(speed)}
                      className="px-2"
                    >
                      {speed}x
                    </Button>
                  ))}
                </div>
                <div className="flex flex-wrap items-center gap-1">
                  <Button
                    size="sm"
                    variant={autoPlay ? 'default' : 'outline'}
                    onClick={() => setAutoPlay(!autoPlay)}
                    className="px-2"
                    title={autoPlay ? 'Auto-play on (click to disable)' : 'Auto-play off (click to enable)'}
                  >
                    <Play className="mr-1 h-3 w-3" />
                    Auto
                  </Button>
                  <Button
                    size="sm"
                    variant={autoLoop ? 'default' : 'outline'}
                    onClick={() => setAutoLoop(!autoLoop)}
                    className="px-2"
                    title={autoLoop ? 'Loop on (click to disable)' : 'Loop off (click to enable)'}
                  >
                    <Repeat className="mr-1 h-3 w-3" />
                    Loop
                  </Button>
                </div>
              </>
            )
          }
          slider={
            <input
              type="range"
              min={0}
              max={totalFrames - 1}
              value={currentFrame}
              onChange={(e) => setCurrentFrame(parseInt(e.target.value, 10))}
              className="w-full"
            />
          }
        />
      </CardContent>
    </Card>
  ), [
    autoLoop,
    autoPlay,
    currentFrame,
    displayFilter,
    frameImageUrl,
    globalTransform?.resize,
    handleLoadedMetadata,
    handleVideoEnded,
    interpolatedImageUrl,
    isInsertedFrame,
    isPlaying,
    playbackSpeed,
    setAutoLoop,
    setAutoPlay,
    setCurrentFrame,
    setPlaybackSpeed,
    stepFrame,
    togglePlayback,
    totalFrames,
    videoSrc,
  ]);

  if (!currentDataset || !currentEpisode) {
    return (
      <div className="flex items-center justify-center h-full">
        <Card className="max-w-md">
          <CardHeader>
            <CardTitle>No Episode Selected</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-muted-foreground">
              Select a dataset and episode from the sidebar to begin annotation.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col gap-2.5 px-3 py-2">
      {/* Main tabbed content area */}
      <Tabs defaultValue="episode" className="flex-1 flex flex-col min-h-0">
        <div className="flex items-center justify-between gap-3" data-testid="workspace-top-bar">
          <div className="flex min-w-0 items-center gap-3">
            <div className="flex min-w-0 items-center gap-2">
              <h2 className="text-lg font-semibold leading-none">
                Episode {currentEpisode.meta.index}
              </h2>
            </div>
            <TabsList className="h-10 w-fit shrink-0">
              <TabsTrigger value="episode" className="gap-2">
                <Video className="h-4 w-4" />
                Episode Viewer
              </TabsTrigger>
              <TabsTrigger value="trajectory" className="gap-2">
                <Activity className="h-4 w-4" />
                Trajectory Viewer
              </TabsTrigger>
              <TabsTrigger value="detection" className="gap-2">
                <Scan className="h-4 w-4" />
                Object Detection
              </TabsTrigger>
            </TabsList>
          </div>
          <div className="flex shrink-0 flex-col items-end justify-center gap-1" data-testid="workspace-header-actions">
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="icon"
                onClick={onPreviousEpisode}
                disabled={!canGoPreviousEpisode || !onPreviousEpisode}
                aria-label="Previous Episode"
                title="Previous Episode"
              >
                <SkipBack className="h-4 w-4" />
              </Button>
              <Button
                variant="outline"
                onClick={() => void handleResetAll()}
                disabled={!hasPendingEpisodeChanges}
              >
                <RotateCcw className="h-4 w-4 mr-2" />
                Reset All
              </Button>
              <Button
                variant="outline"
                onClick={() => setExportDialogOpen(true)}
              >
                <Download className="h-4 w-4 mr-2" />
                Export
              </Button>
              <Button
                onClick={() => void handleSaveAndNextEpisode()}
                disabled={!canGoNextEpisode || !onSaveAndNextEpisode || saveEpisodeLabels.isPending}
              >
                <SkipForward className="h-4 w-4 mr-2" />
                Save & Next Episode
              </Button>
            </div>
            <div className="min-h-[1rem]" data-testid="workspace-save-status-slot">
              {saveStatusMessage && (
                <p data-testid="workspace-save-status" className="text-xs text-muted-foreground">
                  {saveStatusMessage}
                </p>
              )}
            </div>
          </div>
        </div>

        <TabsContent value="episode" className="mt-2.5 flex-1 min-h-0">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 h-full">
            {/* Left panel: Video and timeline */}
            <div className="lg:col-span-2 flex flex-col gap-4 overflow-y-auto">
              {renderPlaybackCard()}

              {/* Subtasks */}
              <Card className="min-h-[220px] flex-1">
                <CardContent className="p-4 h-full flex flex-col gap-2">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-xs text-muted-foreground">Subtasks</span>
                    <SubtaskToolbar />
                  </div>
                  <SubtaskTimelineTrack totalFrames={totalFrames} editable />
                </CardContent>
              </Card>
            </div>

            {/* Right panel: Annotation/edit tools */}
            <div className="flex flex-col min-h-0 overflow-y-auto">
              <Card>
                <CardHeader className="py-3 px-4">
                  <CardTitle className="text-sm">Edit Tools</CardTitle>
                </CardHeader>
                <CardContent className="p-4 pt-0 space-y-6">
                  {/* Episode Labels */}
                  <LabelPanel episodeIndex={currentEpisode.meta.index} />

                  <Separator />

                  {/* Frame Removal Section */}
                  <FrameRemovalToolbar />

                  <Separator />

                  {/* Frame Insertion Section */}
                  <FrameInsertionToolbar />

                  <Separator />

                  {/* Image Transform Section */}
                  <div>
                    <h3 className="text-sm font-medium mb-3">Image Transform</h3>
                    <TransformControls />
                  </div>

                  <Separator />

                  {/* Color Adjustment Section */}
                  <ColorAdjustmentControls />

                  <Separator />

                  {/* Trajectory Editor Section */}
                  <div>
                    <h3 className="text-sm font-medium mb-3">Trajectory Adjustment</h3>
                    <TrajectoryEditor />
                  </div>

                  <Separator />

                  {/* Reset All Transforms */}
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={clearTransforms}
                    disabled={!globalTransform}
                    className="w-full"
                  >
                    <RotateCcw className="h-4 w-4 mr-2" />
                    Reset All Image Transforms
                  </Button>
                </CardContent>
              </Card>
            </div>
          </div>
        </TabsContent>

        <TabsContent value="trajectory" className="mt-2.5 flex-1 min-h-0">
          <div className="grid h-full grid-cols-1 gap-4 xl:grid-cols-[minmax(320px,420px)_minmax(0,1fr)]">
            <div className="min-h-[320px] xl:min-h-0">
              {renderPlaybackCard(true)}
            </div>
            <Card className="min-h-[340px] xl:min-h-0">
              <CardContent className="flex h-full min-h-0 flex-col gap-3 p-4">
                <div>
                  <h3 className="text-sm font-medium">Trajectory Graph</h3>
                  <p className="text-xs text-muted-foreground">
                    Review joint motion, filters, and frame alignment alongside a compact episode player.
                  </p>
                </div>
                <TrajectoryPlot className="flex-1 min-h-[280px]" />
              </CardContent>
            </Card>
          </div>
        </TabsContent>

        {/* Tab 2: Object Detection */}
        <TabsContent value="detection" className="mt-2.5 flex-1 min-h-0">
          <DetectionPanel />
        </TabsContent>
      </Tabs>

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
