import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest'

import { JOINT_COLORS } from '@/components/episode-viewer/joint-constants'
import { JointConfigDefaultsEditor } from '@/components/episode-viewer/JointConfigDefaultsEditor'

beforeAll(() => {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver
})

afterEach(cleanup)

const defaultGroups = [
  { id: 'right-pos', label: 'Right Arm', indices: [0, 1, 2] },
  { id: 'right-orient', label: 'Right Orientation', indices: [3, 4, 5, 6] },
  { id: 'left-pos', label: 'Left Arm', indices: [7, 8, 9] },
]

const defaultLabels: Record<string, string> = {
  '0': 'Right X',
  '1': 'Right Y',
  '2': 'Right Z',
  '3': 'Right Qx',
  '4': 'Right Qy',
  '5': 'Right Qz',
  '6': 'Right Qw',
  '7': 'Left X',
  '8': 'Left Y',
  '9': 'Left Z',
}

const baseProps = {
  open: true,
  onOpenChange: vi.fn(),
  groups: defaultGroups,
  labels: defaultLabels,
  onSave: vi.fn(),
  colors: JOINT_COLORS,
}

describe('JointConfigDefaultsEditor', () => {
  it('renders dialog when open', () => {
    render(<JointConfigDefaultsEditor {...baseProps} />)
    expect(screen.getByText('Joint Configuration Defaults')).toBeInTheDocument()
  })

  it('does not render dialog content when closed', () => {
    render(<JointConfigDefaultsEditor {...baseProps} open={false} />)
    expect(screen.queryByText('Joint Configuration Defaults')).not.toBeInTheDocument()
  })

  it('displays all groups with their labels', () => {
    render(<JointConfigDefaultsEditor {...baseProps} />)
    expect(screen.getByText('Right Arm')).toBeInTheDocument()
    expect(screen.getByText('Right Orientation')).toBeInTheDocument()
    expect(screen.getByText('Left Arm')).toBeInTheDocument()
  })

  it('displays joint labels within their groups', () => {
    render(<JointConfigDefaultsEditor {...baseProps} />)
    expect(screen.getByText('Right X')).toBeInTheDocument()
    expect(screen.getByText('Right Y')).toBeInTheDocument()
    expect(screen.getByText('Right Z')).toBeInTheDocument()
    expect(screen.getByText('Right Qx')).toBeInTheDocument()
    expect(screen.getByText('Left X')).toBeInTheDocument()
  })

  it('renders joint color indicators', () => {
    render(<JointConfigDefaultsEditor {...baseProps} />)
    const colorDots = document.querySelectorAll('[data-joint-color]')
    expect(colorDots.length).toBe(10)
  })

  it('allows editing a joint label', async () => {
    const user = userEvent.setup()
    render(<JointConfigDefaultsEditor {...baseProps} />)
    const editButtons = screen.getAllByLabelText('Edit joint label')
    await user.click(editButtons[0])
    const input = screen.getByRole('textbox')
    await user.clear(input)
    await user.type(input, 'Custom Joint{Enter}')
    expect(screen.getByText('Custom Joint')).toBeInTheDocument()
  })

  it('allows editing a group label', async () => {
    const user = userEvent.setup()
    render(<JointConfigDefaultsEditor {...baseProps} />)
    const editButtons = screen.getAllByLabelText('Edit group label')
    await user.click(editButtons[0])
    const input = screen.getByRole('textbox')
    await user.clear(input)
    await user.type(input, 'Custom Group{Enter}')
    expect(screen.getByText('Custom Group')).toBeInTheDocument()
  })

  it('allows adding a new group', async () => {
    const user = userEvent.setup()
    render(<JointConfigDefaultsEditor {...baseProps} />)
    await user.click(screen.getByText('Add Group'))
    expect(screen.getByText('New Group')).toBeInTheDocument()
  })

  it('allows deleting a group', async () => {
    const user = userEvent.setup()
    render(<JointConfigDefaultsEditor {...baseProps} />)
    const deleteButtons = screen.getAllByLabelText('Delete group')
    await user.click(deleteButtons[0])
    expect(screen.queryByText('Right Arm')).not.toBeInTheDocument()
  })

  it('moves joints to ungrouped when their group is deleted', async () => {
    const user = userEvent.setup()
    render(<JointConfigDefaultsEditor {...baseProps} />)
    const deleteButtons = screen.getAllByLabelText('Delete group')
    await user.click(deleteButtons[0])
    // Right X, Y, Z should now appear in Ungrouped section
    const ungrouped = screen.getByTestId('ungrouped-joints')
    expect(within(ungrouped).getByText('Right X')).toBeInTheDocument()
  })

  it('allows assigning an ungrouped joint to a group', async () => {
    const user = userEvent.setup()
    const propsWithUngrouped = {
      ...baseProps,
      labels: { ...defaultLabels, '10': 'Extra Joint' },
    }
    render(<JointConfigDefaultsEditor {...propsWithUngrouped} />)
    const ungrouped = screen.getByTestId('ungrouped-joints')
    const addButtons = within(ungrouped).getAllByLabelText('Assign to group')
    await user.click(addButtons[0])
    // Should show group selection buttons inside the ungrouped section
    const assignButtons = within(ungrouped).getAllByRole('button')
    const groupOptionLabels = assignButtons.map((b) => b.textContent)
    expect(groupOptionLabels).toEqual(expect.arrayContaining(['Right Arm', 'Left Arm']))
  })

  it('calls onSave with updated config when Save is clicked', async () => {
    const user = userEvent.setup()
    const onSave = vi.fn()
    render(<JointConfigDefaultsEditor {...baseProps} onSave={onSave} />)
    await user.click(screen.getByText('Save'))
    expect(onSave).toHaveBeenCalledWith(
      expect.objectContaining({
        groups: defaultGroups,
        labels: defaultLabels,
      }),
    )
  })

  it('closes dialog and discards changes when Cancel is clicked', async () => {
    const user = userEvent.setup()
    const onOpenChange = vi.fn()
    render(<JointConfigDefaultsEditor {...baseProps} onOpenChange={onOpenChange} />)
    // Make a change first
    const deleteButtons = screen.getAllByLabelText('Delete group')
    await user.click(deleteButtons[0])
    // Cancel
    await user.click(screen.getByText('Cancel'))
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('resets to built-in defaults when Reset is clicked', async () => {
    const user = userEvent.setup()
    render(<JointConfigDefaultsEditor {...baseProps} />)
    // Delete a group first
    const deleteButtons = screen.getAllByLabelText('Delete group')
    await user.click(deleteButtons[0])
    expect(screen.queryByText('Right Arm')).not.toBeInTheDocument()
    // Reset
    await user.click(screen.getByText('Reset'))
    // Built-in defaults from joint-constants.ts include 6 groups
    expect(screen.getByText('Right Arm')).toBeInTheDocument()
  })

  it('shows saving state during save operation', () => {
    render(<JointConfigDefaultsEditor {...baseProps} isSaving />)
    expect(screen.getByText('Saving…')).toBeInTheDocument()
  })
})
