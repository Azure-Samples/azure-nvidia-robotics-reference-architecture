import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

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
})
