import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { AnnotationWorkspace } from '@/components/annotation-workspace/AnnotationWorkspace'

let mockEpisodeLabels = { 0: ['SUCCESS'] }
let mockAvailableLabels = ['SUCCESS', 'FAILURE', 'PARTIAL']
let mockLabelsLoaded = true
const mockInitializeEdit = vi.fn()
const mockResetEdits = vi.fn()
const mockSetCurrentFrame = vi.fn()
const mockTogglePlayback = vi.fn()
const mockSetPlaybackSpeed = vi.fn()
const mockSetAutoPlay = vi.fn()
const mockSetAutoLoop = vi.fn()
const mockSaveEpisodeLabels = vi.fn()

vi.mock('@/components/annotation-panel', () => ({
  LabelPanel: ({ onSaved }: { onSaved?: () => void }) => (
    <button
      type="button"
      onClick={() => {
        mockEpisodeLabels = { 0: ['FAILURE'] }
        onSaved?.()
      }}
    >
      Trigger Label Save
    </button>
  ),
}))

vi.mock('@/components/episode-viewer', () => ({
  TrajectoryPlot: ({ onSaved }: { onSaved?: () => void }) => (
    <button type="button" onClick={onSaved}>
      Trigger Trajectory Save
    </button>
  ),
}))

vi.mock('@/components/export', () => ({
  ExportDialog: () => null,
}))

vi.mock('@/components/frame-editor', () => ({
  ColorAdjustmentControls: () => <div>Color Adjustment Controls</div>,
  FrameInsertionToolbar: () => <div>Frame Insertion Toolbar</div>,
  FrameRemovalToolbar: () => <div>Frame Removal Toolbar</div>,
  TrajectoryEditor: () => <div>Trajectory Editor</div>,
  TransformControls: () => <div>Transform Controls</div>,
}))

vi.mock('@/components/object-detection', () => ({
  DetectionPanel: () => <div>Detection Panel</div>,
}))

vi.mock('@/components/playback/PlaybackControlStrip', () => ({
  PlaybackControlStrip: ({ controls }: { controls?: JSX.Element | null }) => (
    <div>
      <div>Playback Control Strip</div>
      {controls}
    </div>
  ),
}))

vi.mock('@/components/subtask-timeline', () => ({
  SubtaskTimelineTrack: () => <div>Subtask Timeline Track</div>,
  SubtaskToolbar: () => <div>Subtask Toolbar</div>,
}))

vi.mock('@/components/viewer-display', () => ({
  ViewerDisplayControls: () => <div>Viewer Display Controls</div>,
}))

vi.mock('@/lib/css-filters', () => ({
  combineCssFilters: () => '',
}))

vi.mock('@/lib/playback-utils', () => ({
  computeEffectiveFps: () => 30,
  computeSyncAction: () => ({ kind: 'pause' }),
}))

vi.mock('@/hooks/use-labels', () => ({
  useSaveEpisodeLabels: () => ({
    mutateAsync: mockSaveEpisodeLabels,
    isPending: false,
  }),
}))

vi.mock('@/stores/label-store', () => ({
  useLabelStore: (selector: (state: unknown) => unknown) =>
    selector({
      isLoaded: mockLabelsLoaded,
      availableLabels: mockAvailableLabels,
      episodeLabels: mockEpisodeLabels,
    }),
}))

vi.mock('@/stores', () => ({
  useDatasetStore: (selector: (state: unknown) => unknown) =>
    selector({
      currentDataset: { id: 'dataset-1', fps: 30 },
    }),
  useEditDirtyState: () => ({
    isDirty: false,
    resetEdits: mockResetEdits,
  }),
  useEditStore: (selector: (state: unknown) => unknown) =>
    selector({
      removedFrames: new Set<number>(),
      initializeEdit: mockInitializeEdit,
      clearTransforms: vi.fn(),
      datasetId: null,
      episodeIndex: null,
      globalTransform: null,
    }),
  useEpisodeStore: (selector: (state: unknown) => unknown) =>
    selector({
      currentEpisode: {
        meta: { index: 0, length: 12 },
        videoUrls: undefined,
        trajectoryData: undefined,
      },
    }),
  usePlaybackControls: () => ({
    currentFrame: 0,
    isPlaying: false,
    playbackSpeed: 1,
    setCurrentFrame: mockSetCurrentFrame,
    togglePlayback: mockTogglePlayback,
    setPlaybackSpeed: mockSetPlaybackSpeed,
  }),
  usePlaybackSettings: () => ({
    autoPlay: false,
    autoLoop: false,
    setAutoPlay: mockSetAutoPlay,
    setAutoLoop: mockSetAutoLoop,
  }),
  useViewerDisplay: () => ({
    displayAdjustment: null,
    isActive: false,
  }),
}))

vi.mock('@/stores/edit-store', () => ({
  getEffectiveFrameCount: () => 12,
  getOriginalIndex: () => 0,
  useFrameInsertionState: () => ({ insertedFrames: new Map<number, { interpolationFactor?: number }>() }),
}))

describe('AnnotationWorkspace save status', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    mockEpisodeLabels = { 0: ['SUCCESS'] }
    mockAvailableLabels = ['SUCCESS', 'FAILURE', 'PARTIAL']
    mockLabelsLoaded = true
    mockSaveEpisodeLabels.mockReset()
    mockSaveEpisodeLabels.mockResolvedValue(undefined)
    mockResetEdits.mockReset()
  })

  afterEach(() => {
    cleanup()
    vi.runOnlyPendingTimers()
    vi.useRealTimers()
  })

  it('keeps the save status hidden until a save occurs', () => {
    render(<AnnotationWorkspace />)

    expect(screen.queryByText(/changes save automatically/i)).not.toBeInTheDocument()
  })

  it('shows the save status beneath the Reset All and Export actions after a label save', async () => {
    render(<AnnotationWorkspace />)

    fireEvent.click(screen.getByRole('button', { name: /trigger label save/i }))

    const actions = screen.getByTestId('workspace-header-actions')
    expect(within(actions).getByRole('button', { name: /reset all/i })).toBeInTheDocument()
    expect(within(actions).getByRole('button', { name: /export/i })).toBeInTheDocument()
    expect(within(actions).getByText(/changes save automatically/i)).toBeInTheDocument()
  })

  it('shows the save status for other saves and hides it after a short delay', async () => {
    render(<AnnotationWorkspace />)

    fireEvent.click(screen.getByRole('button', { name: /trigger trajectory save/i }))

    expect(screen.getByText(/changes save automatically/i)).toBeInTheDocument()

    act(() => {
      vi.advanceTimersByTime(2500)
    })

    expect(screen.queryByText(/changes save automatically/i)).not.toBeInTheDocument()
  })

  it('reserves header space so the save status does not shift other controls', () => {
    render(<AnnotationWorkspace />)

    expect(screen.getByTestId('workspace-save-status-slot')).toBeInTheDocument()
  })

  it('resets labels back to the original episode labels when Reset All is clicked', async () => {
    const { rerender } = render(<AnnotationWorkspace />)

    mockEpisodeLabels = { 0: ['FAILURE'] }
    rerender(<AnnotationWorkspace />)

    await act(async () => {
      fireEvent.click(
        within(screen.getByTestId('workspace-header-actions')).getByRole('button', { name: /^reset all$/i }),
      )
      await Promise.resolve()
    })

    expect(mockResetEdits).toHaveBeenCalled()
    expect(mockSaveEpisodeLabels).toHaveBeenCalledWith({
      episodeIdx: 0,
      labels: ['SUCCESS'],
    })
  })
})
