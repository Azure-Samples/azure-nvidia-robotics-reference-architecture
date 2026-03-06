import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { JOINT_COLORS } from '@/components/episode-viewer/joint-constants'
import { JointSelector } from '@/components/episode-viewer/JointSelector'

afterEach(cleanup)

describe('JointSelector', () => {
  it('renders group sections for joint categories', () => {
    render(
      <JointSelector
        jointCount={16}
        selectedJoints={[0, 1, 2]}
        onSelectJoints={vi.fn()}
        colors={JOINT_COLORS}
      />,
    )
    expect(screen.getByTestId('joint-group-right-pos')).toBeInTheDocument()
    expect(screen.getByTestId('joint-group-right-orient')).toBeInTheDocument()
    expect(screen.getByTestId('joint-group-right-grip')).toBeInTheDocument()
    expect(screen.getByTestId('joint-group-left-pos')).toBeInTheDocument()
    expect(screen.getByTestId('joint-group-left-orient')).toBeInTheDocument()
    expect(screen.getByTestId('joint-group-left-grip')).toBeInTheDocument()
  })

  it('renders All and None global controls', () => {
    render(
      <JointSelector
        jointCount={16}
        selectedJoints={[0, 1, 2]}
        onSelectJoints={vi.fn()}
        colors={JOINT_COLORS}
      />,
    )
    expect(screen.getByText('All')).toBeInTheDocument()
    expect(screen.getByText('None')).toBeInTheDocument()
  })

  it('renders joint chips within their group sections', () => {
    render(
      <JointSelector
        jointCount={16}
        selectedJoints={[0, 1]}
        onSelectJoints={vi.fn()}
        colors={JOINT_COLORS}
      />,
    )
    const rightArmGroup = screen.getByTestId('joint-group-right-pos')
    expect(within(rightArmGroup).getByText('Right X')).toBeInTheDocument()
    expect(within(rightArmGroup).getByText('Right Y')).toBeInTheDocument()
    expect(within(rightArmGroup).getByText('Right Z')).toBeInTheDocument()
  })

  it('clicking group label toggles all joints in that group', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={16}
        selectedJoints={[]}
        onSelectJoints={onSelect}
        colors={JOINT_COLORS}
      />,
    )
    fireEvent.click(screen.getByText('Right Arm'))
    expect(onSelect).toHaveBeenCalledWith([0, 1, 2])
  })

  it('clicking group label deselects all when group is fully selected', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={16}
        selectedJoints={[0, 1, 2]}
        onSelectJoints={onSelect}
        colors={JOINT_COLORS}
      />,
    )
    fireEvent.click(screen.getByText('Right Arm'))
    expect(onSelect).toHaveBeenCalledWith([])
  })

  it('joints not in any group render in Other section', () => {
    render(
      <JointSelector
        jointCount={18}
        selectedJoints={[]}
        onSelectJoints={vi.fn()}
        colors={JOINT_COLORS}
      />,
    )
    const otherGroup = screen.getByTestId('joint-group-other')
    expect(within(otherGroup).getByText('Ch 16')).toBeInTheDocument()
    expect(within(otherGroup).getByText('Ch 17')).toBeInTheDocument()
  })

  it('selected joints have data attribute for styling', () => {
    const { container } = render(
      <JointSelector
        jointCount={4}
        selectedJoints={[0]}
        onSelectJoints={vi.fn()}
        colors={JOINT_COLORS}
      />,
    )
    const chips = container.querySelectorAll('[data-joint-chip]')
    expect(chips).toHaveLength(4)
  })

  it('clicking a joint chip toggles selection', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={4}
        selectedJoints={[0]}
        onSelectJoints={onSelect}
        colors={JOINT_COLORS}
      />,
    )
    fireEvent.click(screen.getByText('Right Y'))
    expect(onSelect).toHaveBeenCalledWith([0, 1])
  })

  it('clicking a selected joint chip deselects it', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={4}
        selectedJoints={[0, 1]}
        onSelectJoints={onSelect}
        colors={JOINT_COLORS}
      />,
    )
    fireEvent.click(screen.getByText('Right X'))
    expect(onSelect).toHaveBeenCalledWith([1])
  })

  it('All button selects every joint', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={4}
        selectedJoints={[]}
        onSelectJoints={onSelect}
        colors={JOINT_COLORS}
      />,
    )
    fireEvent.click(screen.getByText('All'))
    expect(onSelect).toHaveBeenCalledWith([0, 1, 2, 3])
  })

  it('None button clears all selections', () => {
    const onSelect = vi.fn()
    render(
      <JointSelector
        jointCount={4}
        selectedJoints={[0, 1, 2]}
        onSelectJoints={onSelect}
        colors={JOINT_COLORS}
      />,
    )
    fireEvent.click(screen.getByText('None'))
    expect(onSelect).toHaveBeenCalledWith([])
  })

  it('shows no joints message when jointCount is 0', () => {
    render(
      <JointSelector
        jointCount={0}
        selectedJoints={[]}
        onSelectJoints={vi.fn()}
        colors={JOINT_COLORS}
      />,
    )
    expect(screen.getByText('No joints available')).toBeInTheDocument()
  })
})
