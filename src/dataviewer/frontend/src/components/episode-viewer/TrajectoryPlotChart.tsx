import type React from 'react'
import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

import { JOINT_COLORS } from './joint-constants'
import { TrajectoryPlotSelectionOverlay } from './TrajectoryPlotSelectionOverlay'

const TRAJECTORY_CHART_MIN_HEIGHT = 60
const TRAJECTORY_CHART_INITIAL_DIMENSION = { width: 320, height: TRAJECTORY_CHART_MIN_HEIGHT }

interface TrajectoryPlotChartProps {
  chartData: Array<Record<string, number | boolean>>
  currentFrame: number
  selectedJoints: number[]
  resolveLabel: (index: number) => string
  trajectoryAdjustments: Map<number, unknown>
  showVelocity: boolean
  showNormalized: boolean
  selectedRange: [number, number] | null
  selectionHighlight: { left: string; width: string } | null
  contextMenuPosition: { x: number; y: number } | null
  onChartClick: (data: unknown) => void
  onSelectionContextMenu: (event: React.MouseEvent<HTMLDivElement>) => void
  onSelectionPointerDown: (event: React.PointerEvent<HTMLDivElement>) => void
  onSelectionPointerMove: (event: React.PointerEvent<HTMLDivElement>) => void
  onSelectionPointerUp: (event: React.PointerEvent<HTMLDivElement>) => void
  onCreateSubtaskFromRange?: (range: [number, number]) => void
  onDismissContextMenu: () => void
  selectionSurfaceRef: React.RefObject<HTMLDivElement>
}

export function TrajectoryPlotChart({
  chartData,
  currentFrame,
  selectedJoints,
  resolveLabel,
  trajectoryAdjustments,
  showVelocity,
  showNormalized,
  selectedRange,
  selectionHighlight,
  contextMenuPosition,
  onChartClick,
  onSelectionContextMenu,
  onSelectionPointerDown,
  onSelectionPointerMove,
  onSelectionPointerUp,
  onCreateSubtaskFromRange,
  onDismissContextMenu,
  selectionSurfaceRef,
}: TrajectoryPlotChartProps) {
  return (
    <div className="relative flex-1 min-h-0">
      <ResponsiveContainer
        width="100%"
        height="100%"
        minHeight={TRAJECTORY_CHART_MIN_HEIGHT}
        initialDimension={TRAJECTORY_CHART_INITIAL_DIMENSION}
      >
        <LineChart
          data={chartData}
          onClick={onChartClick}
          margin={{ top: 5, right: 20, left: 0, bottom: 5 }}
        >
          <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
          <XAxis dataKey="frame" stroke="hsl(var(--muted-foreground))" fontSize={12} />
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

          {Array.from(trajectoryAdjustments.keys()).map((frameIdx) => (
            <ReferenceLine
              key={`adj-${frameIdx}`}
              x={frameIdx}
              stroke="#f97316"
              strokeWidth={2}
              strokeOpacity={0.6}
            />
          ))}

          <ReferenceLine
            x={currentFrame}
            stroke="hsl(var(--primary))"
            strokeWidth={2}
            strokeDasharray="4 4"
          />

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
      <TrajectoryPlotSelectionOverlay
        selectedRange={selectedRange}
        selectionHighlight={selectionHighlight}
        contextMenuPosition={contextMenuPosition}
        onSelectionContextMenu={onSelectionContextMenu}
        onSelectionPointerDown={onSelectionPointerDown}
        onSelectionPointerMove={onSelectionPointerMove}
        onSelectionPointerUp={onSelectionPointerUp}
        onCreateSubtaskFromRange={onCreateSubtaskFromRange}
        onDismissContextMenu={onDismissContextMenu}
        selectionSurfaceRef={selectionSurfaceRef}
      />
    </div>
  )
}
