import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { LabelPanel } from '@/components/annotation-panel/LabelPanel'
import { useLabelStore } from '@/stores/label-store'

const mockToggle = vi.fn()
const mockAddLabelOption = vi.fn()
const mockRemoveLabelOption = vi.fn()

vi.mock('@/hooks/use-labels', () => ({
  useCurrentEpisodeLabels: () => ({
    currentLabels: ['SUCCESS'],
    toggle: mockToggle,
  }),
  useAddLabelOption: () => ({
    mutate: mockAddLabelOption,
    isPending: false,
  }),
  useRemoveLabelOption: () => ({
    mutate: mockRemoveLabelOption,
    isPending: false,
  }),
  useSaveAllLabels: () => ({
    mutate: vi.fn(),
    isPending: false,
    isSuccess: false,
  }),
}))

describe('LabelPanel', () => {
  beforeEach(() => {
    mockToggle.mockReset()
    mockAddLabelOption.mockReset()
    mockRemoveLabelOption.mockReset()
    useLabelStore.getState().reset()
    useLabelStore.getState().setAvailableLabels(['SUCCESS', 'FAILURE'])
  })

  it('explains that label changes save automatically instead of showing a save-all action', () => {
    render(<LabelPanel episodeIndex={3} />)

    expect(screen.queryByRole('button', { name: /save all/i })).not.toBeInTheDocument()
    expect(screen.getByText(/changes save automatically/i)).toBeInTheDocument()
  })

  it('allows deleting a label option from the panel', async () => {
    const user = userEvent.setup()

    render(<LabelPanel episodeIndex={3} />)

    await user.click(screen.getByRole('button', { name: /delete label success/i }))

    expect(mockRemoveLabelOption).toHaveBeenCalledWith('SUCCESS')
  })
})
