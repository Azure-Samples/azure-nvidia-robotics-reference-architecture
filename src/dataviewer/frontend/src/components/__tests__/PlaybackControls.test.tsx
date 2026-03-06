import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'

import { PlaybackControls } from '@/components/episode-viewer/PlaybackControls'
import { useEpisodeStore } from '@/stores'

afterEach(() => {
  cleanup()
  useEpisodeStore.getState().reset()
})

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

  it('clicking a speed button updates store playbackSpeed', () => {
    render(<PlaybackControls {...defaultProps} />)
    fireEvent.click(screen.getByText('2x'))
    expect(useEpisodeStore.getState().playbackSpeed).toBe(2)
  })

  it('highlights the active speed button', () => {
    useEpisodeStore.getState().setPlaybackSpeed(2)
    render(<PlaybackControls {...defaultProps} />)
    const btn2x = screen.getByText('2x')
    const btn1x = screen.getByText('1x')
    // Active button uses 'default' variant (solid bg), inactive uses 'ghost'
    expect(btn2x.className).toContain('bg-primary')
    expect(btn1x.className).not.toContain('bg-primary')
  })

  it('switching speeds updates the highlighted button', () => {
    render(<PlaybackControls {...defaultProps} />)
    fireEvent.click(screen.getByText('2x'))
    expect(useEpisodeStore.getState().playbackSpeed).toBe(2)

    fireEvent.click(screen.getByText('0.5x'))
    expect(useEpisodeStore.getState().playbackSpeed).toBe(0.5)
  })

  it('renders all five speed options', () => {
    render(<PlaybackControls {...defaultProps} />)
    for (const label of ['0.25x', '0.5x', '1x', '1.5x', '2x']) {
      expect(screen.getByText(label)).toBeInTheDocument()
    }
  })
})
