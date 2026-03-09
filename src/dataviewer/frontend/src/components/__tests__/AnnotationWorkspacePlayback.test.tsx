import './support/annotationWorkspaceTestSupport'

import { fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { AnnotationWorkspace } from '@/components/annotation-workspace/AnnotationWorkspace'

import {
  mediaSpies,
  mockComputeSyncAction,
  mockSetCurrentFrame,
  mockTogglePlayback,
  setupAnnotationWorkspaceTestCase,
  teardownAnnotationWorkspaceTestCase,
  testState,
} from './support/annotationWorkspaceTestSupport'

describe('AnnotationWorkspace playback and trajectory tab flows', () => {
  beforeEach(setupAnnotationWorkspaceTestCase)
  afterEach(teardownAnnotationWorkspaceTestCase)

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

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })
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
    testState.isPlaying = true

    render(<AnnotationWorkspace />)

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })
    fireEvent.click(screen.getByRole('button', { name: /start range drag/i }))
    fireEvent.click(screen.getAllByRole('button', { name: /finish range drag/i })[1])

    expect(mockTogglePlayback).toHaveBeenCalledTimes(2)
    expect(mockSetCurrentFrame).toHaveBeenLastCalledWith(2)
  })

  it('keeps a graph range selection paused when playback was already paused', () => {
    testState.isPlaying = false

    render(<AnnotationWorkspace />)

    fireEvent.mouseDown(screen.getByRole('tab', { name: /trajectory viewer/i }), { button: 0, ctrlKey: false })
    fireEvent.click(screen.getByRole('button', { name: /start range drag/i }))
    fireEvent.click(screen.getAllByRole('button', { name: /finish range drag/i })[1])

    expect(mockTogglePlayback).not.toHaveBeenCalled()
    expect(mockSetCurrentFrame).toHaveBeenLastCalledWith(2)
  })

  it('restarts playback when a remounted video finishes loading while the store is already playing', () => {
    testState.isPlaying = true
    mockComputeSyncAction.mockReturnValue({ kind: 'play', playbackRate: 1 })

    const { container } = render(<AnnotationWorkspace />)
    const video = container.querySelector('video')

    expect(video).not.toBeNull()
    Object.defineProperty(video!, 'duration', { configurable: true, value: 12.8 })
    mediaSpies.play?.mockClear()

    fireEvent.loadedMetadata(video!)
    expect(mediaSpies.play).toHaveBeenCalledTimes(1)
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
})
