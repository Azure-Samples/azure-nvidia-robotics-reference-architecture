/**
 * Full detection panel for the YOLO11 tab in AnnotationWorkspace.
 * 
 * This component provides a full-page detection experience with:
 * - Detection controls and progress indicator
 * - Detection viewer with bounding boxes
 * - Timeline navigation
 * - Filters and charts
 */

import { useMemo, useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Scan, BarChart3, Filter, Eye, Loader2, AlertTriangle, Play, Pause, RotateCcw } from 'lucide-react';
import { useObjectDetection } from '@/hooks/use-object-detection';
import { useDatasetStore, useEpisodeStore, usePlaybackControls } from '@/stores';
import { DetectionViewer } from './DetectionViewer';
import { DetectionTimeline } from './DetectionTimeline';
import { DetectionFilters } from './DetectionFilters';
import { DetectionCharts } from './DetectionCharts';

export function DetectionPanel() {
  const currentDataset = useDatasetStore((state) => state.currentDataset);
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);
  const { currentFrame, setCurrentFrame, isPlaying, togglePlayback, playbackSpeed, setPlaybackSpeed } = usePlaybackControls();

  console.log('[DetectionPanel] Mounted', { 
    datasetId: currentDataset?.id,
    episodeIdx: currentEpisode?.meta.index,
  });

  const {
    data,
    filteredData,
    isLoading,
    isRunning,
    error,
    needsRerun,
    filters,
    setFilters,
    runDetection,
    availableClasses,
  } = useObjectDetection();

  console.log('[DetectionPanel] Detection state', { 
    hasData: !!data, 
    isLoading, 
    isRunning,
    error: error?.message,
  });

  // Progress simulation for detection
  const [progress, setProgress] = useState(0);
  const totalFrames = currentEpisode?.meta.length || 100;

  // Simulate progress during detection
  useEffect(() => {
    if (!isRunning) {
      setProgress(0);
      return;
    }

    // Estimate ~50ms per frame for detection
    const estimatedTotalTime = totalFrames * 50;
    const intervalTime = 100;
    const increment = (intervalTime / estimatedTotalTime) * 100;

    const interval = setInterval(() => {
      setProgress((prev) => {
        const next = prev + increment;
        return next >= 95 ? 95 : next; // Cap at 95%, completion will set to 100
      });
    }, intervalTime);

    return () => clearInterval(interval);
  }, [isRunning, totalFrames]);

  // Set progress to 100% when detection completes
  useEffect(() => {
    if (data && !isRunning && progress > 0) {
      setProgress(100);
      // Reset after a short delay
      const timeout = setTimeout(() => setProgress(0), 1000);
      return () => clearTimeout(timeout);
    }
  }, [data, isRunning, progress]);

  // Get current frame detections
  const currentDetections = useMemo(() => {
    if (!filteredData) return [];
    const frameResult = filteredData.detections_by_frame.find(
      (r) => r.frame === currentFrame
    );
    return frameResult?.detections || [];
  }, [filteredData, currentFrame]);

  // Build image URL for detection overlay
  const imageUrl = useMemo(() => {
    if (!currentDataset || !currentEpisode) return null;
    return `/api/datasets/${currentDataset.id}/episodes/${currentEpisode.meta.index}/frames/${currentFrame}?camera=il-camera`;
  }, [currentDataset, currentEpisode, currentFrame]);

  if (!currentDataset || !currentEpisode) {
    return (
      <div className="flex items-center justify-center h-full">
        <Card className="max-w-md">
          <CardHeader>
            <CardTitle>No Episode Selected</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-muted-foreground">
              Select a dataset and episode from the sidebar to run object detection.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex-1 grid grid-cols-1 lg:grid-cols-3 gap-4 min-h-0 overflow-auto">
      {/* Left panel: Detection viewer and timeline */}
      <div className="lg:col-span-2 flex flex-col gap-4">
        {/* Detection Controls */}
        <Card className="flex-shrink-0">
          <CardContent className="p-4">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <Scan className="h-5 w-5 text-primary" />
                <div>
                  <h3 className="font-medium">YOLO11 Object Detection</h3>
                  <p className="text-xs text-muted-foreground">
                    Detect objects in all frames of this episode
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                {needsRerun && data && (
                  <span className="text-xs text-orange-500 flex items-center gap-1">
                    <AlertTriangle className="h-3 w-3" />
                    Edits detected
                  </span>
                )}
                <Button
                  onClick={() => {
                    console.log('[DetectionPanel] Run Detection clicked');
                    runDetection({ confidence: filters.minConfidence });
                  }}
                  disabled={isRunning || isLoading}
                >
                  {isRunning ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Detecting...
                    </>
                  ) : (
                    <>
                      <Scan className="h-4 w-4 mr-2" />
                      {needsRerun ? 'Re-run Detection' : data ? 'Run Again' : 'Run Detection'}
                    </>
                  )}
                </Button>
              </div>
            </div>

            {/* Progress indicator */}
            {isRunning && (
              <div className="space-y-2">
                <div className="flex justify-between text-xs text-muted-foreground">
                  <span>Processing {totalFrames} frames...</span>
                  <span>{Math.round(progress)}%</span>
                </div>
                <Progress value={progress} className="h-2" />
              </div>
            )}

            {error && (
              <div className="bg-destructive/10 text-destructive p-3 rounded text-sm">
                <strong>Error:</strong> {error instanceof Error ? error.message : 'Detection failed'}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Detection Viewer */}
        <Card className="flex-shrink-0">
          <CardContent className="p-4">
            {!data && !isRunning ? (
              <div className="aspect-video bg-muted rounded-lg flex items-center justify-center">
                <div className="text-center text-muted-foreground">
                  <Scan className="h-16 w-16 mx-auto mb-4 opacity-30" />
                  <p className="text-lg mb-2">No detection results</p>
                  <p className="text-sm">Click "Run Detection" to analyze all frames with YOLO11</p>
                </div>
              </div>
            ) : isRunning && !data ? (
              <div className="aspect-video bg-muted rounded-lg flex items-center justify-center">
                <div className="text-center text-muted-foreground">
                  <Loader2 className="h-16 w-16 mx-auto mb-4 animate-spin opacity-50" />
                  <p className="text-lg mb-2">Processing frames...</p>
                  <p className="text-sm">This may take a moment for episodes with many frames</p>
                </div>
              </div>
            ) : (
              <>
                <div className="aspect-video mb-4">
                  <DetectionViewer imageUrl={imageUrl} detections={currentDetections} />
                </div>

                {/* Playback Controls for Detection */}
                <div className="flex items-center gap-4 p-3 bg-muted rounded-lg">
                  <Button size="sm" onClick={togglePlayback} className="gap-1">
                    {isPlaying ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
                    {isPlaying ? 'Pause' : 'Play'}
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => setCurrentFrame(0)}>
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
              </>
            )}
          </CardContent>
        </Card>

        {/* Detection Timeline */}
        {data && (
          <Card className="flex-shrink-0">
            <CardHeader className="py-3 px-4">
              <CardTitle className="text-sm">Detection Timeline</CardTitle>
            </CardHeader>
            <CardContent className="p-4 pt-0">
              <p className="text-sm text-muted-foreground mb-3">
                Frame {currentFrame} - {currentDetections.length} detection{currentDetections.length !== 1 ? 's' : ''}
              </p>
              <DetectionTimeline
                detectionsPerFrame={filteredData?.detections_by_frame || []}
                totalFrames={totalFrames}
                currentFrame={currentFrame}
                onFrameClick={setCurrentFrame}
              />
            </CardContent>
          </Card>
        )}

        {/* Charts */}
        {data && filteredData && (
          <Card className="flex-shrink-0">
            <CardHeader className="py-3 px-4">
              <CardTitle className="text-sm flex items-center gap-2">
                <BarChart3 className="h-4 w-4" />
                Detection Statistics
              </CardTitle>
            </CardHeader>
            <CardContent className="p-4 pt-0">
              <DetectionCharts summary={filteredData} />
            </CardContent>
          </Card>
        )}
      </div>

      {/* Right panel: Filters and details */}
      <div className="flex flex-col gap-4 min-h-0">
        {/* Filters */}
        <Card className="flex-1 flex flex-col min-h-0 overflow-auto">
          <CardHeader className="py-3 px-4">
            <CardTitle className="text-sm flex items-center gap-2">
              <Filter className="h-4 w-4" />
              Detection Filters
            </CardTitle>
          </CardHeader>
          <CardContent className="p-4 pt-0">
            <DetectionFilters
              filters={filters}
              availableClasses={availableClasses}
              onFiltersChange={setFilters}
            />
          </CardContent>
        </Card>

        {/* Current Frame Detections */}
        {data && currentDetections.length > 0 && (
          <Card className="flex-shrink-0 max-h-80 overflow-auto">
            <CardHeader className="py-3 px-4">
              <CardTitle className="text-sm flex items-center gap-2">
                <Eye className="h-4 w-4" />
                Frame {currentFrame} Detections
              </CardTitle>
            </CardHeader>
            <CardContent className="p-4 pt-0">
              <div className="space-y-2">
                {currentDetections.map((det, i) => (
                  <div
                    key={i}
                    className="flex items-center justify-between p-2 bg-muted rounded text-sm"
                  >
                    <span className="font-medium">{det.class_name}</span>
                    <span className="text-muted-foreground">
                      {(det.confidence * 100).toFixed(1)}%
                    </span>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Summary Stats */}
        {data && (
          <Card className="flex-shrink-0">
            <CardHeader className="py-3 px-4">
              <CardTitle className="text-sm">Summary</CardTitle>
            </CardHeader>
            <CardContent className="p-4 pt-0">
              <div className="grid grid-cols-2 gap-3 text-center">
                <div className="bg-muted p-3 rounded-lg">
                  <div className="text-xl font-bold text-blue-500">
                    {filteredData?.total_detections || 0}
                  </div>
                  <div className="text-xs text-muted-foreground">Total</div>
                </div>
                <div className="bg-muted p-3 rounded-lg">
                  <div className="text-xl font-bold text-green-500">
                    {availableClasses.length}
                  </div>
                  <div className="text-xs text-muted-foreground">Classes</div>
                </div>
                <div className="bg-muted p-3 rounded-lg">
                  <div className="text-xl font-bold text-purple-500">
                    {data.processed_frames}
                  </div>
                  <div className="text-xs text-muted-foreground">Frames</div>
                </div>
                <div className="bg-muted p-3 rounded-lg">
                  <div className="text-xl font-bold text-orange-500">
                    {(filters.minConfidence * 100).toFixed(0)}%
                  </div>
                  <div className="text-xs text-muted-foreground">Min Conf</div>
                </div>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
