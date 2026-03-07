import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="responsive-container">{children}</div>
  ),
  LineChart: ({ children, data }: { children: React.ReactNode; data: unknown }) => (
    <div data-testid="line-chart">
      <pre data-testid="line-chart-data">{JSON.stringify(data)}</pre>
      {children}
    </div>
  ),
  CartesianGrid: () => null,
  Line: ({ dataKey }: { dataKey: string }) => <div data-testid={`line-${dataKey}`} />,
  ReferenceLine: () => null,
  Tooltip: () => null,
  XAxis: () => null,
  YAxis: () => null,
}))

import { TrajectoryPlot } from '@/components/episode-viewer/TrajectoryPlot'
import { useEditStore, useEpisodeStore } from '@/stores'
import { useJointConfigStore } from '@/stores/joint-config-store'

vi.mock('@/hooks/use-joint-config', () => ({
  useJointConfigDefaults: () => ({ data: undefined }),
  useSaveJointConfig: () => ({ save: vi.fn() }),
  useSaveJointConfigDefaults: () => ({ mutate: vi.fn(), isPending: false }),
}))

beforeAll(() => {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver
})

afterEach(cleanup)

beforeEach(() => {
  useEpisodeStore.getState().reset()
  useEditStore.getState().clear()
  useJointConfigStore.getState().reset()

  useEpisodeStore.getState().setCurrentEpisode({
    meta: { index: 0, length: 3, taskIndex: 0, hasAnnotations: false },
    videoUrls: {},
    trajectoryData: [
      {
        frame: 0,
        timestamp: 0,
        jointPositions: Array.from({ length: 17 }, (_, index) => index),
        jointVelocities: Array.from({ length: 17 }, (_, index) => index / 10),
        endEffectorPose: [],
        gripperState: 0,
      },
      {
        frame: 1,
        timestamp: 0.1,
        jointPositions: Array.from({ length: 17 }, (_, index) => index + 1),
        jointVelocities: Array.from({ length: 17 }, (_, index) => (index + 1) / 10),
        endEffectorPose: [],
        gripperState: 1,
      },
    ],
  })
})

describe('TrajectoryPlot', () => {
  it('auto-selects the most significant joint groups for the episode telemetry', () => {
    useEpisodeStore.getState().setCurrentEpisode({
      meta: { index: 0, length: 4, taskIndex: 0, hasAnnotations: false },
      videoUrls: {},
      trajectoryData: [
        {
          frame: 0,
          timestamp: 0,
          jointPositions: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0],
          jointVelocities: Array.from({ length: 17 }, () => 0),
          endEffectorPose: [],
          gripperState: 0,
        },
        {
          frame: 1,
          timestamp: 0.1,
          jointPositions: [0, 0, 0, 0, 0, 0, 0, 0, 0.8, 1.2, 0.9, 0.2, 0.4, 0.3, 0.8, 0.6, 0],
          jointVelocities: Array.from({ length: 17 }, () => 0),
          endEffectorPose: [],
          gripperState: 0.6,
        },
        {
          frame: 2,
          timestamp: 0.2,
          jointPositions: [0, 0, 0, 0, 0, 0, 0, 0, 1.4, 2.1, 1.5, 0.5, 0.9, 0.7, 0.1, 1, 0],
          jointVelocities: Array.from({ length: 17 }, () => 0),
          endEffectorPose: [],
          gripperState: 1,
        },
        {
          frame: 3,
          timestamp: 0.3,
          jointPositions: [0, 0, 0, 0, 0, 0, 0, 0, 1.8, 2.8, 2.2, 0.9, 1.2, 1.1, -0.4, 0.2, 0],
          jointVelocities: Array.from({ length: 17 }, () => 0),
          endEffectorPose: [],
          gripperState: 0.2,
        },
      ],
    })

    render(
      <div style={{ width: 600, height: 300 }}>
        <TrajectoryPlot className="h-full" />
      </div>,
    )

    expect(screen.getByTestId('line-joint_8')).toBeInTheDocument()
    expect(screen.getByTestId('line-joint_11')).toBeInTheDocument()
    expect(screen.getByTestId('line-joint_15')).toBeInTheDocument()
    expect(screen.queryByTestId('line-joint_0')).not.toBeInTheDocument()
    expect(screen.queryByTestId('line-joint_7')).not.toBeInTheDocument()
  })

  it('renders the joint selector inside a dedicated scroll region', () => {
    render(
      <div style={{ width: 600, height: 300 }}>
        <TrajectoryPlot className="h-full" />
      </div>,
    )

    const scrollRegion = screen.getByTestId('trajectory-joint-selector-scroll')

    expect(scrollRegion).toBeInTheDocument()
    expect(scrollRegion).toHaveClass('overflow-y-auto')
    expect(scrollRegion).toHaveClass('max-h-32')
    expect(screen.getByRole('button', { name: 'Position' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Velocity' })).toBeInTheDocument()
  })

  it('defaults normalization on and lets the chart switch back to raw position values', () => {
    render(
      <div style={{ width: 600, height: 300 }}>
        <TrajectoryPlot className="h-full" />
      </div>,
    )

    const normalizeButton = screen.getByRole('button', { name: 'Normalize' })

    expect(normalizeButton).toHaveAttribute('aria-pressed', 'true')

    const normalizedData = JSON.parse(screen.getByTestId('line-chart-data').textContent ?? '[]') as Array<Record<string, number>>

    expect(normalizedData[0]?.joint_0).toBe(0)
    expect(normalizedData[0]?.joint_1).toBe(0)
    expect(normalizedData[1]?.joint_0).toBe(1)
    expect(normalizedData[1]?.joint_1).toBe(1)

    fireEvent.click(normalizeButton)

    const rawData = JSON.parse(screen.getByTestId('line-chart-data').textContent ?? '[]') as Array<Record<string, number>>

    expect(rawData[0]?.joint_0).toBe(0)
    expect(rawData[0]?.joint_1).toBe(1)
    expect(rawData[1]?.joint_0).toBe(1)
    expect(rawData[1]?.joint_1).toBe(2)
  })

  it('keeps velocity mode raw and disables the normalize control while active', () => {
    render(
      <div style={{ width: 600, height: 300 }}>
        <TrajectoryPlot className="h-full" />
      </div>,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Velocity' }))

    const normalizeButton = screen.getByRole('button', { name: 'Normalize' })
    const velocityData = JSON.parse(screen.getByTestId('line-chart-data').textContent ?? '[]') as Array<Record<string, number>>

    expect(normalizeButton).toBeDisabled()
    expect(normalizeButton).toHaveAttribute('aria-disabled', 'true')
    expect(velocityData[0]?.joint_0).toBe(0)
    expect(velocityData[0]?.joint_1).toBe(0.1)
    expect(velocityData[1]?.joint_0).toBe(0.1)
    expect(velocityData[1]?.joint_1).toBe(0.2)
  })
})
