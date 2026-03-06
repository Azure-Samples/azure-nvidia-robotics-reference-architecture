import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { JointSelector } from '@/components/episode-viewer/JointSelector'

const COLORS = ['#ef4444', '#22c55e', '#3b82f6', '#8b5cf6']

afterEach(cleanup)

describe('JointSelector', () => {
  it('renders joint count summary', () => {
    render(
      <JointSelector
        jointCount={8}
        selectedJoints={[0, 1, 2]}
        onSelectJoints={vi.fn()}
        colors={COLORS}
      />,
    )
    expect(screen.getByText('3 / 8 Joints')).toBeInTheDocument()
  })

  it('opens dropdown on click and shows joint options', () => {
    render(
      <JointSelector
        jointCount={4}
        selectedJoints={[0]}
        onSelectJoints={vi.fn()}
        colors={COLORS}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: /joints/i }))
    expect(screen.getByText('Right X')).toBeInTheDocument()
    expect(screen.getByText('Right Y')).toBeInTheDocument()
  })

  it('dropdown container has z-50 class for stacking above chart elements', () => {
    const { container } = render(
      <JointSelector
        jointCount={4}
        selectedJoints={[0]}
        onSelectJoints={vi.fn()}
        colors={COLORS}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: /joints/i }))
    const dropdown = container.querySelector('.z-50')
    expect(dropdown).toBeInTheDocument()
  })

  it('toggles joint selection when an option is clicked', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={4}
        selectedJoints={[0]}
        onSelectJoints={onSelect}
        colors={COLORS}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: /joints/i }))
    fireEvent.click(screen.getByText('Right Y'))
    expect(onSelect).toHaveBeenCalledWith([0, 1])
  })

  it('deselects a joint when already selected', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={4}
        selectedJoints={[0, 1]}
        onSelectJoints={onSelect}
        colors={COLORS}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: /joints/i }))
    fireEvent.click(screen.getByText('Right X'))
    expect(onSelect).toHaveBeenCalledWith([1])
  })

  it('select all adds every joint index', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={4}
        selectedJoints={[]}
        onSelectJoints={onSelect}
        colors={COLORS}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: /joints/i }))
    fireEvent.click(screen.getByText('Select All'))
    expect(onSelect).toHaveBeenCalledWith([0, 1, 2, 3])
  })

  it('clear all removes all selections', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={4}
        selectedJoints={[0, 1, 2]}
        onSelectJoints={onSelect}
        colors={COLORS}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: /joints/i }))
    fireEvent.click(screen.getByText('Clear'))
    expect(onSelect).toHaveBeenCalledWith([])
  })
})
