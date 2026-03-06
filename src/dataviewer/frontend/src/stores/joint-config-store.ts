/**
 * Zustand store for per-dataset joint configuration.
 */

import { create } from 'zustand'
import { devtools } from 'zustand/middleware'

import type { JointGroup } from '@/components/episode-viewer/joint-constants'

export interface JointConfig {
  datasetId: string
  labels: Record<string, string>
  groups: JointGroup[]
}

interface JointConfigState {
  config: JointConfig | null
  isLoaded: boolean
}

interface JointConfigActions {
  setConfig: (config: JointConfig) => void
  updateLabel: (index: number, label: string) => void
  updateGroupLabel: (groupId: string, label: string) => void
  moveJoint: (jointIndex: number, fromGroupId: string, toGroupId: string, toPosition: number) => void
  createGroup: (label: string, jointIndices: number[]) => void
  deleteGroup: (groupId: string) => void
  reorderGroups: (groupIds: string[]) => void
  reset: () => void
}

type JointConfigStore = JointConfigState & JointConfigActions

const initialState: JointConfigState = {
  config: null,
  isLoaded: false,
}

let _groupCounter = 0

export const useJointConfigStore = create<JointConfigStore>()(
  devtools(
    (set, get) => ({
      ...initialState,

      setConfig: (config) => {
        set({ config, isLoaded: true }, false, 'setConfig')
      },

      updateLabel: (index, label) => {
        const { config } = get()
        if (!config) return
        set(
          {
            config: {
              ...config,
              labels: { ...config.labels, [String(index)]: label },
            },
          },
          false,
          'updateLabel',
        )
      },

      updateGroupLabel: (groupId, label) => {
        const { config } = get()
        if (!config) return
        set(
          {
            config: {
              ...config,
              groups: config.groups.map((g) => (g.id === groupId ? { ...g, label } : g)),
            },
          },
          false,
          'updateGroupLabel',
        )
      },

      moveJoint: (jointIndex, fromGroupId, toGroupId, toPosition) => {
        const { config } = get()
        if (!config) return
        const groups = config.groups.map((g) => {
          if (g.id === fromGroupId) {
            return { ...g, indices: g.indices.filter((i) => i !== jointIndex) }
          }
          if (g.id === toGroupId) {
            const newIndices = [...g.indices]
            newIndices.splice(toPosition, 0, jointIndex)
            return { ...g, indices: newIndices }
          }
          return g
        })
        set({ config: { ...config, groups } }, false, 'moveJoint')
      },

      createGroup: (label, jointIndices) => {
        const { config } = get()
        if (!config) return
        _groupCounter++
        const newGroup: JointGroup = {
          id: `custom-${Date.now()}-${_groupCounter}`,
          label,
          indices: jointIndices,
        }
        // Remove joints from existing groups
        const groups = config.groups.map((g) => ({
          ...g,
          indices: g.indices.filter((i) => !jointIndices.includes(i)),
        }))
        set(
          { config: { ...config, groups: [...groups, newGroup] } },
          false,
          'createGroup',
        )
      },

      deleteGroup: (groupId) => {
        const { config } = get()
        if (!config) return
        set(
          {
            config: {
              ...config,
              groups: config.groups.filter((g) => g.id !== groupId),
            },
          },
          false,
          'deleteGroup',
        )
      },

      reorderGroups: (groupIds) => {
        const { config } = get()
        if (!config) return
        const groupMap = new Map(config.groups.map((g) => [g.id, g]))
        const reordered = groupIds.map((id) => groupMap.get(id)).filter(Boolean) as JointGroup[]
        // Append any groups not in the new order
        const remaining = config.groups.filter((g) => !groupIds.includes(g.id))
        set(
          { config: { ...config, groups: [...reordered, ...remaining] } },
          false,
          'reorderGroups',
        )
      },

      reset: () => {
        set(initialState, false, 'reset')
      },
    }),
    { name: 'joint-config-store' },
  ),
)
