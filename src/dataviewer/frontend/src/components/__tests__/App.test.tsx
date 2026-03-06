import { cleanup, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { AppContent } from '@/App'
import { useDatasetStore, useEpisodeStore } from '@/stores'
import { useLabelStore } from '@/stores/label-store'
import type { DatasetInfo } from '@/types'

let mockDatasets: DatasetInfo[] = []

vi.mock('@/hooks/use-datasets', () => ({
  useDatasets: () => ({ data: mockDatasets }),
  useCapabilities: () => ({ data: undefined }),
  useEpisodes: () => ({ data: [], isLoading: false, error: null }),
  useEpisode: () => ({ data: null, isLoading: false, error: null }),
}))

vi.mock('@/hooks/use-joint-config', () => ({
  useJointConfig: () => undefined,
}))

vi.mock('@/hooks/use-labels', () => ({
  useDatasetLabels: () => undefined,
}))

vi.mock('@/components/annotation-panel', () => ({
  LabelFilter: () => <div>Label Filter</div>,
}))

vi.mock('@/components/annotation-workspace/AnnotationWorkspace', () => ({
  AnnotationWorkspace: () => <div>Annotation Workspace</div>,
}))

describe('AppContent', () => {
  beforeEach(() => {
    mockDatasets = [
      {
        id: 'houston_lerobot_fixed',
        name: 'houston_lerobot_fixed (ur10e)',
        totalEpisodes: 100,
        fps: 30,
        features: {},
        tasks: [],
      },
      {
        id: 'hexagon_lerobot',
        name: 'hexagon_lerobot (hexagarm)',
        totalEpisodes: 64,
        fps: 30,
        features: {},
        tasks: [],
      },
    ]
    useDatasetStore.getState().reset()
    useEpisodeStore.getState().reset()
    useLabelStore.getState().reset()
  })

  afterEach(cleanup)

  it('switches away from a removed selected dataset when the dataset list refreshes', async () => {
    const { rerender } = render(<AppContent />)

    await waitFor(() => {
      expect(screen.getByRole('combobox')).toHaveValue('houston_lerobot_fixed')
    })

    mockDatasets = [
      {
        id: 'hexagon_lerobot',
        name: 'hexagon_lerobot (hexagarm)',
        totalEpisodes: 64,
        fps: 30,
        features: {},
        tasks: [],
      },
    ]

    rerender(<AppContent />)

    await waitFor(() => {
      expect(screen.getByDisplayValue('hexagon_lerobot')).toBeInTheDocument()
    })
  })
})
