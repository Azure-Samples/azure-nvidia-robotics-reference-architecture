/**
 * Dialog-based editor for global joint configuration defaults.
 *
 * Operates on a local copy of the defaults config — changes are only
 * persisted when the user explicitly clicks Save.
 */

import { ArrowRightLeft, Pencil, Plus, Settings, Trash2 } from 'lucide-react'
import { type KeyboardEvent, useCallback, useEffect, useRef, useState } from 'react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Separator } from '@/components/ui/separator'

import {
  getJointColor,
  JOINT_COLORS,
  JOINT_GROUPS,
  type JointGroup,
  OBSERVATION_LABELS,
} from './joint-constants'

export interface JointConfigDefaultsEditorProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  groups: JointGroup[]
  labels: Record<string, string>
  onSave: (config: { groups: JointGroup[]; labels: Record<string, string> }) => void
  isSaving?: boolean
  colors?: string[]
}

function InlineEditField({
  value,
  onCommit,
  onCancel,
}: {
  value: string
  onCommit: (val: string) => void
  onCancel: () => void
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [text, setText] = useState(value)

  useEffect(() => {
    inputRef.current?.focus()
    inputRef.current?.select()
  }, [])

  const handleKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      const trimmed = text.trim()
      if (trimmed) onCommit(trimmed)
      else onCancel()
    } else if (e.key === 'Escape') {
      e.preventDefault()
      onCancel()
    }
  }

  return (
    <input
      ref={inputRef}
      value={text}
      onChange={(e) => setText(e.target.value)}
      onKeyDown={handleKeyDown}
      onBlur={() => {
        const trimmed = text.trim()
        if (trimmed && trimmed !== value) onCommit(trimmed)
        else onCancel()
      }}
      className="bg-transparent border-b border-primary text-sm outline-none px-1"
    />
  )
}

function IndexEditField({
  value,
  onCommit,
  onCancel,
}: {
  value: number
  onCommit: (val: number) => void
  onCancel: () => void
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [num, setNum] = useState(String(value))

  useEffect(() => {
    inputRef.current?.focus()
    inputRef.current?.select()
  }, [])

  const handleKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      const parsed = parseInt(num, 10)
      if (!isNaN(parsed) && parsed >= 0) onCommit(parsed)
      else onCancel()
    } else if (e.key === 'Escape') {
      e.preventDefault()
      onCancel()
    }
  }

  return (
    <input
      ref={inputRef}
      type="number"
      min={0}
      value={num}
      onChange={(e) => setNum(e.target.value)}
      onKeyDown={handleKeyDown}
      onBlur={onCancel}
      className="bg-transparent border-b border-primary text-[10px] outline-none w-10 text-center"
    />
  )
}

let _groupCounter = 0

export function JointConfigDefaultsEditor({
  open,
  onOpenChange,
  groups: initialGroups,
  labels: initialLabels,
  onSave,
  isSaving,
  colors = JOINT_COLORS,
}: JointConfigDefaultsEditorProps) {
  const [groups, setGroups] = useState<JointGroup[]>(() => initialGroups.map((g) => ({ ...g, indices: [...g.indices] })))
  const [labels, setLabels] = useState<Record<string, string>>(() => ({ ...initialLabels }))
  const [editingJoint, setEditingJoint] = useState<number | null>(null)
  const [editingGroup, setEditingGroup] = useState<string | null>(null)
  const [assigningJoint, setAssigningJoint] = useState<number | null>(null)
  const [movingJoint, setMovingJoint] = useState<number | null>(null)
  const [editingIndex, setEditingIndex] = useState<number | null>(null)

  // Reset local state when dialog opens with new props
  useEffect(() => {
    if (open) {
      setGroups(initialGroups.map((g) => ({ ...g, indices: [...g.indices] })))
      setLabels({ ...initialLabels })
      setEditingJoint(null)
      setEditingGroup(null)
      setAssigningJoint(null)
      setMovingJoint(null)
      setEditingIndex(null)
    }
  }, [open, initialGroups, initialLabels])

  const allGroupedIndices = new Set(groups.flatMap((g) => g.indices))
  const allKnownIndices = Object.keys(labels).map(Number).sort((a, b) => a - b)
  const ungroupedIndices = allKnownIndices.filter((i) => !allGroupedIndices.has(i))

  const resolveLabel = useCallback(
    (idx: number) => labels[String(idx)] ?? OBSERVATION_LABELS[idx] ?? `Ch ${idx}`,
    [labels],
  )

  const handleEditJointLabel = (idx: number, label: string) => {
    setLabels((prev) => ({ ...prev, [String(idx)]: label }))
    setEditingJoint(null)
  }

  const handleEditGroupLabel = (groupId: string, label: string) => {
    setGroups((prev) => prev.map((g) => (g.id === groupId ? { ...g, label } : g)))
    setEditingGroup(null)
  }

  const handleDeleteGroup = (groupId: string) => {
    setGroups((prev) => prev.filter((g) => g.id !== groupId))
  }

  const handleAddGroup = () => {
    _groupCounter++
    const newGroup: JointGroup = {
      id: `custom-${Date.now()}-${_groupCounter}`,
      label: 'New Group',
      indices: [],
    }
    setGroups((prev) => [...prev, newGroup])
  }

  const handleAssignJoint = (jointIdx: number, groupId: string) => {
    setGroups((prev) =>
      prev.map((g) => {
        if (g.id === groupId) return { ...g, indices: [...g.indices, jointIdx] }
        return { ...g, indices: g.indices.filter((i) => i !== jointIdx) }
      }),
    )
    setAssigningJoint(null)
  }

  const handleUnassignJoint = (jointIdx: number) => {
    setGroups((prev) =>
      prev.map((g) => ({
        ...g,
        indices: g.indices.filter((i) => i !== jointIdx),
      })),
    )
  }

  const handleMoveJoint = (jointIdx: number, toGroupId: string) => {
    setGroups((prev) =>
      prev.map((g) => {
        if (g.id === toGroupId) return { ...g, indices: [...g.indices, jointIdx] }
        return { ...g, indices: g.indices.filter((i) => i !== jointIdx) }
      }),
    )
    setMovingJoint(null)
  }

  const handleEditIndex = (oldIdx: number, newIdx: number) => {
    const allIndices = new Set(groups.flatMap((g) => g.indices))
    const ungrouped = Object.keys(labels).map(Number).filter((i) => !allIndices.has(i))
    const allUsed = new Set([...allIndices, ...ungrouped])
    if (newIdx === oldIdx || allUsed.has(newIdx)) {
      setEditingIndex(null)
      return
    }
    setGroups((prev) =>
      prev.map((g) => ({
        ...g,
        indices: g.indices.map((i) => (i === oldIdx ? newIdx : i)),
      })),
    )
    setLabels((prev) => {
      const next = { ...prev }
      const label = next[String(oldIdx)]
      if (label !== undefined) {
        delete next[String(oldIdx)]
        next[String(newIdx)] = label
      }
      return next
    })
    setEditingIndex(null)
  }

  const handleSave = () => {
    onSave({ groups, labels })
  }

  const handleCancel = () => {
    onOpenChange(false)
  }

  const handleReset = () => {
    setGroups(JOINT_GROUPS.map((g) => ({ ...g, indices: [...g.indices] })))
    const builtInLabels: Record<string, string> = {}
    for (const [k, v] of Object.entries(OBSERVATION_LABELS)) {
      builtInLabels[String(k)] = v
    }
    setLabels(builtInLabels)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Settings className="h-5 w-5" />
            Joint Configuration Defaults
          </DialogTitle>
          <DialogDescription>
            Edit the default joint names and groupings applied to new datasets.
          </DialogDescription>
        </DialogHeader>

        <ScrollArea className="flex-1 min-h-0 pr-4">
          <div className="flex flex-col gap-4 py-2">
            {groups.map((group) => (
              <div key={group.id} className="rounded-lg border p-3">
                <div className="flex items-center justify-between mb-2">
                  {editingGroup === group.id ? (
                    <InlineEditField
                      value={group.label}
                      onCommit={(val) => handleEditGroupLabel(group.id, val)}
                      onCancel={() => setEditingGroup(null)}
                    />
                  ) : (
                    <span className="text-sm font-semibold">{group.label}</span>
                  )}
                  <div className="flex items-center gap-1">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6"
                      aria-label="Edit group label"
                      onClick={() => setEditingGroup(group.id)}
                    >
                      <Pencil className="h-3 w-3" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6 text-destructive"
                      aria-label="Delete group"
                      onClick={() => handleDeleteGroup(group.id)}
                    >
                      <Trash2 className="h-3 w-3" />
                    </Button>
                  </div>
                </div>

                <div className="flex flex-wrap gap-1.5">
                  {group.indices.map((idx) => (
                    <div
                      key={idx}
                      className="inline-flex items-center gap-1 pl-1.5 pr-0.5 py-0.5 text-xs rounded border border-current/20 group/chip"
                      style={{ color: getJointColor(idx, colors) }}
                    >
                      {editingIndex === idx ? (
                        <IndexEditField
                          value={idx}
                          onCommit={(val) => handleEditIndex(idx, val)}
                          onCancel={() => setEditingIndex(null)}
                        />
                      ) : (
                        <button
                          data-testid="joint-index"
                          className="text-[10px] font-mono bg-current/10 rounded px-1 cursor-pointer hover:bg-current/20"
                          aria-label="Edit joint index"
                          onClick={() => setEditingIndex(idx)}
                        >
                          {idx}
                        </button>
                      )}
                      <span
                        data-joint-color
                        className="w-2 h-2 rounded-full flex-shrink-0"
                        style={{ backgroundColor: getJointColor(idx, colors) }}
                      />
                      {editingJoint === idx ? (
                        <InlineEditField
                          value={resolveLabel(idx)}
                          onCommit={(val) => handleEditJointLabel(idx, val)}
                          onCancel={() => setEditingJoint(null)}
                        />
                      ) : (
                        <span>{resolveLabel(idx)}</span>
                      )}
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-4 w-4 opacity-0 group-hover/chip:opacity-100 transition-opacity"
                        aria-label="Edit joint label"
                        onClick={() => setEditingJoint(idx)}
                      >
                        <Pencil className="h-2.5 w-2.5" />
                      </Button>
                      {movingJoint === idx ? (
                        <div data-testid="group-picker" className="flex gap-1">
                          {groups
                            .filter((g) => g.id !== group.id)
                            .map((g) => (
                              <Button
                                key={g.id}
                                variant="outline"
                                size="sm"
                                className="h-5 text-[10px] px-1.5"
                                onClick={() => handleMoveJoint(idx, g.id)}
                              >
                                {g.label}
                              </Button>
                            ))}
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-5 text-[10px] px-1"
                            onClick={() => setMovingJoint(null)}
                          >
                            ✕
                          </Button>
                        </div>
                      ) : (
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-4 w-4 opacity-0 group-hover/chip:opacity-100 transition-opacity"
                          aria-label="Move to group"
                          onClick={() => setMovingJoint(idx)}
                        >
                          <ArrowRightLeft className="h-2.5 w-2.5" />
                        </Button>
                      )}
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-4 w-4 opacity-0 group-hover/chip:opacity-100 transition-opacity"
                        aria-label="Remove joint from group"
                        onClick={() => handleUnassignJoint(idx)}
                      >
                        <Trash2 className="h-2.5 w-2.5" />
                      </Button>
                    </div>
                  ))}
                  {group.indices.length === 0 && (
                    <span className="text-xs text-muted-foreground italic">No joints assigned</span>
                  )}
                </div>
              </div>
            ))}

            {ungroupedIndices.length > 0 && (
              <>
                <Separator />
                <div data-testid="ungrouped-joints" className="rounded-lg border border-dashed p-3">
                  <span className="text-sm font-semibold text-muted-foreground mb-2 block">
                    Ungrouped Joints
                  </span>
                  <div className="flex flex-wrap gap-1.5">
                    {ungroupedIndices.map((idx) => (
                      <div
                        key={idx}
                        className="inline-flex items-center gap-1 pl-1.5 pr-0.5 py-0.5 text-xs rounded border border-current/20 group/chip"
                        style={{ color: getJointColor(idx, colors) }}
                      >
                        {editingIndex === idx ? (
                          <IndexEditField
                            value={idx}
                            onCommit={(val) => handleEditIndex(idx, val)}
                            onCancel={() => setEditingIndex(null)}
                          />
                        ) : (
                          <button
                            data-testid="joint-index"
                            className="text-[10px] font-mono bg-current/10 rounded px-1 cursor-pointer hover:bg-current/20"
                            aria-label="Edit joint index"
                            onClick={() => setEditingIndex(idx)}
                          >
                            {idx}
                          </button>
                        )}
                        <span
                          data-joint-color
                          className="w-2 h-2 rounded-full flex-shrink-0"
                          style={{ backgroundColor: getJointColor(idx, colors) }}
                        />
                        {editingJoint === idx ? (
                          <InlineEditField
                            value={resolveLabel(idx)}
                            onCommit={(val) => handleEditJointLabel(idx, val)}
                            onCancel={() => setEditingJoint(null)}
                          />
                        ) : (
                          <span>{resolveLabel(idx)}</span>
                        )}
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-4 w-4 opacity-0 group-hover/chip:opacity-100 transition-opacity"
                          aria-label="Edit joint label"
                          onClick={() => setEditingJoint(idx)}
                        >
                          <Pencil className="h-2.5 w-2.5" />
                        </Button>
                        {assigningJoint === idx ? (
                          <div className="flex gap-1">
                            {groups.map((g) => (
                              <Button
                                key={g.id}
                                variant="outline"
                                size="sm"
                                className="h-5 text-[10px] px-1.5"
                                onClick={() => handleAssignJoint(idx, g.id)}
                              >
                                {g.label}
                              </Button>
                            ))}
                          </div>
                        ) : (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-4 w-4 opacity-0 group-hover/chip:opacity-100 transition-opacity"
                            aria-label="Assign to group"
                            onClick={() => setAssigningJoint(idx)}
                          >
                            <Plus className="h-2.5 w-2.5" />
                          </Button>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              </>
            )}
          </div>
        </ScrollArea>

        <DialogFooter className="flex items-center justify-between gap-2 pt-4">
          <Button variant="outline" size="sm" onClick={handleReset}>
            Reset
          </Button>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={handleAddGroup}>
              <Plus className="h-3.5 w-3.5 mr-1" />
              Add Group
            </Button>
            <Button variant="ghost" size="sm" onClick={handleCancel}>
              Cancel
            </Button>
            <Button size="sm" onClick={handleSave} disabled={isSaving}>
              {isSaving ? 'Saving…' : 'Save'}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
