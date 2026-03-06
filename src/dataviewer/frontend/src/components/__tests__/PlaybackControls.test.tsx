import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'

import { PlaybackControls } from '@/components/episode-viewer/PlaybackControls'

afterEach(cleanup)

describe('PlaybackControls', () => {
  const defaultProps = {
    currentFrame: 100,
    totalFrames: 385,
    duration: 12.833,
    fps: 30,
  }

  it('renders frame navigation buttons', () => {
    render(<PlaybackControls {...defaultProps} />)
    expect(screen.getByTitle('Go to start')).toBeInTheDocument()
    expect(screen.getByTitle('Go to end')).toBeInTheDocument()
  })

  it('renders play/pause toggle', () => {
    render(<PlaybackControls {...defaultProps} />)
    expect(screen.getByTitle(/play|pause/i)).toBeInTheDocument()
  })

  it('displays formatted time', () => {
    render(<PlaybackControls {...defaultProps} />)
    // 100 / 30 = 3.33s → "0:03" ; 12.833s → "0:12"
    expect(screen.getByText(/0:03/)).toBeInTheDocument()
  })

  it('renders speed options', () => {
    render(<PlaybackControls {...defaultProps} />)
    expect(screen.getByText('1x')).toBeInTheDocument()
    expect(screen.getByText('2x')).toBeInTheDocument()
  })

  it('play button uses icon-only variant with consistent size', () => {
    render(<PlaybackControls {...defaultProps} />)
    const playButton = screen.getByTitle(/play/i)
    // Button should use size="icon" for consistent dimensions
    expect(playButton).toBeInTheDocument()
    // Should not contain text that changes width
    expect(playButton.textContent).toBe('')
  })
})
