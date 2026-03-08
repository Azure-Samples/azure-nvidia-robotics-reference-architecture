import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { AnnotationWorkspace } from '@/components/annotation-workspace/AnnotationWorkspace'

let mockEpisodeLabels: Record<number, string[]> = { 0: ['SUCCESS'] }
let mockSavedEpisodeLabels: Record<number, string[]> = { 0: ['SUCCESS'] }
let mockAvailableLabels = ['SUCCESS', 'FAILURE', 'PARTIAL']
let mockLabelsLoaded = true
let mockEpisodeIndex = 0
let mockHasEdits = false
const mockInitializeEdit = vi.fn()
const mockResetEdits = vi.fn()
const mockSaveEpisodeDraft = vi.fn()
const mockSetCurrentFrame = vi.fn()
const mockTogglePlayback = vi.fn()
const mockSetPlaybackSpeed = vi.fn()
const mockSetAutoPlay = vi.fn()
const mockSetAutoLoop = vi.fn()
const mockSaveEpisodeLabels = vi.fn()

vi.mock('@/components/annotation-panel', () => ({
  LabelPanel: () => (
    <button
      type="button"
      onClick={() => {
        mockEpisodeLabels = { 0: ['FAILURE'] }
      }}
    >
      Toggle Label Draft
    </button>
  ),
}))

vi.mock('@/components/episode-viewer', () => ({
  TrajectoryPlot: () => <div>Trajectory Plot</div>,
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
      savedEpisodeLabels: mockSavedEpisodeLabels,
      setEpisodeLabels: (episodeIndex: number, labels: string[]) => {
        mockEpisodeLabels = { ...mockEpisodeLabels, [episodeIndex]: labels }
      },
      commitEpisodeLabels: (episodeIndex: number, labels?: string[]) => {
        const nextLabels = labels ?? mockEpisodeLabels[episodeIndex] ?? []
        mockEpisodeLabels = { ...mockEpisodeLabels, [episodeIndex]: nextLabels }
        mockSavedEpisodeLabels = { ...mockSavedEpisodeLabels, [episodeIndex]: nextLabels }
      },
    }),
}))

vi.mock('@/stores', () => ({
  useDatasetStore: (selector: (state: unknown) => unknown) =>
    selector({
      currentDataset: { id: 'dataset-1', fps: 30 },
    }),
  useEditDirtyState: () => ({
    isDirty: mockHasEdits,
    resetEdits: mockResetEdits,
  }),
  useEditStore: (selector: (state: unknown) => unknown) =>
    selector({
      removedFrames: new Set<number>(),
      initializeEdit: mockInitializeEdit,
      clearTransforms: vi.fn(),
      saveEpisodeDraft: mockSaveEpisodeDraft,
      datasetId: null,
      episodeIndex: null,
      globalTransform: null,
    }),
  useEpisodeStore: (selector: (state: unknown) => unknown) =>
    selector({
      currentEpisode: {
        meta: { index: mockEpisodeIndex, length: 12 },
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
    mockSavedEpisodeLabels = { 0: ['SUCCESS'] }
    mockAvailableLabels = ['SUCCESS', 'FAILURE', 'PARTIAL']
    mockLabelsLoaded = true
    mockEpisodeIndex = 0
    mockHasEdits = false
    mockSaveEpisodeLabels.mockReset()
    mockSaveEpisodeLabels.mockImplementation(async ({ episodeIdx, labels }: { episodeIdx: number; labels: string[] }) => {
      mockEpisodeLabels = { ...mockEpisodeLabels, [episodeIdx]: labels }
      mockSavedEpisodeLabels = { ...mockSavedEpisodeLabels, [episodeIdx]: labels }
      return undefined
    })
    mockSaveEpisodeDraft.mockReset()
    mockSaveEpisodeDraft.mockImplementation(() => {
      mockHasEdits = false
    })
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

  it('shows pending episode changes instead of auto-save copy after labels change locally', () => {
    const { rerender } = render(<AnnotationWorkspace />)

    fireEvent.click(screen.getByRole('button', { name: /toggle label draft/i }))
    rerender(<AnnotationWorkspace />)

    const actions = screen.getByTestId('workspace-header-actions')
    expect(within(actions).getByText(/unsaved episode changes/i)).toBeInTheDocument()
    expect(screen.queryByText(/changes save automatically/i)).not.toBeInTheDocument()
    expect(mockSaveEpisodeLabels).not.toHaveBeenCalled()
  })

  it('shows a saved message after Save & Next Episode and hides it after a short delay', async () => {
    const handleSaveAndNextEpisode = vi.fn()
    const { rerender } = render(
      <AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />,
    )

    mockEpisodeLabels = { 0: ['FAILURE'] }
    rerender(<AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />)

    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /save\s*&\s*next episode/i }))
      await Promise.resolve()
    })

    expect(screen.getByText(/episode changes saved/i)).toBeInTheDocument()

    act(() => {
      vi.advanceTimersByTime(2500)
    })

    expect(screen.queryByText(/episode changes saved/i)).not.toBeInTheDocument()
  })

  it('does not show stale unsaved episode changes after Save & Next Episode advances to the next episode', async () => {
    const handleSaveAndNextEpisode = vi.fn(() => {
      mockEpisodeIndex = 1
      mockEpisodeLabels = {
        ...mockEpisodeLabels,
        1: [],
      }
      mockSavedEpisodeLabels = {
        ...mockSavedEpisodeLabels,
        1: [],
      }
    })
    const { rerender } = render(
      <AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />,
    )

    mockEpisodeLabels = { 0: ['FAILURE'], 1: [] }
    mockSavedEpisodeLabels = { 0: ['SUCCESS'], 1: [] }
    rerender(<AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />)

    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /save\s*&\s*next episode/i }))
      await Promise.resolve()
    })

    rerender(<AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />)

    expect(screen.queryByText(/unsaved episode changes/i)).not.toBeInTheDocument()
  })

  it('uses the save-status slot as the only pending-change indicator', () => {
    mockHasEdits = true

    render(<AnnotationWorkspace />)

    expect(screen.queryByText(/\(has edits\)/i)).not.toBeInTheDocument()
    expect(screen.getByText(/unsaved episode changes/i)).toBeInTheDocument()
  })

  it('reserves header space so the save status does not shift other controls', () => {
    render(<AnnotationWorkspace />)

    expect(screen.getByTestId('workspace-save-status-slot')).toBeInTheDocument()
  })

  it('keeps the episode title, tabs, and top actions in a single compact toolbar', () => {
    render(<AnnotationWorkspace />)

    const topBar = screen.getByTestId('workspace-top-bar')

    expect(topBar).toContainElement(screen.getByRole('tablist'))
    expect(topBar).toContainElement(screen.getByTestId('workspace-header-actions'))
    expect(topBar.className).toContain('items-center')
    expect(topBar.className).toContain('justify-between')
    expect(topBar.className).not.toContain('flex-wrap')
  })

  it('adds a dedicated trajectory viewer tab alongside the existing workspace tabs', () => {
    render(<AnnotationWorkspace />)

    expect(screen.getByRole('tab', { name: /episode viewer/i })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: /trajectory viewer/i })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: /object detection/i })).toBeInTheDocument()
  })

  it('keeps the trajectory plot out of the default episode viewer tab', () => {
    render(<AnnotationWorkspace />)

    expect(screen.queryByText('Trajectory Plot')).not.toBeInTheDocument()
  })

  it('keeps subtask controls out of the default episode viewer tab', () => {
    render(<AnnotationWorkspace />)

    expect(screen.queryByText('Subtask Toolbar')).not.toBeInTheDocument()
    expect(screen.queryByText('Subtask Timeline Track')).not.toBeInTheDocument()
  })

  it('renders the trajectory plot after switching to the trajectory viewer tab', () => {
    render(<AnnotationWorkspace />)

    const trajectoryTab = screen.getByRole('tab', { name: /trajectory viewer/i })

    fireEvent.mouseDown(trajectoryTab, { button: 0, ctrlKey: false })

    expect(screen.getByText('Trajectory Plot')).toBeInTheDocument()
  })

  it('renders subtask controls alongside the trajectory graph in the trajectory viewer tab', () => {
    render(<AnnotationWorkspace />)

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })

    expect(screen.getByText('Subtask Toolbar')).toBeInTheDocument()
    expect(screen.getByText('Subtask Timeline Track')).toBeInTheDocument()
  })

  it('uses compact playback controls in the trajectory viewer tab', () => {
    render(<AnnotationWorkspace />)

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })

    expect(screen.getByRole('button', { name: /play playback/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /toggle auto-play/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /toggle loop playback/i })).toBeInTheDocument()
    expect(screen.queryByText(/^Speed:$/)).not.toBeInTheDocument()
  })

  it('renders a Previous Episode action in the workspace header when navigation is available', () => {
    const handlePreviousEpisode = vi.fn()

    render(<AnnotationWorkspace canGoPreviousEpisode onPreviousEpisode={handlePreviousEpisode} />)

    const previousEpisodeButton = screen.getByRole('button', { name: /previous episode/i })

    expect(previousEpisodeButton).toBeEnabled()

    fireEvent.click(previousEpisodeButton)

    expect(handlePreviousEpisode).toHaveBeenCalledTimes(1)
  })

  it('renders a Save & Next Episode action in the workspace header when navigation is available', async () => {
    const handleSaveAndNextEpisode = vi.fn()

    render(<AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />)

    const saveAndNextButton = within(screen.getByTestId('workspace-header-actions')).getByRole('button', {
      name: /save\s*&\s*next episode/i,
    })

    expect(saveAndNextButton).toBeEnabled()

    await act(async () => {
      fireEvent.click(saveAndNextButton)
      await Promise.resolve()
    })

    expect(handleSaveAndNextEpisode).toHaveBeenCalledTimes(1)
  })

  it('saves labels and advances when Save & Next Episode is clicked', async () => {
    const handleSaveAndNextEpisode = vi.fn()
    const { rerender } = render(
      <AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />,
    )

    mockEpisodeLabels = { 0: ['FAILURE'] }
    rerender(<AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />)

    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /save\s*&\s*next episode/i }))
      await Promise.resolve()
    })

    expect(mockSaveEpisodeLabels).toHaveBeenCalledWith({
      episodeIdx: 0,
      labels: ['FAILURE'],
    })
    expect(handleSaveAndNextEpisode).toHaveBeenCalledTimes(1)
  })

  it('resets labels back to the original episode labels without saving when Reset All is clicked', async () => {
    const { rerender } = render(<AnnotationWorkspace />)

    mockEpisodeLabels = { 0: ['FAILURE'] }
    rerender(<AnnotationWorkspace />)

    await act(async () => {
      fireEvent.click(
        within(screen.getByTestId('workspace-header-actions')).getByRole('button', { name: /^reset all$/i }),
      )
      await Promise.resolve()
    })

    rerender(<AnnotationWorkspace />)

    expect(mockResetEdits).toHaveBeenCalled()
    expect(mockSaveEpisodeLabels).not.toHaveBeenCalled()
    expect(screen.queryByText(/unsaved episode changes/i)).not.toBeInTheDocument()
  })
})
