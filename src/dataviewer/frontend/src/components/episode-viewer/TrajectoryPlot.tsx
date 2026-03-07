/**
 * Trajectory visualization component showing joint positions over time.
 *
 * Performance optimizations:
 * - CurrentFrameMarker is isolated to prevent full chart re-renders on frame changes
 * - Chart data is memoized based on trajectory data and velocity toggle
 * - Reference line position updates without re-rendering chart lines
 */

import { memo, useCallback, useEffect, useMemo, useState } from 'react';
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
export const TrajectoryPlot = memo(function TrajectoryPlot({ className, onSaved }: TrajectoryPlotProps) {
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
      <div className="flex-1 min-h-0">
        <ResponsiveContainer width="100%" height="100%">
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
