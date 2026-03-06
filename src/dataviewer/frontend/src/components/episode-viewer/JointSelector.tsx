/**
 * Joint selector for trajectory visualization.
 *
 * Renders grouped toggle chips organized by actuator category,
 * with per-group and global selection controls.
 */

import { cn } from '@/lib/utils'

import {
  getJointColor,
  getJointLabel,
  JOINT_GROUPS,
  type JointGroup,
} from './joint-constants'

interface JointSelectorProps {
  jointCount: number
  selectedJoints: number[]
  onSelectJoints: (joints: number[]) => void
  colors: string[]
  groups?: JointGroup[]
}

export function JointSelector({
  jointCount,
  selectedJoints,
  onSelectJoints,
  colors,
  groups = JOINT_GROUPS,
}: JointSelectorProps) {
  const toggleJoint = (jointIdx: number) => {
    if (selectedJoints.includes(jointIdx)) {
      onSelectJoints(selectedJoints.filter((j) => j !== jointIdx))
    } else {
      onSelectJoints([...selectedJoints, jointIdx].sort((a, b) => a - b))
    }
  }

  const selectAll = () => {
    onSelectJoints(Array.from({ length: jointCount }, (_, i) => i))
  }

  const clearAll = () => {
    onSelectJoints([])
  }

  const toggleGroup = (indices: number[]) => {
    const valid = indices.filter((i) => i < jointCount)
    const allSelected = valid.every((i) => selectedJoints.includes(i))
    if (allSelected) {
      onSelectJoints(selectedJoints.filter((j) => !valid.includes(j)))
    } else {
      const merged = new Set([...selectedJoints, ...valid])
      onSelectJoints([...merged].sort((a, b) => a - b))
    }
  }

  if (jointCount === 0) {
    return (
      <span className="text-sm text-muted-foreground">No joints available</span>
    )
  }

  // Build visible groups filtered to valid indices
  const allGroupedIndices = new Set(groups.flatMap((g) => g.indices))
  const visibleGroups = groups
    .map((g) => ({ ...g, indices: g.indices.filter((i) => i < jointCount) }))
    .filter((g) => g.indices.length > 0)

  // Collect ungrouped joints into an "Other" section
  const otherIndices = Array.from({ length: jointCount }, (_, i) => i).filter(
    (i) => !allGroupedIndices.has(i),
  )

  return (
    <div className="flex flex-col gap-1">
      {/* Global controls */}
      <div className="flex items-center gap-1">
        <button
          onClick={selectAll}
          className={cn(
            'px-2 py-0.5 text-xs rounded border transition-colors',
            selectedJoints.length === jointCount
              ? 'bg-primary text-primary-foreground border-primary'
              : 'bg-muted text-muted-foreground border-transparent hover:border-border',
          )}
        >
          All
        </button>
        <button
          onClick={clearAll}
          className={cn(
            'px-2 py-0.5 text-xs rounded border transition-colors',
            selectedJoints.length === 0
              ? 'bg-primary text-primary-foreground border-primary'
              : 'bg-muted text-muted-foreground border-transparent hover:border-border',
          )}
        >
          None
        </button>
      </div>

      {/* Grouped joint sections */}
      <div className="flex flex-wrap gap-x-3 gap-y-1">
        {visibleGroups.map((group) => {
          const allActive = group.indices.every((i) => selectedJoints.includes(i))
          return (
            <div
              key={group.id}
              data-testid={`joint-group-${group.id}`}
              className="flex items-center gap-1"
            >
              <button
                onClick={() => toggleGroup(group.indices)}
                className={cn(
                  'text-xs font-medium transition-colors whitespace-nowrap',
                  allActive
                    ? 'text-foreground'
                    : 'text-muted-foreground hover:text-foreground',
                )}
              >
                {group.label}
              </button>
              {group.indices.map((idx) => {
                const isSelected = selectedJoints.includes(idx)
                const color = getJointColor(idx, colors)
                return (
                  <button
                    key={idx}
                    data-joint-chip
                    onClick={() => toggleJoint(idx)}
                    className={cn(
                      'inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded border transition-all',
                      isSelected
                        ? 'border-current font-medium'
                        : 'border-transparent opacity-40 hover:opacity-70',
                    )}
                    style={{ color }}
                  >
                    <span
                      className="w-2 h-2 rounded-full flex-shrink-0"
                      style={{ backgroundColor: color }}
                    />
                    {getJointLabel(idx)}
                  </button>
                )
              })}
            </div>
          )
        })}

        {otherIndices.length > 0 && (
          <div
            data-testid="joint-group-other"
            className="flex items-center gap-1"
          >
            <button
              onClick={() => toggleGroup(otherIndices)}
              className={cn(
                'text-xs font-medium transition-colors whitespace-nowrap',
                otherIndices.every((i) => selectedJoints.includes(i))
                  ? 'text-foreground'
                  : 'text-muted-foreground hover:text-foreground',
              )}
            >
              Other
            </button>
            {otherIndices.map((idx) => {
              const isSelected = selectedJoints.includes(idx)
              const color = getJointColor(idx, colors)
              return (
                <button
                  key={idx}
                  data-joint-chip
                  onClick={() => toggleJoint(idx)}
                  className={cn(
                    'inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded border transition-all',
                    isSelected
                      ? 'border-current font-medium'
                      : 'border-transparent opacity-40 hover:opacity-70',
                  )}
                  style={{ color }}
                >
                  <span
                    className="w-2 h-2 rounded-full flex-shrink-0"
                    style={{ backgroundColor: color }}
                  />
                  {getJointLabel(idx)}
                </button>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
