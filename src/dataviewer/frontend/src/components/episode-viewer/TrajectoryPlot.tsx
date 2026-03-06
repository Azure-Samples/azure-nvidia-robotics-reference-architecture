/**
 * Trajectory visualization component showing joint positions over time.
 *
 * Performance optimizations:
 * - CurrentFrameMarker is isolated to prevent full chart re-renders on frame changes
 * - Chart data is memoized based on trajectory data and velocity toggle
 * - Reference line position updates without re-rendering chart lines
 */

import { memo, useCallback,useMemo, useState } from 'react';
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

import { useSaveJointConfig } from '@/hooks/use-joint-config'
import { cn } from '@/lib/utils'
import { useEpisodeStore } from '@/stores'
import { useTrajectoryAdjustmentState } from '@/stores/edit-store'
import { useJointConfigStore } from '@/stores/joint-config-store'

import { getJointLabel, JOINT_COLORS } from './joint-constants'
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
export const TrajectoryPlot = memo(function TrajectoryPlot({ className }: TrajectoryPlotProps) {
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

  const [selectedJoints, setSelectedJoints] = useState<number[]>([0, 1, 2]);
  const [showVelocity, setShowVelocity] = useState(false);

  const withSave = useCallback(
    <T extends unknown[]>(fn: (...args: T) => void) =>
      (...args: T) => {
        fn(...args)
        // Defer save to allow store update to complete
        queueMicrotask(saveJointConfig)
      },
    [saveJointConfig],
  );

  const resolveLabel = useCallback(
    (idx: number) => jointConfig.labels[String(idx)] ?? getJointLabel(idx),
    [jointConfig.labels],
  );

  // Transform trajectory data for Recharts - memoized
  // Apply trajectory adjustments to show modified values
  const chartData = useMemo(() => {
    if (!currentEpisode?.trajectoryData) return [];

    return currentEpisode.trajectoryData.map((point) => {
      const adjustment = trajectoryAdjustments.get(point.frame);
      const data: Record<string, number | boolean> = {
        frame: point.frame,
        timestamp: point.timestamp,
        hasAdjustment: !!adjustment,
      };

      // Add selected joint data with adjustments applied
      if (showVelocity) {
        point.jointVelocities.forEach((vel, idx) => {
          data[`joint_${idx}`] = vel;
        });
      } else {
        point.jointPositions.forEach((pos, idx) => {
          let adjusted = pos;
          if (adjustment) {
            // Apply right arm delta (indices 0, 1, 2)
            if (adjustment.rightArmDelta && idx >= 0 && idx <= 2) {
              adjusted += adjustment.rightArmDelta[idx];
            }
            // Apply left arm delta (indices 8, 9, 10)
            if (adjustment.leftArmDelta && idx >= 8 && idx <= 10) {
              adjusted += adjustment.leftArmDelta[idx - 8];
            }
            // Apply gripper overrides
            if (idx === 7 && adjustment.rightGripperOverride !== undefined) {
              adjusted = adjustment.rightGripperOverride;
            }
            if (idx === 15 && adjustment.leftGripperOverride !== undefined) {
              adjusted = adjustment.leftGripperOverride;
            }
          }
          data[`joint_${idx}`] = adjusted;
        });
      }

      return data;
    });
  }, [currentEpisode?.trajectoryData, showVelocity, trajectoryAdjustments]);

  // Get joint count - memoized
  const jointCount = useMemo(() => {
    if (!currentEpisode?.trajectoryData?.[0]) return 0;
    return currentEpisode.trajectoryData[0].jointPositions.length;
  }, [currentEpisode?.trajectoryData]);

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
    <div className={cn('flex flex-col gap-2', className)}>
      {/* Controls */}
      <div className="flex items-center justify-between">
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
        />
        <div className="flex items-center gap-2">
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
            <YAxis stroke="hsl(var(--muted-foreground))" fontSize={12} />
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
    </div>
  );
});
