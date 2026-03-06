import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { useJointConfigStore } from '@/stores/joint-config-store'

const defaultConfig = {
  datasetId: 'test-dataset',
  labels: { '0': 'Right X', '1': 'Right Y', '2': 'Right Z' },
  groups: [
    { id: 'right-pos', label: 'Right Arm', indices: [0, 1, 2] },
    { id: 'left-pos', label: 'Left Arm', indices: [3, 4, 5] },
  ],
}

beforeEach(() => {
  useJointConfigStore.getState().reset()
})

afterEach(() => {
  useJointConfigStore.getState().reset()
})

describe('joint-config-store', () => {
  it('sets config and marks as loaded', () => {
    useJointConfigStore.getState().setConfig(defaultConfig)
    const state = useJointConfigStore.getState()
    expect(state.isLoaded).toBe(true)
    expect(state.config?.datasetId).toBe('test-dataset')
    expect(state.config?.groups).toHaveLength(2)
  })

  it('updates a joint label', () => {
    useJointConfigStore.getState().setConfig(defaultConfig)
    useJointConfigStore.getState().updateLabel(0, 'Renamed X')
    expect(useJointConfigStore.getState().config?.labels['0']).toBe('Renamed X')
  })

  it('updates a group label', () => {
    useJointConfigStore.getState().setConfig(defaultConfig)
    useJointConfigStore.getState().updateGroupLabel('right-pos', 'Right Position')
    const group = useJointConfigStore.getState().config?.groups.find((g) => g.id === 'right-pos')
    expect(group?.label).toBe('Right Position')
  })

  it('moves a joint between groups', () => {
    useJointConfigStore.getState().setConfig(defaultConfig)
    useJointConfigStore.getState().moveJoint(2, 'right-pos', 'left-pos', 0)
    const state = useJointConfigStore.getState().config!
    const rightGroup = state.groups.find((g) => g.id === 'right-pos')!
    const leftGroup = state.groups.find((g) => g.id === 'left-pos')!
    expect(rightGroup.indices).toEqual([0, 1])
    expect(leftGroup.indices).toEqual([2, 3, 4, 5])
  })

  it('creates a new group and removes joints from existing groups', () => {
    useJointConfigStore.getState().setConfig(defaultConfig)
    useJointConfigStore.getState().createGroup('Custom Group', [1, 4])
    const state = useJointConfigStore.getState().config!
    const rightGroup = state.groups.find((g) => g.id === 'right-pos')!
    const leftGroup = state.groups.find((g) => g.id === 'left-pos')!
    const customGroup = state.groups.find((g) => g.label === 'Custom Group')!
    expect(rightGroup.indices).toEqual([0, 2])
    expect(leftGroup.indices).toEqual([3, 5])
    expect(customGroup.indices).toEqual([1, 4])
  })

  it('deletes a group', () => {
    useJointConfigStore.getState().setConfig(defaultConfig)
    useJointConfigStore.getState().deleteGroup('left-pos')
    expect(useJointConfigStore.getState().config?.groups).toHaveLength(1)
    expect(useJointConfigStore.getState().config?.groups[0].id).toBe('right-pos')
  })

  it('reorders groups', () => {
    useJointConfigStore.getState().setConfig(defaultConfig)
    useJointConfigStore.getState().reorderGroups(['left-pos', 'right-pos'])
    const groups = useJointConfigStore.getState().config?.groups
    expect(groups?.[0].id).toBe('left-pos')
    expect(groups?.[1].id).toBe('right-pos')
  })

  it('reset clears config', () => {
    useJointConfigStore.getState().setConfig(defaultConfig)
    useJointConfigStore.getState().reset()
    expect(useJointConfigStore.getState().config).toBeNull()
    expect(useJointConfigStore.getState().isLoaded).toBe(false)
  })
})
