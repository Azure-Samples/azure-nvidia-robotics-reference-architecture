/**
 * Trajectory visualization component showing joint positions over time.
 *
 * Performance optimizations:
 * - CurrentFrameMarker is isolated to prevent full chart re-renders on frame changes
 * - Chart data is memoized based on trajectory data and velocity toggle
 * - Reference line position updates without re-rendering chart lines
 */

import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

import { Button } from '@/components/ui/button'
import { useJointConfigDefaults, useSaveJointConfig, useSaveJointConfigDefaults } from '@/hooks/use-joint-config'
import { getAutoSelectedJointsForEpisode } from '@/lib/joint-significance'
import { cn } from '@/lib/utils'
import { useEpisodeStore } from '@/stores'
import { useTrajectoryAdjustmentState } from '@/stores/edit-store'
import { useJointConfigStore } from '@/stores/joint-config-store'
import type { TrajectoryAdjustment } from '@/types/episode-edit'

import { getJointLabel, JOINT_COLORS } from './joint-constants'
import { JointConfigDefaultsEditor } from './JointConfigDefaultsEditor'
import { JointSelector } from './JointSelector'

/**
 * Isolated current frame marker component.
 * Only re-renders when currentFrame changes, preventing full chart re-renders.
 */
const CurrentFrameMarker = memo(function CurrentFrameMarker() {
  const currentFrame = useEpisodeStore((state) => state.currentFrame);

  return (
    <ReferenceLine
      x={currentFrame}
      stroke="hsl(var(--primary))"
      strokeWidth={2}
      strokeDasharray="4 4"
    />
  );
});

interface TrajectoryPlotProps {
  /** Additional CSS classes */
  className?: string;
  /** Callback invoked after a successful save */
  onSaved?: () => void;
  /** Active graph selection range */
  selectedRange?: [number, number] | null;
  /** Called when the graph selection changes */
  onSelectedRangeChange?: (range: [number, number] | null) => void;
  /** Called when the user creates a subtask from the selected range */
  onCreateSubtaskFromRange?: (range: [number, number]) => void;
  /** Called when the user begins dragging a graph selection */
  onSelectionStart?: () => void;
  /** Called after a graph drag selection is committed */
  onSelectionComplete?: (range: [number, number]) => void;
}

function applyTrajectoryAdjustment(
  value: number,
  jointIndex: number,
  adjustment: TrajectoryAdjustment | undefined,
) {
  let adjusted = value;

  if (!adjustment) {
    return adjusted;
  }

  if (adjustment.rightArmDelta && jointIndex >= 0 && jointIndex <= 2) {
    adjusted += adjustment.rightArmDelta[jointIndex];
  }

  if (adjustment.leftArmDelta && jointIndex >= 8 && jointIndex <= 10) {
    adjusted += adjustment.leftArmDelta[jointIndex - 8];
  }

  if (jointIndex === 7 && adjustment.rightGripperOverride !== undefined) {
    adjusted = adjustment.rightGripperOverride;
  }

  if (jointIndex === 15 && adjustment.leftGripperOverride !== undefined) {
    adjusted = adjustment.leftGripperOverride;
  }

  return adjusted;
}

function normalizeSeries(value: number, min: number, max: number) {
  if (max === min) {
    return 0;
  }

  return (value - min) / (max - min);
}

const TRAJECTORY_CHART_MIN_HEIGHT = 60
const TRAJECTORY_CHART_INITIAL_DIMENSION = { width: 320, height: TRAJECTORY_CHART_MIN_HEIGHT }



/**
 * Line chart showing joint positions over time with current frame marker.
 *
 * Performance: Uses isolated CurrentFrameMarker to prevent full chart re-renders
 * when scrubbing through frames.
 *
 * @example
 * ```tsx
 * <TrajectoryPlot className="h-64" />
 * ```
 */
export const TrajectoryPlot = memo(function TrajectoryPlot({
  className,
  onSaved,
  selectedRange = null,
  onSelectedRangeChange,
  onCreateSubtaskFromRange,
  onSelectionStart,
  onSelectionComplete,
}: TrajectoryPlotProps) {
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);
  const setCurrentFrame = useEpisodeStore((state) => state.setCurrentFrame);
  const { trajectoryAdjustments } = useTrajectoryAdjustmentState();
  const jointConfig = useJointConfigStore((state) => state.config);
  const updateLabel = useJointConfigStore((state) => state.updateLabel);
  const updateGroupLabel = useJointConfigStore((state) => state.updateGroupLabel);
  const createGroup = useJointConfigStore((state) => state.createGroup);
  const deleteGroup = useJointConfigStore((state) => state.deleteGroup);
  const moveJoint = useJointConfigStore((state) => state.moveJoint);
  const { save: saveJointConfig } = useSaveJointConfig();
  const { data: defaults } = useJointConfigDefaults();
  const saveDefaults = useSaveJointConfigDefaults();

  const [selectedJoints, setSelectedJoints] = useState<number[]>([]);
  const [showVelocity, setShowVelocity] = useState(false);
  const [showNormalized, setShowNormalized] = useState(true);
  const [defaultsOpen, setDefaultsOpen] = useState(false);
  const [selectionAnchorFrame, setSelectionAnchorFrame] = useState<number | null>(null);
  const [selectionAnchorX, setSelectionAnchorX] = useState<number | null>(null);
  const [contextMenuPosition, setContextMenuPosition] = useState<{ x: number; y: number } | null>(null);
  const selectionSurfaceRef = useRef<HTMLDivElement>(null);
  const contextMenuRef = useRef<HTMLDivElement>(null);

  const withSave = useCallback(
    <T extends unknown[]>(fn: (...args: T) => void) =>
      (...args: T) => {
        fn(...args)
        // Defer save to allow store update to complete
        queueMicrotask(() => saveJointConfig(onSaved))
      },
    [onSaved, saveJointConfig],
  );

  const resolveLabel = useCallback(
    (idx: number) => jointConfig.labels[String(idx)] ?? getJointLabel(idx),
    [jointConfig.labels],
  );

  // Transform trajectory data for Recharts - memoized
  // Apply trajectory adjustments to show modified values
  const chartData = useMemo(() => {
    if (!currentEpisode?.trajectoryData) return [];

    const seriesValues = currentEpisode.trajectoryData.map((point) => {
      const adjustment = trajectoryAdjustments.get(point.frame);

      return showVelocity
        ? point.jointVelocities
        : point.jointPositions.map((position, jointIndex) =>
            applyTrajectoryAdjustment(position, jointIndex, adjustment),
          );
    });

    const shouldNormalizePositions = showNormalized && !showVelocity;
    const normalizedRanges = shouldNormalizePositions
      ? seriesValues[0]?.map((_, jointIndex) => {
          const values = seriesValues.map((pointValues) => pointValues[jointIndex]);

          return {
            min: Math.min(...values),
            max: Math.max(...values),
          };
        }) ?? []
      : [];

    return currentEpisode.trajectoryData.map((point, pointIndex) => {
      const adjustment = trajectoryAdjustments.get(point.frame);
      const data: Record<string, number | boolean> = {
        frame: point.frame,
        timestamp: point.timestamp,
        hasAdjustment: !!adjustment,
      };

      // Add selected joint data with adjustments applied
      const pointValues = seriesValues[pointIndex] ?? (showVelocity ? point.jointVelocities : point.jointPositions);

      pointValues.forEach((value, jointIndex) => {
        if (shouldNormalizePositions) {
          const range = normalizedRanges[jointIndex];

          data[`joint_${jointIndex}`] = range
            ? normalizeSeries(value, range.min, range.max)
            : value;
          return;
        }

        data[`joint_${jointIndex}`] = value;
      });

      return data;
    });
  }, [currentEpisode?.trajectoryData, showNormalized, showVelocity, trajectoryAdjustments]);

  // Get joint count - memoized
  const jointCount = useMemo(() => {
    if (!currentEpisode?.trajectoryData?.[0]) return 0;
    return currentEpisode.trajectoryData[0].jointPositions.length;
  }, [currentEpisode?.trajectoryData]);

  const autoSelectedJoints = useMemo(
    () => getAutoSelectedJointsForEpisode(currentEpisode?.trajectoryData ?? [], jointConfig.groups, jointCount),
    [currentEpisode?.trajectoryData, jointConfig.groups, jointCount],
  )

  useEffect(() => {
    setSelectedJoints(autoSelectedJoints)
  }, [autoSelectedJoints])

  useEffect(() => {
    if (!selectedRange) {
      setContextMenuPosition(null)
    }
  }, [selectedRange])

  useEffect(() => {
    if (!selectedRange) {
      return
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') {
        return
      }

      setContextMenuPosition(null)
      onSelectedRangeChange?.(null)
    }

    const handlePointerDown = (event: PointerEvent) => {
      const target = event.target

      if (!(target instanceof Element)) {
        return
      }

      if (selectionSurfaceRef.current?.contains(target) || contextMenuRef.current?.contains(target)) {
        return
      }

      if (target.closest('[data-keep-playback-selection="true"]')) {
        return
      }

      setContextMenuPosition(null)
      onSelectedRangeChange?.(null)
    }

    window.addEventListener('keydown', handleKeyDown)
    window.addEventListener('pointerdown', handlePointerDown)

    return () => {
      window.removeEventListener('keydown', handleKeyDown)
      window.removeEventListener('pointerdown', handlePointerDown)
    }
  }, [onSelectedRangeChange, selectedRange])

  const frameFromClientX = useCallback((clientX: number) => {
    const bounds = selectionSurfaceRef.current?.getBoundingClientRect()

    if (!bounds || bounds.width <= 0) {
      return 0
    }

    const relativeX = Math.max(0, Math.min(clientX - bounds.left, bounds.width))
    const ratio = bounds.width === 0 ? 0 : relativeX / bounds.width

    return Math.round(ratio * Math.max((currentEpisode?.meta.length ?? 1) - 1, 0))
  }, [currentEpisode?.meta.length])

  const updateSelectedRange = useCallback((startFrame: number, endFrame: number) => {
    onSelectedRangeChange?.([
      Math.min(startFrame, endFrame),
      Math.max(startFrame, endFrame),
    ])
  }, [onSelectedRangeChange])

  const handleSelectionPointerDown = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) {
      return
    }

    if ('setPointerCapture' in event.currentTarget) {
      event.currentTarget.setPointerCapture(event.pointerId)
    }
    setContextMenuPosition(null)
    setSelectionAnchorX(event.clientX)
    setSelectionAnchorFrame(frameFromClientX(event.clientX))
    onSelectionStart?.()
  }, [frameFromClientX, onSelectionStart])

  const handleSelectionPointerMove = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    if (selectionAnchorFrame === null || selectionAnchorX === null) {
      return
    }

    if (Math.abs(event.clientX - selectionAnchorX) < 4) {
      return
    }

    updateSelectedRange(selectionAnchorFrame, frameFromClientX(event.clientX))
  }, [frameFromClientX, selectionAnchorFrame, selectionAnchorX, updateSelectedRange])

  const handleSelectionPointerUp = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    if (selectionAnchorFrame === null) {
      return
    }

    if ('hasPointerCapture' in event.currentTarget && event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId)
    }

    const pointerFrame = frameFromClientX(event.clientX)
    const pointerDistance = selectionAnchorX === null ? 0 : Math.abs(event.clientX - selectionAnchorX)

    if (pointerDistance < 4) {
      setCurrentFrame(pointerFrame)
    } else {
      const nextRange: [number, number] = [
        Math.min(selectionAnchorFrame, pointerFrame),
        Math.max(selectionAnchorFrame, pointerFrame),
      ]

      updateSelectedRange(nextRange[0], nextRange[1])
      onSelectionComplete?.(nextRange)
    }

    setSelectionAnchorFrame(null)
    setSelectionAnchorX(null)
  }, [frameFromClientX, onSelectionComplete, selectionAnchorFrame, selectionAnchorX, setCurrentFrame, updateSelectedRange])

  const handleSelectionContextMenu = useCallback((event: React.MouseEvent<HTMLDivElement>) => {
    if (!selectedRange || !selectionSurfaceRef.current) {
      return
    }

    const frame = frameFromClientX(event.clientX)

    if (frame < selectedRange[0] || frame > selectedRange[1]) {
      return
    }

    const bounds = selectionSurfaceRef.current.getBoundingClientRect()
    event.preventDefault()
    setContextMenuPosition({
      x: event.clientX - bounds.left,
      y: event.clientY - bounds.top,
    })
  }, [frameFromClientX, selectedRange])

  const selectionHighlight = useMemo(() => {
    if (!selectedRange || (currentEpisode?.meta.length ?? 0) <= 1) {
      return null
    }

    const [start, end] = selectedRange[0] <= selectedRange[1]
      ? selectedRange
      : [selectedRange[1], selectedRange[0]]
    const total = Math.max((currentEpisode?.meta.length ?? 1) - 1, 1)
    const left = (start / total) * 100
    const width = ((Math.max(end - start, 0) + 1) / (total + 1)) * 100

    return {
      left: `${left}%`,
      width: `${Math.max(width, 0.5)}%`,
    }
  }, [currentEpisode?.meta.length, selectedRange])

  // Handle chart click to seek - memoized callback
  const handleChartClick = useCallback((data: unknown) => {
    const chartData = data as { activePayload?: { payload?: { frame: number } }[] };
    if (chartData?.activePayload?.[0]?.payload?.frame !== undefined) {
      setCurrentFrame(chartData.activePayload[0].payload.frame);
    }
  }, [setCurrentFrame]);

  if (!currentEpisode) {
    return (
      <div
        className={cn(
          'flex items-center justify-center bg-muted rounded-lg',
          className
        )}
      >
        <p className="text-muted-foreground">No episode selected</p>
      </div>
    );
  }

  if (chartData.length === 0) {
    return (
      <div
        className={cn(
          'flex items-center justify-center bg-muted rounded-lg',
          className
        )}
      >
        <p className="text-muted-foreground">No trajectory data available</p>
      </div>
    );
  }

  return (
    <div className={cn('flex min-h-0 flex-col gap-2', className)}>
      {/* Controls */}
      <div className="flex items-start justify-between gap-3">
        <div
          data-testid="trajectory-joint-selector-scroll"
          className="flex-1 min-w-0 max-h-32 overflow-y-auto pr-2"
        >
          <JointSelector
            jointCount={jointCount}
            selectedJoints={selectedJoints}
            onSelectJoints={setSelectedJoints}
            colors={JOINT_COLORS}
            groups={jointConfig.groups}
            labels={jointConfig.labels}
            editable
            onEditJointLabel={withSave(updateLabel)}
            onEditGroupLabel={withSave(updateGroupLabel)}
            onCreateGroup={withSave(createGroup)}
            onDeleteGroup={withSave(deleteGroup)}
            onMoveJoint={withSave(moveJoint)}
            onOpenDefaults={() => setDefaultsOpen(true)}
          />
        </div>
        <div className="flex shrink-0 flex-wrap items-center justify-end gap-2 self-start">
          {selectedRange && (
            <Button
              type="button"
              size="sm"
              variant="outline"
              onClick={() => onSelectedRangeChange?.(null)}
            >
              Clear Selection
            </Button>
          )}
          <button
            onClick={() => setShowVelocity(false)}
            className={cn(
              'px-2 py-1 text-xs rounded',
              !showVelocity
                ? 'bg-primary text-primary-foreground'
                : 'bg-muted text-muted-foreground'
            )}
          >
            Position
          </button>
          <button
            onClick={() => setShowVelocity(true)}
            className={cn(
              'px-2 py-1 text-xs rounded',
              showVelocity
                ? 'bg-primary text-primary-foreground'
                : 'bg-muted text-muted-foreground'
            )}
          >
            Velocity
          </button>
          <button
            type="button"
            aria-pressed={showNormalized}
            aria-disabled={showVelocity}
            disabled={showVelocity}
            onClick={() => setShowNormalized((current) => !current)}
            className={cn(
              'px-2 py-1 text-xs rounded border transition-colors',
              showVelocity
                ? 'cursor-not-allowed border-transparent bg-muted text-muted-foreground/60'
                : showNormalized
                  ? 'border-primary bg-primary text-primary-foreground'
                  : 'border-transparent bg-muted text-muted-foreground hover:border-border'
            )}
          >
            Normalize
          </button>
        </div>
      </div>

      {/* Chart */}
      <div className="relative flex-1 min-h-0">
        <ResponsiveContainer
          width="100%"
          height="100%"
          minHeight={TRAJECTORY_CHART_MIN_HEIGHT}
          initialDimension={TRAJECTORY_CHART_INITIAL_DIMENSION}
        >
          <LineChart
            data={chartData}
            onClick={handleChartClick}
            margin={{ top: 5, right: 20, left: 0, bottom: 5 }}
          >
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
            <XAxis
              dataKey="frame"
              stroke="hsl(var(--muted-foreground))"
              fontSize={12}
            />
            <YAxis
              stroke="hsl(var(--muted-foreground))"
              fontSize={12}
              domain={showNormalized && !showVelocity ? [0, 1] : ['auto', 'auto']}
            />
            <Tooltip
              allowEscapeViewBox={{ x: true, y: true }}
              reverseDirection={{ x: false, y: true }}
              offset={{ x: 16, y: 12 }}
              isAnimationActive={false}
              contentStyle={{
                backgroundColor: 'hsl(var(--popover))',
                border: '1px solid hsl(var(--border))',
                borderRadius: '6px',
              }}
            />
            {/* Legend hidden — joint chips above serve as interactive legend */}

            {/* Trajectory adjustment markers - show orange lines on adjusted frames */}
            {Array.from(trajectoryAdjustments.keys()).map((frameIdx) => (
              <ReferenceLine
                key={`adj-${frameIdx}`}
                x={frameIdx}
                stroke="#f97316"
                strokeWidth={2}
                strokeOpacity={0.6}
              />
            ))}

            {/* Current frame marker - isolated component for performance */}
            <CurrentFrameMarker />

            {/* Joint lines */}
            {selectedJoints.map((jointIdx) => (
              <Line
                key={jointIdx}
                type="monotone"
                dataKey={`joint_${jointIdx}`}
                name={resolveLabel(jointIdx)}
                stroke={JOINT_COLORS[jointIdx % JOINT_COLORS.length]}
                dot={false}
                strokeWidth={1.5}
                isAnimationActive={false}
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
        <div
          ref={selectionSurfaceRef}
          data-testid="trajectory-selection-surface"
          data-keep-playback-selection="true"
          className="absolute inset-0 z-10 cursor-crosshair"
          onContextMenu={handleSelectionContextMenu}
          onPointerDown={handleSelectionPointerDown}
          onPointerMove={handleSelectionPointerMove}
          onPointerUp={handleSelectionPointerUp}
        >
          {selectionHighlight && (
            <div
              className="absolute bottom-2 top-2 rounded-md border border-primary/60 bg-primary/10"
              style={selectionHighlight}
            />
          )}
          {contextMenuPosition && selectedRange && (
            <div
              ref={contextMenuRef}
              data-keep-playback-selection="true"
              className="absolute z-20 rounded-md border bg-popover p-1 shadow-md"
              style={{ left: contextMenuPosition.x, top: contextMenuPosition.y }}
              onContextMenu={(event) => event.preventDefault()}
              onPointerDown={(event) => event.stopPropagation()}
              onPointerUp={(event) => event.stopPropagation()}
            >
              <Button
                type="button"
                size="sm"
                variant="ghost"
                onClick={(event) => {
                  event.stopPropagation()
                  onCreateSubtaskFromRange?.(selectedRange)
                  setContextMenuPosition(null)
                }}
              >
                Create Subtask
              </Button>
            </div>
          )}
        </div>
      </div>

      <JointConfigDefaultsEditor
        open={defaultsOpen}
        onOpenChange={setDefaultsOpen}
        groups={defaults?.groups ?? jointConfig.groups}
        labels={defaults?.labels ?? jointConfig.labels}
        onSave={(config) => {
          saveDefaults.mutate(
            { datasetId: '_defaults', ...config },
            {
              onSuccess: () => {
                setDefaultsOpen(false)
                onSaved?.()
              },
            },
          )
        }}
        isSaving={saveDefaults.isPending}
      />
    </div>
  );
});
