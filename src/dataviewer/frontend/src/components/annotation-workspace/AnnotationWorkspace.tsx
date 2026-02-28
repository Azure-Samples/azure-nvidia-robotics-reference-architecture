import { useState, useMemo, useEffect, useCallback, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Download, Layers, Play, Pause, RotateCcw, Video, Scan, SkipForward, SkipBack } from 'lucide-react';
import { Timeline, TrajectoryPlot } from '@/components/episode-viewer';
import { TransformControls, FrameRemovalToolbar, FrameInsertionToolbar, TrajectoryEditor, ColorAdjustmentControls } from '@/components/frame-editor';
import { SubtaskTimelineTrack, SubtaskToolbar } from '@/components/subtask-timeline';
import { ExportDialog } from '@/components/export';
import { DetectionPanel } from '@/components/object-detection';
import { LabelPanel } from '@/components/annotation-panel';
import {
  useDatasetStore,
  useEpisodeStore,
  useEditStore,
  useEditDirtyState,
  usePlaybackControls,
} from '@/stores';
import {
  useFrameInsertionState,
  getOriginalIndex,
  getEffectiveFrameCount,
} from '@/stores/edit-store';

/**
 * Unified annotation workspace integrating episode viewing, editing, and export.
 *
 * Uses native <video> for smooth playback and per-frame <img> for
 * frame-accurate scrubbing when paused.
 */
export function AnnotationWorkspace() {
  const [exportDialogOpen, setExportDialogOpen] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const [interpolatedImageUrl, setInterpolatedImageUrl] = useState<string | null>(null);

  const currentDataset = useDatasetStore((state) => state.currentDataset);
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);
  const removedFrames = useEditStore((state) => state.removedFrames);
  const initializeEdit = useEditStore((state) => state.initializeEdit);
  const editDatasetId = useEditStore((state) => state.datasetId);
  const editEpisodeIndex = useEditStore((state) => state.episodeIndex);
  const { insertedFrames } = useFrameInsertionState();
  const { isDirty: hasEdits } = useEditDirtyState();
  const { currentFrame, isPlaying, playbackSpeed, setCurrentFrame, togglePlayback, setPlaybackSpeed } = usePlaybackControls();

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

  const fps = currentDataset?.fps ?? 30;

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

  // Get current trajectory point for display (use original index if available)
  const currentPoint = useMemo(() => {
    const trajectoryData = currentEpisode?.trajectoryData || [];
    if (trajectoryData.length === 0) return null;

    if (originalFrameIndex !== null) {
      return trajectoryData[Math.min(originalFrameIndex, trajectoryData.length - 1)];
    }

    if (adjacentFrames) {
      const before = trajectoryData[adjacentFrames.beforeFrame];
      const after = trajectoryData[adjacentFrames.afterFrame];
      if (before && after) {
        const t = adjacentFrames.factor;
        return {
          frame: currentFrame,
          timestamp: before.timestamp + (after.timestamp - before.timestamp) * t,
          jointPositions: before.jointPositions.map((v, i) =>
            v + (after.jointPositions[i] - v) * t
          ),
          jointVelocities: before.jointVelocities.map((v, i) =>
            v + (after.jointVelocities[i] - v) * t
          ),
        };
      }
    }
    return null;
  }, [currentEpisode?.trajectoryData, originalFrameIndex, currentFrame, adjacentFrames]);

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

  // Sync play/pause and playback speed to native video element
  useEffect(() => {
    const video = videoRef.current;
    if (!video || !videoSrc) return;

    video.playbackRate = playbackSpeed;
    if (isPlaying) {
      video.play().catch(() => { /* autoplay may be blocked */ });
    } else {
      video.pause();
    }
  }, [isPlaying, playbackSpeed, videoSrc]);

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

  // When the video ends, stop playback
  const handleVideoEnded = useCallback(() => {
    if (isPlaying) togglePlayback();
    setCurrentFrame(totalFrames - 1);
  }, [isPlaying, togglePlayback, setCurrentFrame, totalFrames]);

  // Step forward / backward one frame (when paused)
  const stepFrame = useCallback(
    (delta: number) => {
      const next = Math.max(0, Math.min(totalFrames - 1, currentFrame + delta));
      setCurrentFrame(next);
    },
    [currentFrame, totalFrames, setCurrentFrame],
  );

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
    <div className="flex flex-col h-full gap-4 p-4">
      {/* Header */}
      <div className="flex justify-between items-center">
        <div className="flex items-center gap-2">
          <h2 className="text-lg font-semibold">
            Episode {currentEpisode.meta.index}
          </h2>
          {hasEdits && (
            <span className="text-xs text-orange-500 font-medium">
              (has edits)
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            onClick={() => setExportDialogOpen(true)}
          >
            <Download className="h-4 w-4 mr-2" />
            Export
          </Button>
        </div>
      </div>

      {/* Main tabbed content area */}
      <Tabs defaultValue="episode" className="flex-1 flex flex-col min-h-0">
        <TabsList className="w-fit">
          <TabsTrigger value="episode" className="gap-2">
            <Video className="h-4 w-4" />
            Episode Viewer
          </TabsTrigger>
          <TabsTrigger value="detection" className="gap-2">
            <Scan className="h-4 w-4" />
            Object Detection
          </TabsTrigger>
        </TabsList>

        {/* Tab 1: Episode Viewer */}
        <TabsContent value="episode" className="flex-1 mt-4 min-h-0 overflow-auto">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            {/* Left panel: Video and timeline */}
            <div className="lg:col-span-2 flex flex-col gap-4">
              {/* Frame display with playback controls */}
              <Card className="flex-shrink-0">
                <CardContent className="p-4">
                  <div className="aspect-video bg-black rounded-lg flex items-center justify-center overflow-hidden relative">
                    {/* Hidden canvas for image blending */}
                    <canvas ref={canvasRef} className="hidden" />

                    {videoSrc ? (
                      <video
                        ref={videoRef}
                        src={videoSrc}
                        onEnded={handleVideoEnded}
                        muted
                        playsInline
                        preload="auto"
                        className="max-w-full max-h-full object-contain"
                      />
                    ) : isInsertedFrame && interpolatedImageUrl ? (
                      <img
                        src={interpolatedImageUrl}
                        alt={`Interpolated frame ${currentFrame}`}
                        className="max-w-full max-h-full object-contain"
                      />
                    ) : frameImageUrl ? (
                      <img
                        src={frameImageUrl}
                        alt={`Frame ${currentFrame}`}
                        className="max-w-full max-h-full object-contain"
                      />
                    ) : (
                      <span className="text-white">Frame {currentFrame + 1} of {totalFrames}</span>
                    )}

                    {/* Inserted frame indicator */}
                    {isInsertedFrame && (
                      <div className="absolute top-2 left-2 bg-blue-500/80 text-white text-xs px-2 py-1 rounded">
                        Interpolated Frame
                      </div>
                    )}
                  </div>

                  {/* Playback Controls */}
                  <div className="mt-3 flex items-center gap-4 p-3 bg-muted rounded-lg">
                    <Button
                      size="sm"
                      onClick={togglePlayback}
                      className="gap-1"
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
                    <div className="flex items-center gap-2">
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
                    <input
                      type="range"
                      min={0}
                      max={totalFrames - 1}
                      value={currentFrame}
                      onChange={(e) => setCurrentFrame(parseInt(e.target.value, 10))}
                      className="flex-1"
                    />
                    <span className="text-sm text-muted-foreground w-24 text-right">
                      {currentFrame + 1} / {totalFrames}
                    </span>
                  </div>
                </CardContent>
              </Card>

              {/* Subtask timeline - moved up for visibility */}
              <Card className="flex-shrink-0">
                <CardHeader className="py-3 px-4">
                  <div className="flex items-center justify-between">
                    <CardTitle className="text-sm flex items-center gap-2">
                      <Layers className="h-4 w-4" />
                      Subtask Segments
                    </CardTitle>
                    <SubtaskToolbar />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-0">
                  <SubtaskTimelineTrack totalFrames={totalFrames} editable />
                </CardContent>
              </Card>

              {/* Trajectory Plot */}
              <Card className="h-[250px] flex-shrink-0">
                <CardHeader className="py-3 px-4">
                  <CardTitle className="text-sm">Trajectory</CardTitle>
                </CardHeader>
                <CardContent className="p-4 pt-0 h-[calc(100%-48px)]">
                  <TrajectoryPlot className="h-full" />
                </CardContent>
              </Card>

              {/* Current Frame Data */}
              {currentPoint && (
                <Card className="flex-shrink-0">
                  <CardContent className="p-4">
                    <div className="grid grid-cols-3 gap-4 text-sm">
                      {/* Right Arm */}
                      <div>
                        <div className="font-medium mb-2 text-blue-600">Right Arm</div>
                        <div className="space-y-1 font-mono text-xs">
                          <div className="bg-muted px-2 py-1 rounded">
                            Pos: [{currentPoint.jointPositions[0]?.toFixed(3)}, {currentPoint.jointPositions[1]?.toFixed(3)}, {currentPoint.jointPositions[2]?.toFixed(3)}]
                          </div>
                          <div className="bg-muted px-2 py-1 rounded">
                            Gripper: {currentPoint.jointPositions[7]?.toFixed(3)}
                          </div>
                        </div>
                      </div>
                      {/* Left Arm */}
                      <div>
                        <div className="font-medium mb-2 text-green-600">Left Arm</div>
                        <div className="space-y-1 font-mono text-xs">
                          <div className="bg-muted px-2 py-1 rounded">
                            Pos: [{currentPoint.jointPositions[8]?.toFixed(3)}, {currentPoint.jointPositions[9]?.toFixed(3)}, {currentPoint.jointPositions[10]?.toFixed(3)}]
                          </div>
                          <div className="bg-muted px-2 py-1 rounded">
                            Gripper: {currentPoint.jointPositions[15]?.toFixed(3)}
                          </div>
                        </div>
                      </div>
                      {/* Frame Info */}
                      <div>
                        <div className="font-medium mb-2">Frame Info</div>
                        <div className="space-y-1 text-xs">
                          <div className="bg-muted px-2 py-1 rounded">
                            Time: {currentPoint.timestamp.toFixed(3)}s
                          </div>
                          <div className="bg-muted px-2 py-1 rounded">
                            Frame: {currentFrame} / {totalFrames - 1}
                          </div>
                        </div>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              )}

              {/* Timeline with annotations */}
              <Card className="flex-shrink-0">
                <CardHeader className="py-3 px-4">
                  <CardTitle className="text-sm">Timeline</CardTitle>
                </CardHeader>
                <CardContent className="p-4 pt-0">
                  <Timeline />
                </CardContent>
              </Card>
            </div>

            {/* Right panel: Annotation/edit tools */}
            <div className="flex flex-col min-h-0">
              <Card className="flex-1 flex flex-col min-h-0 overflow-auto">
                <CardHeader className="py-3 px-4">
                  <CardTitle className="text-sm">Edit Tools</CardTitle>
                </CardHeader>
                <CardContent className="p-4 pt-0 space-y-6">
                  {/* Episode Labels */}
                  <LabelPanel episodeIndex={currentEpisode.meta.index} />

                  <Separator />

                  {/* Frame Removal Section */}
                  <div>
                    <h3 className="text-sm font-medium mb-3">Frame Removal</h3>
                    <FrameRemovalToolbar />
                  </div>

                  <Separator />

                  {/* Frame Insertion Section */}
                  <div>
                    <h3 className="text-sm font-medium mb-3">Frame Insertion</h3>
                    <FrameInsertionToolbar />
                  </div>

                  <Separator />

                  {/* Image Transform Section */}
                  <div>
                    <h3 className="text-sm font-medium mb-3">Image Transform</h3>
                    <TransformControls />
                  </div>

                  <Separator />

                  {/* Color Adjustment Section */}
                  <div>
                    <h3 className="text-sm font-medium mb-3">Color Adjustments</h3>
                    <ColorAdjustmentControls />
                  </div>

                  <Separator />

                  {/* Trajectory Editor Section */}
                  <div>
                    <h3 className="text-sm font-medium mb-3">Trajectory Adjustment</h3>
                    <TrajectoryEditor />
                  </div>
                </CardContent>
              </Card>
            </div>
          </div>
        </TabsContent>

        {/* Tab 2: Object Detection */}
        <TabsContent value="detection" className="flex-1 mt-4 min-h-0">
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
