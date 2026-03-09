import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { AnnotationWorkspace } from '@/components/annotation-workspace/AnnotationWorkspace'

const { mockComputeSyncAction } = vi.hoisted(() => ({
  mockComputeSyncAction: vi.fn<() => { kind: string; playbackRate?: number }>(() => ({ kind: 'pause' })),
}))

const {
  mockDiagnosticsState,
  mockClearDiagnosticEvents,
  mockDisableDiagnostics,
  mockEnableDiagnostics,
  mockRecordDiagnosticEvent,
} = vi.hoisted(() => {
  const state = {
    enabled: false,
    channels: [] as string[],
    events: [] as Array<{
      channel: string
      type: string
      data?: Record<string, unknown>
      timestamp: string
    }>,
  }

  return {
    mockDiagnosticsState: state,
    mockClearDiagnosticEvents: vi.fn((channel?: string) => {
      if (!channel) {
        state.events = []
        return
      }

      state.events = state.events.filter((event) => event.channel !== channel)
    }),
    mockDisableDiagnostics: vi.fn(() => {
      state.enabled = false
      state.channels = []
    }),
    mockEnableDiagnostics: vi.fn((channels?: string[] | string) => {
      state.enabled = true

      if (!channels) {
        state.channels = ['all']
        return
      }

      state.channels = Array.isArray(channels) ? channels : [channels]
    }),
    mockRecordDiagnosticEvent: vi.fn((channel: string, type: string, data?: Record<string, unknown>) => {
      if (!state.enabled) {
        return
      }

      state.events.push({ channel, type, data, timestamp: new Date().toISOString() })
    }),
  }
})

let mockEpisodeLabels: Record<number, string[]> = { 0: ['SUCCESS'] }
let mockSavedEpisodeLabels: Record<number, string[]> = { 0: ['SUCCESS'] }
let mockAvailableLabels = ['SUCCESS', 'FAILURE', 'PARTIAL']
let mockLabelsLoaded = true
let mockEpisodeIndex = 0
let mockHasEdits = false
let mockIsPlaying = false
let mockAutoPlay = false
let mockAutoLoop = false
let playSpy: ReturnType<typeof vi.spyOn>
let pauseSpy: ReturnType<typeof vi.spyOn>
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
  TrajectoryPlot: (props: Record<string, unknown>) => {
    const plotProps = props as {
      selectedRange?: [number, number] | null
      onSelectedRangeChange?: (range: [number, number] | null) => void
      onCreateSubtaskFromRange?: (range: [number, number]) => void
      onSelectionStart?: () => void
      onSelectionComplete?: (range: [number, number]) => void
    }

    return (
      <div>
        <div>Trajectory Plot</div>
        <div>
          {plotProps.selectedRange
            ? `Selected range ${plotProps.selectedRange[0]}-${plotProps.selectedRange[1]}`
            : 'No selected range'}
        </div>
        <button type="button" onClick={() => plotProps.onSelectedRangeChange?.([2, 6])}>
          Select Range Draft
        </button>
        <button type="button" onClick={() => plotProps.onSelectionStart?.()}>
          Start Range Drag
        </button>
        <button type="button" onClick={() => plotProps.onSelectionComplete?.([2, 6])}>
          Finish Range Drag
        </button>
        <button
          type="button"
          onClick={() => {
            plotProps.onSelectedRangeChange?.([2, 6])
            plotProps.onSelectionComplete?.([2, 6])
          }}
        >
          Finish Range Drag
        </button>
        <button type="button" onClick={() => plotProps.onCreateSubtaskFromRange?.([2, 6])}>
          Create Subtask
        </button>
      </div>
    )
  },
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
  SubtaskList: () => <div>Subtask List</div>,
  SubtaskTimelineTrack: () => <div>Subtask Timeline Track</div>,
  SubtaskToolbar: () => <div>Subtask Toolbar</div>,
}))

vi.mock('@/components/viewer-display', () => ({
  ViewerDisplayControls: () => <div>Viewer Display Controls</div>,
}))

vi.mock('@/lib/css-filters', () => ({
  combineCssFilters: () => '',
}))

vi.mock('@/lib/playback-diagnostics', () => ({
  DIAGNOSTIC_CHANNEL_OPTIONS: ['all', 'workspace', 'playback', 'labels', 'subtasks', 'persistence', 'export', 'navigation', 'detection'],
  DIAGNOSTICS_EVENT_NAME: 'dataviewer:diagnostics',
  clearDiagnosticEvents: mockClearDiagnosticEvents,
  disableDiagnostics: mockDisableDiagnostics,
  enableDiagnostics: mockEnableDiagnostics,
  getEnabledDiagnosticsChannels: () => (mockDiagnosticsState.enabled ? mockDiagnosticsState.channels : []),
  isDiagnosticsEnabled: () => mockDiagnosticsState.enabled,
  isDiagnosticsChannelEnabled: () => mockDiagnosticsState.enabled,
  readDiagnosticEvents: (channel?: string) => {
    if (!channel) {
      return mockDiagnosticsState.events
    }

    return mockDiagnosticsState.events.filter((event) => event.channel === channel)
  },
  recordDiagnosticEvent: mockRecordDiagnosticEvent,
  stringifyDiagnosticEvents: (events: unknown[]) => JSON.stringify(events, null, 2),
}))

vi.mock('@/lib/playback-utils', () => ({
  clampFrameToPlaybackRange: (frame: number) => frame,
  computeEffectiveFps: () => 30,
  computeSyncAction: mockComputeSyncAction,
  resolvePlaybackRange: (totalFrames: number) => [0, totalFrames - 1],
  resolvePlaybackTick: (frame: number) => ({ frame, shouldStop: false }),
  shouldLoopActivePlaybackRange: (range: [number, number] | null, autoLoop: boolean) => autoLoop || !!range,
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
      subtasks: [],
      addSubtask: vi.fn(),
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
        videoUrls: { main: '/video.mp4' },
        trajectoryData: undefined,
      },
    }),
  usePlaybackControls: () => ({
    currentFrame: 0,
    isPlaying: mockIsPlaying,
    playbackSpeed: 1,
    setCurrentFrame: mockSetCurrentFrame,
    togglePlayback: mockTogglePlayback,
    setPlaybackSpeed: mockSetPlaybackSpeed,
  }),
  usePlaybackSettings: () => ({
    autoPlay: mockAutoPlay,
    autoLoop: mockAutoLoop,
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
    playSpy = vi.spyOn(HTMLMediaElement.prototype, 'play').mockImplementation(() => Promise.resolve())
    pauseSpy = vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => undefined)
    mockEpisodeLabels = { 0: ['SUCCESS'] }
    mockSavedEpisodeLabels = { 0: ['SUCCESS'] }
    mockAvailableLabels = ['SUCCESS', 'FAILURE', 'PARTIAL']
    mockLabelsLoaded = true
    mockEpisodeIndex = 0
    mockHasEdits = false
    mockIsPlaying = false
    mockAutoPlay = false
    mockAutoLoop = false
    mockSaveEpisodeLabels.mockReset()
    mockSetCurrentFrame.mockReset()
    mockTogglePlayback.mockReset()
    mockSetPlaybackSpeed.mockReset()
    mockSetAutoPlay.mockReset()
    mockSetAutoLoop.mockReset()
    mockComputeSyncAction.mockReset()
    mockComputeSyncAction.mockReturnValue({ kind: 'pause' })
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
    mockDiagnosticsState.enabled = false
    mockDiagnosticsState.channels = []
    mockDiagnosticsState.events = []
    mockClearDiagnosticEvents.mockClear()
    mockEnableDiagnostics.mockClear()
    mockDisableDiagnostics.mockClear()
    mockRecordDiagnosticEvent.mockClear()
  })

  afterEach(() => {
    cleanup()
    playSpy.mockRestore()
    pauseSpy.mockRestore()
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

  it('keeps the diagnostics panel hidden by default', () => {
    render(<AnnotationWorkspace />)

    expect(screen.queryByTestId('dataviewer-diagnostics-panel')).not.toBeInTheDocument()
  })

  it('shows a whole-dataviewer diagnostics panel when diagnostics are enabled from the shell', () => {
    mockDiagnosticsState.enabled = true
    mockDiagnosticsState.channels = ['all']

    render(<AnnotationWorkspace diagnosticsVisible />)

    expect(screen.getByTestId('dataviewer-diagnostics-panel')).toBeInTheDocument()
  })

  it('keeps the workspace header actions free of the diagnostics toggle', () => {
    render(<AnnotationWorkspace />)

    expect(within(screen.getByTestId('workspace-header-actions')).queryByRole('button', { name: /toggle diagnostics/i })).not.toBeInTheDocument()
  })

  it('renders diagnostics in a shared bottom panel outside the trajectory tab', () => {
    mockDiagnosticsState.enabled = true
    mockDiagnosticsState.channels = ['all', 'workspace', 'playback']
    mockDiagnosticsState.events = [
      { channel: 'workspace', type: 'tab-change', data: { nextTab: 'episode' }, timestamp: '2026-03-08T00:00:00.000Z' },
      { channel: 'playback', type: 'sync-action', data: { action: 'play' }, timestamp: '2026-03-08T00:00:01.000Z' },
    ]

    render(<AnnotationWorkspace />)

    const diagnosticsPanel = screen.getByTestId('dataviewer-diagnostics-panel')

    expect(diagnosticsPanel).toBeInTheDocument()
    expect(screen.getByText(/dataviewer diagnostics/i)).toBeInTheDocument()
    expect(screen.getByText(/workspace state/i)).toBeInTheDocument()
    expect(within(diagnosticsPanel).getByText(/sync-action/i)).toBeInTheDocument()
    expect(screen.queryByTestId('playback-diagnostics-panel')).not.toBeInTheDocument()
  })

  it('filters diagnostics events by channel and clears only the visible channel history', () => {
    mockDiagnosticsState.enabled = true
    mockDiagnosticsState.channels = ['all', 'labels', 'playback']
    mockDiagnosticsState.events = [
      { channel: 'labels', type: 'draft-change', data: { labels: ['FAILURE'] }, timestamp: '2026-03-08T00:00:00.000Z' },
      { channel: 'playback', type: 'sync-action', data: { action: 'play' }, timestamp: '2026-03-08T00:00:01.000Z' },
    ]

    render(<AnnotationWorkspace />)

    const diagnosticsPanel = screen.getByTestId('dataviewer-diagnostics-panel')

    fireEvent.change(within(diagnosticsPanel).getByLabelText(/filter events/i), {
      target: { value: 'labels' },
    })

    expect(within(diagnosticsPanel).getByText(/draft-change/i)).toBeInTheDocument()
    expect(within(diagnosticsPanel).queryByText(/sync-action/i)).not.toBeInTheDocument()

    fireEvent.click(within(diagnosticsPanel).getByRole('button', { name: /clear visible events/i }))

    expect(mockClearDiagnosticEvents).toHaveBeenCalledWith('labels')
    expect(within(diagnosticsPanel).queryByText(/draft-change/i)).not.toBeInTheDocument()
    expect(within(diagnosticsPanel).getByText(/no diagnostics events recorded yet/i)).toBeInTheDocument()
  })

  it('copies the visible diagnostics events as json from the shared panel', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    })

    mockDiagnosticsState.enabled = true
    mockDiagnosticsState.channels = ['all', 'export']
    mockDiagnosticsState.events = [
      { channel: 'export', type: 'dialog-open', data: { activeTab: 'episode' }, timestamp: '2026-03-08T00:00:00.000Z' },
    ]

    render(<AnnotationWorkspace />)

    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /copy json/i }))
      await Promise.resolve()
    })

    expect(writeText).toHaveBeenCalledWith(expect.stringContaining('"channel": "export"'))
    expect(writeText).toHaveBeenCalledWith(expect.stringContaining('"type": "dialog-open"'))
  })

  it('records expanded diagnostics channels for labels, subtasks, export, detection, and persistence actions', async () => {
    const handleSaveAndNextEpisode = vi.fn()
    mockDiagnosticsState.enabled = true
    mockDiagnosticsState.channels = ['all']
    mockHasEdits = true

    const { rerender } = render(
      <AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />,
    )

    mockRecordDiagnosticEvent.mockClear()

    fireEvent.click(screen.getByRole('button', { name: /toggle label draft/i }))
    rerender(<AnnotationWorkspace canGoNextEpisode onSaveAndNextEpisode={handleSaveAndNextEpisode} />)

    fireEvent.click(screen.getByRole('button', { name: /export/i }))
    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })
    fireEvent.click(screen.getByRole('button', { name: /create subtask/i }))
    fireEvent.mouseDown(screen.getByRole('tab', { name: /object detection/i }), { button: 0, ctrlKey: false })

    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /save\s*&\s*next episode/i }))
      await Promise.resolve()
    })

    expect(mockRecordDiagnosticEvent.mock.calls).toEqual(expect.arrayContaining([
      ['labels', 'draft-change', expect.objectContaining({ episodeIndex: 0, labelCount: 1 })],
      ['export', 'dialog-open', expect.objectContaining({ activeTab: 'episode' })],
      ['subtasks', 'create', expect.objectContaining({ rangeStart: 2, rangeEnd: 6 })],
      ['detection', 'tab-viewed', expect.objectContaining({ previousTab: 'trajectory' })],
      ['persistence', 'draft-saved', expect.objectContaining({ episodeIndex: 0 })],
    ]))
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

  it('renders the shared subtask list in the default episode viewer', () => {
    render(<AnnotationWorkspace />)

    expect(screen.getByText('Subtask List')).toBeInTheDocument()
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

  it('renders the same subtask list in the trajectory viewer under the compact video panel', () => {
    render(<AnnotationWorkspace />)

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })

    expect(screen.getByText('Subtask List')).toBeInTheDocument()
  })

  it('clears a draft graph selection when Escape is pressed', () => {
    render(<AnnotationWorkspace />)

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })
    fireEvent.click(screen.getByRole('button', { name: /select range draft/i }))

    expect(screen.getByRole('button', { name: /clear selection/i })).toBeInTheDocument()

    fireEvent.keyDown(window, { key: 'Escape' })

    expect(screen.queryByRole('button', { name: /clear selection/i })).not.toBeInTheDocument()
  })

  it('pauses during graph range selection and resumes from the selection start when playback was already running', () => {
    mockIsPlaying = true

    render(<AnnotationWorkspace />)

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })
    fireEvent.click(screen.getByRole('button', { name: /start range drag/i }))
    fireEvent.click(screen.getAllByRole('button', { name: /finish range drag/i })[1])

    expect(mockTogglePlayback).toHaveBeenCalledTimes(2)
    expect(mockSetCurrentFrame).toHaveBeenLastCalledWith(2)
  })

  it('keeps a graph range selection paused when playback was already paused', () => {
    mockIsPlaying = false

    render(<AnnotationWorkspace />)

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })
    fireEvent.click(screen.getByRole('button', { name: /start range drag/i }))
    fireEvent.click(screen.getAllByRole('button', { name: /finish range drag/i })[1])

    expect(mockTogglePlayback).not.toHaveBeenCalled()
    expect(mockSetCurrentFrame).toHaveBeenLastCalledWith(2)
  })

  it('restarts playback when a remounted video finishes loading while the store is already playing', () => {
    mockIsPlaying = true
    mockComputeSyncAction.mockReturnValue({ kind: 'play', playbackRate: 1 })

    const { container } = render(<AnnotationWorkspace />)
    const video = container.querySelector('video')

    expect(video).not.toBeNull()

    Object.defineProperty(video!, 'duration', {
      configurable: true,
      value: 12.8,
    })

    playSpy.mockClear()

    fireEvent.loadedMetadata(video!)

    expect(playSpy).toHaveBeenCalledTimes(1)
  })

  it('marks the trajectory playback controls as keep-selection controls for draft ranges', () => {
    render(<AnnotationWorkspace />)

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })
    fireEvent.click(screen.getByRole('button', { name: /select range draft/i }))

    expect(screen.getByRole('button', { name: /play playback/i }).closest('[data-keep-playback-selection="true"]')).not.toBeNull()
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
