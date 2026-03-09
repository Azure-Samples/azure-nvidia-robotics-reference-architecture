import { Activity, Download, Pause, Play, Repeat, RotateCcw, Scan, SkipBack, SkipForward, Video } from 'lucide-react';
import { type SyntheticEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { LabelPanel } from '@/components/annotation-panel';
import { TrajectoryPlot } from '@/components/episode-viewer';
import { ExportDialog } from '@/components/export';
import { ColorAdjustmentControls, FrameInsertionToolbar, FrameRemovalToolbar, TrajectoryEditor, TransformControls } from '@/components/frame-editor';
import { DetectionPanel } from '@/components/object-detection';
import { PlaybackControlStrip } from '@/components/playback/PlaybackControlStrip';
import { SubtaskList, SubtaskTimelineTrack, SubtaskToolbar } from '@/components/subtask-timeline';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ViewerDisplayControls } from '@/components/viewer-display';
import { useSaveEpisodeLabels } from '@/hooks/use-labels';
import { combineCssFilters } from '@/lib/css-filters';
import {
  clearDiagnosticEvents,
  DIAGNOSTIC_CHANNEL_OPTIONS,
  DIAGNOSTICS_EVENT_NAME,
  getEnabledDiagnosticsChannels,
  isDiagnosticsEnabled,
  readDiagnosticEvents,
  recordDiagnosticEvent,
  stringifyDiagnosticEvents,
} from '@/lib/playback-diagnostics';
import {
  clampFrameToPlaybackRange,
  computeEffectiveFps,
  computeSyncAction,
  resolvePlaybackRange,
  resolvePlaybackTick,
  shouldLoopActivePlaybackRange,
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
  const [showSavedStatus, setShowSavedStatus] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const currentFrameRef = useRef(0);
  const originalFrameIndexRef = useRef<number | null>(null);
  const saveStatusTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const shouldResumeAfterSelectionRef = useRef(false);
  const shouldAutoPlayOnMetadataLoadRef = useRef(false);
  const skipNextPlaybackSyncRef = useRef(false);
  const playbackRetryTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastPlaybackRecoveryAtRef = useRef(0);
  const [interpolatedImageUrl, setInterpolatedImageUrl] = useState<string | null>(null);
  const [videoDuration, setVideoDuration] = useState(0);
  const [selectedSubtaskId, setSelectedSubtaskId] = useState<string | null>(null);
  const [selectedRange, setSelectedRange] = useState<[number, number] | null>(null);
  const [activeTab, setActiveTab] = useState('episode');
  const [diagnosticEvents, setDiagnosticEvents] = useState(() =>
    diagnosticsVisible && isDiagnosticsEnabled() ? readDiagnosticEvents() : [],
  );
  const [selectedDiagnosticsChannel, setSelectedDiagnosticsChannel] = useState('all');
  const [diagnosticsClipboardStatus, setDiagnosticsClipboardStatus] = useState<string | null>(null);
  const lastLabelSignatureRef = useRef<string | null>(null);
  const lastEpisodeContextRef = useRef<string | null>(null);
  const wasDiagnosticsEnabledRef = useRef(diagnosticsVisible && isDiagnosticsEnabled());

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
  const labelSignature = useMemo(
    () => JSON.stringify([...currentEpisodeLabels].sort()),
    [currentEpisodeLabels],
  );

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

      if (playbackRetryTimeoutRef.current) {
        clearTimeout(playbackRetryTimeoutRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!isDiagnosticsEnabled() || typeof window === 'undefined') {
      return;
    }

    const syncDiagnostics = () => {
      setDiagnosticEvents(readDiagnosticEvents());
    };

    syncDiagnostics();
    window.addEventListener(DIAGNOSTICS_EVENT_NAME, syncDiagnostics);

    return () => {
      window.removeEventListener(DIAGNOSTICS_EVENT_NAME, syncDiagnostics);
    };
  }, [diagnosticsVisible]);

  const diagnosticsEnabled = diagnosticsVisible && isDiagnosticsEnabled();
  const diagnosticsChannels = getEnabledDiagnosticsChannels();

  useEffect(() => {
    if (diagnosticsEnabled && !wasDiagnosticsEnabledRef.current) {
      recordDiagnosticEvent('workspace', 'diagnostics-enabled', {
        activeTab,
        episodeIndex: currentEpisode?.meta.index ?? null,
      });
      setDiagnosticEvents(readDiagnosticEvents());
    }

    if (!diagnosticsEnabled && wasDiagnosticsEnabledRef.current) {
      setDiagnosticEvents([]);
    }

    wasDiagnosticsEnabledRef.current = diagnosticsEnabled;
  }, [activeTab, currentEpisode?.meta.index, diagnosticsEnabled]);

  useEffect(() => {
    if (diagnosticsEnabled) {
      return;
    }

    setSelectedDiagnosticsChannel('all');
    setDiagnosticsClipboardStatus(null);
  }, [diagnosticsEnabled]);

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

  useEffect(() => {
    if (!currentEpisode) {
      lastLabelSignatureRef.current = null;
      return;
    }

    if (
      diagnosticsEnabled
      && lastLabelSignatureRef.current !== null
      && lastLabelSignatureRef.current !== labelSignature
    ) {
      recordDiagnosticEvent('labels', 'draft-change', {
        episodeIndex: currentEpisode.meta.index,
        labelCount: currentEpisodeLabels.length,
        labels: [...currentEpisodeLabels],
        hasLabelChanges,
      });
    }

    lastLabelSignatureRef.current = labelSignature;
  }, [currentEpisode, currentEpisodeLabels, diagnosticsEnabled, hasLabelChanges, labelSignature]);

  useEffect(() => {
    const nextContext = currentDataset && currentEpisode
      ? `${currentDataset.id}:${currentEpisode.meta.index}`
      : null;

    if (!nextContext) {
      lastEpisodeContextRef.current = null;
      return;
    }

    if (
      diagnosticsEnabled
      && lastEpisodeContextRef.current !== null
      && lastEpisodeContextRef.current !== nextContext
    ) {
      const [previousDatasetId, previousEpisodeIndex] = lastEpisodeContextRef.current.split(':');

      recordDiagnosticEvent('navigation', 'episode-context-change', {
        previousDatasetId,
        previousEpisodeIndex: Number(previousEpisodeIndex),
        datasetId: currentDataset?.id ?? null,
        episodeIndex: currentEpisode?.meta.index ?? null,
      });
    }

    lastEpisodeContextRef.current = nextContext;
  }, [currentDataset, currentEpisode, diagnosticsEnabled]);

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

      recordDiagnosticEvent('labels', 'saved', {
        datasetId: currentDataset.id,
        episodeIndex: currentEpisode.meta.index,
        labelCount: currentEpisodeLabels.length,
      });
    }

    if (hasEdits) {
      saveEpisodeDraft();
      recordDiagnosticEvent('persistence', 'draft-saved', {
        datasetId: currentDataset?.id ?? null,
        episodeIndex: currentEpisode?.meta.index ?? null,
      });
    }

    if (hasPendingEpisodeChanges) {
      announceSave();
    }

    recordDiagnosticEvent('workspace', 'save-next-episode', {
      episodeIndex: currentEpisode?.meta.index ?? null,
      hasPendingEpisodeChanges,
      hasEdits,
      hasLabelChanges,
    });

    advanceToNextEpisode();
  }, [announceSave, canGoNextEpisode, currentDataset, currentEpisode, currentEpisodeLabels, hasEdits, hasLabelChanges, hasPendingEpisodeChanges, onNextEpisode, onSaveAndNextEpisode, saveEpisodeDraft, saveEpisodeLabels]);

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
  const activeSubtask = useMemo(
    () => subtasks.find((segment) => segment.id === selectedSubtaskId) ?? null,
    [selectedSubtaskId, subtasks],
  );
  const activePlaybackRange = activeSubtask?.frameRange ?? selectedRange;
  const shouldLoopPlaybackRange = useMemo(
    () => shouldLoopActivePlaybackRange(activePlaybackRange, autoLoop),
    [activePlaybackRange, autoLoop],
  );
  const playbackRange = useMemo(
    () => resolvePlaybackRange(totalFrames, activePlaybackRange),
    [activePlaybackRange, totalFrames],
  );
  const playbackRangeStart = playbackRange[0];
  const playbackRangeEnd = playbackRange[1];
  const playbackRangeLabel = selectedSubtaskId ? 'Active subtask range' : selectedRange ? 'Draft selection range' : null;
  const playbackRangeHighlight = useMemo(() => {
    if (!activePlaybackRange || totalFrames <= 1) {
      return null;
    }

    const total = Math.max(totalFrames - 1, 1);
    const left = (playbackRangeStart / total) * 100;
    const width = ((Math.max(playbackRangeEnd - playbackRangeStart, 0) + 1) / (total + 1)) * 100;

    return {
      left: `${left}%`,
      width: `${Math.max(width, 0.5)}%`,
    };
  }, [activePlaybackRange, playbackRangeEnd, playbackRangeStart, totalFrames]);

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

  const setFrameWithinPlaybackRange = useCallback((frame: number, rangeOverride?: [number, number] | null) => {
    return seekVideoFrame(frame, rangeOverride ?? activePlaybackRange, true);
  }, [activePlaybackRange, seekVideoFrame]);

  const handleGraphSeek = useCallback((frame: number) => {
    recordDiagnosticEvent('playback', 'graph-seek', { frame });
    seekVideoFrame(frame, null, false);
  }, [seekVideoFrame]);

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

  const clearPlaybackSelection = useCallback(() => {
    shouldResumeAfterSelectionRef.current = false;
    setSelectedSubtaskId(null);
    setSelectedRange(null);
    recordDiagnosticEvent('playback', 'selection-clear', { source: 'workspace-action' });
  }, []);

  const handleSubtaskSelectionChange = useCallback((id: string | null) => {
    setSelectedSubtaskId(id);
    shouldResumeAfterSelectionRef.current = false;
    recordDiagnosticEvent('subtasks', 'select', { id });

    if (!id) {
      setSelectedRange(null);
      return;
    }

    setSelectedRange(null);
    const nextSegment = subtasks.find((segment) => segment.id === id);

    if (nextSegment) {
      setFrameWithinPlaybackRange(nextSegment.frameRange[0], nextSegment.frameRange);
    }
  }, [setFrameWithinPlaybackRange, subtasks]);

  const handleCreateSubtaskFromRange = useCallback((range: [number, number]) => {
    const nextSegment = createDefaultSubtask(range, subtasks);
    addSubtask(nextSegment);
    shouldResumeAfterSelectionRef.current = false;
    setSelectedRange(null);
    setSelectedSubtaskId(nextSegment.id);
    setFrameWithinPlaybackRange(nextSegment.frameRange[0], nextSegment.frameRange);
    recordDiagnosticEvent('subtasks', 'create', {
      id: nextSegment.id,
      rangeStart: nextSegment.frameRange[0],
      rangeEnd: nextSegment.frameRange[1],
    });
  }, [addSubtask, setFrameWithinPlaybackRange, subtasks]);

  const handleDraftRangeChange = useCallback((range: [number, number] | null) => {
    if (!range) {
      shouldResumeAfterSelectionRef.current = false;
    }

    setSelectedSubtaskId(null);
    setSelectedRange(range);
    recordDiagnosticEvent('playback', 'draft-range-change', {
      rangeStart: range?.[0] ?? null,
      rangeEnd: range?.[1] ?? null,
    });
  }, []);

  const handleSelectionStart = useCallback(() => {
    shouldResumeAfterSelectionRef.current = isPlaying;
    recordDiagnosticEvent('playback', 'selection-start', { shouldResume: isPlaying });

    if (isPlaying) {
      togglePlayback();
    }
  }, [isPlaying, togglePlayback]);

  const handleSelectionComplete = useCallback((range: [number, number]) => {
    const shouldResume = shouldResumeAfterSelectionRef.current;
    const nextFrame = setFrameWithinPlaybackRange(range[0], range);

    setSelectedSubtaskId(null);
    setSelectedRange(range);
    shouldResumeAfterSelectionRef.current = false;
    recordDiagnosticEvent('playback', 'selection-finish', {
      shouldResume,
      rangeStart: range[0],
      rangeEnd: range[1],
      nextFrame,
    });

    if (shouldResume) {
      togglePlayback();

      requestAnimationFrame(() => {
        const video = videoRef.current;

        if (!video) {
          return;
        }

        const targetOriginalFrame = getOriginalIndex(nextFrame, insertedFrames, removedFrames);
        const targetTime = (targetOriginalFrame ?? nextFrame) / fps;

        ensureVideoPlaybackAtTime(video, targetTime);
      });
    }
  }, [ensureVideoPlaybackAtTime, fps, insertedFrames, removedFrames, setFrameWithinPlaybackRange, togglePlayback]);

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
    setSelectedSubtaskId(null);
    setSelectedRange(null);
    shouldResumeAfterSelectionRef.current = false;
  }, [currentDataset?.id, currentEpisode?.meta.index]);

  useEffect(() => {
    shouldAutoPlayOnMetadataLoadRef.current = autoPlay;
  }, [autoPlay, currentDataset?.id, currentEpisode?.meta.index]);

  useEffect(() => {
    if (selectedSubtaskId && !activeSubtask) {
      setSelectedSubtaskId(null);
    }
  }, [activeSubtask, selectedSubtaskId]);

  useEffect(() => {
    if (!activePlaybackRange) {
      return;
    }

    const clampedFrame = clampFrameToPlaybackRange(currentFrame, totalFrames, activePlaybackRange);

    if (clampedFrame !== currentFrame) {
      setCurrentFrame(clampedFrame);
    }
  }, [activePlaybackRange, currentFrame, setCurrentFrame, totalFrames]);

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
        setFrameWithinPlaybackRange(playbackRangeStart);
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
  }, [autoLoop, ensureVideoPlaybackAtTime, fps, isPlaying, playbackRangeEnd, playbackRangeStart, playbackSpeed, setFrameWithinPlaybackRange, shouldLoopPlaybackRange, totalFrames]);

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
      setFrameWithinPlaybackRange(playbackRangeStart);
      if (video) {
        ensureVideoPlaybackAtTime(video, playbackRangeStart / fps);
      }
    } else {
      if (isPlaying) togglePlayback();
      setFrameWithinPlaybackRange(playbackRangeEnd);
    }
  }, [autoLoop, ensureVideoPlaybackAtTime, fps, isPlaying, playbackRangeEnd, playbackRangeStart, setFrameWithinPlaybackRange, shouldLoopPlaybackRange, togglePlayback]);

  // Step forward / backward one frame (when paused)
  const stepFrame = useCallback(
    (delta: number) => {
      setFrameWithinPlaybackRange(currentFrame + delta);
    },
    [currentFrame, setFrameWithinPlaybackRange],
  );

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

  const diagnosticsStateSummary = useMemo(() => ([
    { label: 'Dataset', value: currentDataset?.id ?? 'none' },
    { label: 'Episode', value: currentEpisode ? String(currentEpisode.meta.index) : 'none' },
    { label: 'Tab', value: activeTab },
    { label: 'Frame', value: `${currentFrame} / ${Math.max(totalFrames - 1, 0)}` },
    { label: 'Playback', value: isPlaying ? 'playing' : 'paused' },
    { label: 'Selection', value: selectedSubtaskId ? `subtask:${selectedSubtaskId}` : selectedRange ? `${selectedRange[0]}-${selectedRange[1]}` : 'none' },
    { label: 'Channels', value: diagnosticsChannels.length > 0 ? diagnosticsChannels.join(', ') : 'none' },
  ]), [activeTab, currentDataset?.id, currentEpisode, currentFrame, diagnosticsChannels, isPlaying, selectedRange, selectedSubtaskId, totalFrames]);

  const availableDiagnosticsChannels = useMemo(() => {
    const configuredChannels = new Set(diagnosticsChannels.filter((channel) => channel !== 'all'));
    const eventChannels = new Set(diagnosticEvents.map((event) => event.channel));
    const channels = DIAGNOSTIC_CHANNEL_OPTIONS.filter((channel) => {
      if (channel === 'all') {
        return true;
      }

      return configuredChannels.has(channel) || eventChannels.has(channel);
    });

    return channels.length > 0 ? channels : ['all'];
  }, [diagnosticEvents, diagnosticsChannels]);

  const visibleDiagnosticEvents = useMemo(() => {
    if (selectedDiagnosticsChannel === 'all') {
      return diagnosticEvents;
    }

    return diagnosticEvents.filter((event) => event.channel === selectedDiagnosticsChannel);
  }, [diagnosticEvents, selectedDiagnosticsChannel]);
  const recentDiagnosticEvents = useMemo(() => {
    const keyCounts = new Map<string, number>();

    return visibleDiagnosticEvents.slice(-12).map((event) => {
      const baseKey = `${event.timestamp}-${event.channel}-${event.type}-${JSON.stringify(event.data ?? {})}`;
      const nextCount = (keyCounts.get(baseKey) ?? 0) + 1;

      keyCounts.set(baseKey, nextCount);

      return {
        ...event,
        uniqueKey: `${baseKey}-${nextCount}`,
      };
    });
  }, [visibleDiagnosticEvents]);

  const serializedDiagnosticEvents = useMemo(
    () => stringifyDiagnosticEvents(visibleDiagnosticEvents),
    [visibleDiagnosticEvents],
  );

  const handleClearVisibleDiagnostics = useCallback(() => {
    if (selectedDiagnosticsChannel === 'all') {
      clearDiagnosticEvents();
    } else {
      clearDiagnosticEvents(selectedDiagnosticsChannel);
    }

    setDiagnosticEvents(readDiagnosticEvents());
  }, [selectedDiagnosticsChannel]);

  const handleCopyDiagnostics = useCallback(async () => {
    if (!navigator.clipboard?.writeText) {
      setDiagnosticsClipboardStatus('Clipboard access is unavailable.');
      return;
    }

    await navigator.clipboard.writeText(serializedDiagnosticEvents);
    setDiagnosticsClipboardStatus('Copied diagnostics JSON.');
  }, [serializedDiagnosticEvents]);

  const handleDownloadDiagnostics = useCallback(() => {
    if (typeof window === 'undefined') {
      return;
    }

    const blob = new Blob([serializedDiagnosticEvents], { type: 'application/json' });
    const objectUrl = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    const channelLabel = selectedDiagnosticsChannel === 'all' ? 'all' : selectedDiagnosticsChannel;

    link.href = objectUrl;
    link.download = `dataviewer-diagnostics-${channelLabel}.json`;
    link.click();
    window.URL.revokeObjectURL(objectUrl);
    setDiagnosticsClipboardStatus('Downloaded diagnostics JSON.');
  }, [selectedDiagnosticsChannel, serializedDiagnosticEvents]);

  const renderSubtaskListCard = useCallback((compact = false) => (
    <Card className={compact ? 'min-h-[220px]' : 'mt-4'}>
      <CardContent className={compact ? 'p-3' : 'p-4'}>
        <SubtaskList
          selectedSubtaskId={selectedSubtaskId}
          onSelectionChange={handleSubtaskSelectionChange}
          draftRange={selectedRange}
          maxFrame={Math.max(totalFrames - 1, 0)}
          onDraftRangeChange={handleDraftRangeChange}
          onCreateSubtaskFromRange={handleCreateSubtaskFromRange}
        />
      </CardContent>
    </Card>
  ), [handleCreateSubtaskFromRange, handleDraftRangeChange, handleSubtaskSelectionChange, selectedRange, selectedSubtaskId, totalFrames]);

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

        <div data-keep-playback-selection="true">
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
                    onClick={() => setFrameWithinPlaybackRange(playbackRangeStart)}
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
                  onClick={() => setFrameWithinPlaybackRange(playbackRangeStart)}
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
              <div className="space-y-1">
                <div className="relative">
                  {playbackRangeHighlight && (
                    <div className="pointer-events-none absolute inset-y-1 left-0 right-0 rounded bg-muted/60">
                      <div
                        className="absolute inset-y-0 rounded bg-primary/20"
                        style={playbackRangeHighlight}
                      />
                    </div>
                  )}
                  <input
                    type="range"
                    min={playbackRangeStart}
                    max={playbackRangeEnd}
                    value={currentFrame}
                    onChange={(e) => setFrameWithinPlaybackRange(parseInt(e.target.value, 10))}
                    className="relative z-10 w-full"
                  />
                </div>
                {playbackRangeLabel && (
                  <p className="text-xs text-muted-foreground">
                    {playbackRangeLabel}: frames {playbackRangeStart} to {playbackRangeEnd}
                  </p>
                )}
              </div>
            }
          />
        </div>
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
    playbackRangeEnd,
    playbackRangeHighlight,
    playbackRangeLabel,
    playbackRangeStart,
    setPlaybackSpeed,
    setFrameWithinPlaybackRange,
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
      <Tabs value={activeTab} onValueChange={handleTabChange} className="flex-1 flex flex-col min-h-0">
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
                onClick={handleResetAllClick}
                disabled={!hasPendingEpisodeChanges}
              >
                <RotateCcw className="h-4 w-4 mr-2" />
                Reset All
              </Button>
              <Button
                variant="outline"
                onClick={handleOpenExportDialog}
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
            <div className="lg:col-span-2 min-h-0 overflow-y-auto">
              {renderPlaybackCard()}
              {renderSubtaskListCard()}
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
            <div className="flex min-h-[320px] flex-col gap-4 xl:min-h-0">
              {renderPlaybackCard(true)}
              {renderSubtaskListCard(true)}
            </div>
            <Card className="min-h-[340px] xl:min-h-0">
              <CardContent className="flex h-full min-h-0 flex-col gap-3 p-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <h3 className="text-sm font-medium">Trajectory Graph</h3>
                    <p className="text-xs text-muted-foreground">
                      Review joint motion, filters, and subtask boundaries alongside a compact episode player.
                    </p>
                  </div>
                  {(selectedRange || selectedSubtaskId) && (
                    <Button size="sm" variant="outline" onClick={clearPlaybackSelection}>
                      Clear Selection
                    </Button>
                  )}
                </div>
                <TrajectoryPlot
                  className="flex-1 min-h-[280px]"
                  selectedRange={selectedRange}
                  onSelectedRangeChange={handleDraftRangeChange}
                  onCreateSubtaskFromRange={handleCreateSubtaskFromRange}
                  onSeekFrame={handleGraphSeek}
                  onSelectionStart={handleSelectionStart}
                  onSelectionComplete={handleSelectionComplete}
                />
                <div className="rounded-lg border bg-muted/20 p-3">
                  <div className="mb-2 flex items-center justify-between gap-3">
                    <div>
                      <h4 className="text-sm font-medium">Subtask Timeline</h4>
                      <p className="text-xs text-muted-foreground">
                        Compare subtask ranges directly against trajectory changes on the same frame timeline.
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <SubtaskToolbar
                      selectedSegmentId={selectedSubtaskId}
                      onSelectionChange={handleSubtaskSelectionChange}
                    />
                  </div>
                  <SubtaskTimelineTrack
                    totalFrames={totalFrames}
                    editable
                    selectedSegmentId={selectedSubtaskId}
                    draftRange={selectedRange}
                    onSegmentClick={(segment) => handleSubtaskSelectionChange(segment.id)}
                  />
                </div>
              </CardContent>
            </Card>
          </div>
        </TabsContent>

        {/* Tab 2: Object Detection */}
        <TabsContent value="detection" className="mt-2.5 flex-1 min-h-0">
          <DetectionPanel />
        </TabsContent>
      </Tabs>

      {diagnosticsEnabled && (
        <Card className="shrink-0" data-testid="dataviewer-diagnostics-panel">
          <CardHeader className="py-3 px-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <CardTitle className="text-sm">Dataviewer Diagnostics</CardTitle>
                <p className="text-xs text-muted-foreground">
                  Whole-workspace diagnostics are enabled. Use the header toggle to hide this panel.
                </p>
              </div>
              <div className="text-right text-xs text-muted-foreground">
                <div>Range: {playbackRangeStart} to {playbackRangeEnd}</div>
                <div>Loop intent: {shouldLoopPlaybackRange ? 'enabled' : 'disabled'}</div>
              </div>
            </div>
          </CardHeader>
          <CardContent className="grid gap-3 border-t p-4 lg:grid-cols-[minmax(260px,320px)_minmax(0,1fr)]">
            <div className="rounded-lg border bg-muted/20 p-3">
              <h4 className="text-sm font-medium">Workspace State</h4>
              <div className="mt-2 grid gap-1 text-xs">
                {diagnosticsStateSummary.map((entry) => (
                  <div key={entry.label} className="flex items-center justify-between gap-3 border-b border-border/50 py-1 last:border-b-0">
                    <span className="text-muted-foreground">{entry.label}</span>
                    <span>{entry.value}</span>
                  </div>
                ))}
              </div>
            </div>
            <div className="rounded-lg border bg-muted/20 p-3">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <h4 className="text-sm font-medium">Recent Events</h4>
                  <p className="text-xs text-muted-foreground">
                    Filter, clear, copy, or download the visible diagnostics stream.
                  </p>
                </div>
                <div className="flex flex-col items-stretch gap-2 sm:min-w-[240px] sm:items-end">
                  <label className="flex items-center gap-2 text-xs text-muted-foreground">
                    <span>Filter Events</span>
                    <select
                      aria-label="Filter Events"
                      className="h-8 rounded-md border bg-background px-2 text-xs text-foreground"
                      value={selectedDiagnosticsChannel}
                      onChange={(event) => setSelectedDiagnosticsChannel(event.target.value)}
                    >
                      {availableDiagnosticsChannels.map((channel) => (
                        <option key={channel} value={channel}>
                          {channel}
                        </option>
                      ))}
                    </select>
                  </label>
                  <div className="flex flex-wrap gap-2 sm:justify-end">
                    <Button size="sm" variant="outline" onClick={handleClearVisibleDiagnostics}>
                      Clear Visible Events
                    </Button>
                    <Button size="sm" variant="outline" onClick={() => void handleCopyDiagnostics()}>
                      Copy JSON
                    </Button>
                    <Button size="sm" variant="outline" onClick={handleDownloadDiagnostics}>
                      Download JSON
                    </Button>
                  </div>
                  {diagnosticsClipboardStatus && (
                    <p className="text-right text-xs text-muted-foreground">{diagnosticsClipboardStatus}</p>
                  )}
                </div>
              </div>
              <div className="mt-2 max-h-48 overflow-y-auto rounded border bg-background/80 p-2 font-mono text-[11px]">
                {recentDiagnosticEvents.length === 0 ? (
                  <div className="text-muted-foreground">No diagnostics events recorded yet.</div>
                ) : (
                  recentDiagnosticEvents.map((event) => (
                    <div key={event.uniqueKey} className="border-b border-border/50 py-1 last:border-b-0">
                      <div>{event.channel}</div>
                      <div>{event.type}</div>
                      <div className="text-muted-foreground">{JSON.stringify(event.data ?? {})}</div>
                    </div>
                  ))
                )}
              </div>
            </div>
          </CardContent>
        </Card>
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
