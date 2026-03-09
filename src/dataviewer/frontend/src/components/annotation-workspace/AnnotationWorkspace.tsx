import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

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
import { useAnnotationWorkspaceMediaController } from '@/components/annotation-workspace/useAnnotationWorkspaceMediaController';
import { useAnnotationWorkspacePlayback } from '@/components/annotation-workspace/useAnnotationWorkspacePlayback';
import { ExportDialog } from '@/components/export';
import { DetectionPanel } from '@/components/object-detection';
import { Tabs, TabsContent } from '@/components/ui/tabs';
import { useSaveEpisodeLabels } from '@/hooks/use-labels';
import {
  isDiagnosticsEnabled,
  recordDiagnosticEvent,
} from '@/lib/playback-diagnostics';
import {
  useDatasetStore,
  useEditDirtyState,
  useEditStore,
  useEpisodeStore,
  useFrameInsertionState,
  usePlaybackControls,
  usePlaybackSettings,
  useViewerDisplay,
} from '@/stores';
import {
  getEffectiveFrameCount,
  getOriginalIndex,
} from '@/stores/edit-store';
import { useLabelStore } from '@/stores/label-store';
import { createDefaultSubtask } from '@/types/episode-edit';

const EMPTY_LABELS: string[] = [];

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
  const [activeTab, setActiveTab] = useState('episode');
  const seekVideoFrameRef = useRef(
    (frame: number, _range: [number, number] | null, _constrainToRange = true) => frame,
  );
  const resumePlaybackRef = useRef((_: number) => {});

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

  // Calculate effective frame count including insertions and removals
  const totalFrames = useMemo(() => {
    return getEffectiveFrameCount(originalFrameCount, insertedFrames, removedFrames);
  }, [originalFrameCount, insertedFrames, removedFrames]);

  // Map current effective frame to original frame index
  const originalFrameIndex = useMemo(() => {
    return getOriginalIndex(currentFrame, insertedFrames, removedFrames);
  }, [currentFrame, insertedFrames, removedFrames]);

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
    onSeekFrame: (frame, range, constrainToRange) => seekVideoFrameRef.current(frame, range, constrainToRange),
    onResumePlayback: (frame) => resumePlaybackRef.current(frame),
    onTogglePlayback: togglePlayback,
    onSetCurrentFrame: setCurrentFrame,
    onRecordEvent: recordDiagnosticEvent,
  });

  const {
    canvasRef,
    displayFilter,
    frameImageUrl,
    handleLoadedMetadata,
    handleResumePlayback,
    handleVideoEnded,
    interpolatedImageUrl,
    isInsertedFrame,
    seekVideoFrame,
    videoRef,
    videoSrc,
  } = useAnnotationWorkspaceMediaController({
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
    onSetCurrentFrame: setCurrentFrame,
    onTogglePlayback: togglePlayback,
    onSetFrameWithinPlaybackRange: setFrameWithinActivePlaybackRange,
    onRecordEvent: recordDiagnosticEvent,
  });

  seekVideoFrameRef.current = seekVideoFrame;
  resumePlaybackRef.current = handleResumePlayback;

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
