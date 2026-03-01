/**
 * Subtask toolbar for adding, editing, and deleting segments.
 */

import { useState, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';
import { useSubtaskState, usePlaybackControls, useEpisodeStore } from '@/stores';
import { SUBTASK_COLORS, getNextSubtaskColor, generateSubtaskId } from '@/types/episode-edit';
import { cn } from '@/lib/utils';
import type { SubtaskSegment } from '@/types/episode-edit';
import { Plus, Trash2 } from 'lucide-react';

interface SubtaskToolbarProps {
  /** Currently selected segment ID */
  selectedSegmentId?: string | null;
  /** Callback when selection changes */
  onSelectionChange?: (id: string | null) => void;
  /** Additional CSS classes */
  className?: string;
}

/**
 * Toolbar for managing subtask segments.
 *
 * @example
 * ```tsx
 * <SubtaskToolbar
 *   selectedSegmentId={selectedId}
 *   onSelectionChange={setSelectedId}
 * />
 * ```
 */
export function SubtaskToolbar({
  selectedSegmentId,
  onSelectionChange,
  className,
}: SubtaskToolbarProps) {
  const { subtasks, addSubtask, updateSubtask, removeSubtask } = useSubtaskState();
  const { currentFrame } = usePlaybackControls();
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);

  const [isAddDialogOpen, setIsAddDialogOpen] = useState(false);
  const [editLabel, setEditLabel] = useState('');
  const [editStart, setEditStart] = useState('');
  const [editEnd, setEditEnd] = useState('');

  const totalFrames = currentEpisode?.meta.length ?? 100;
  const selectedSegment = subtasks.find((s) => s.id === selectedSegmentId);

  // Add a new segment at current frame position
  const handleAddSegment = useCallback(() => {
    const defaultEnd = Math.min(currentFrame + 100, totalFrames - 1);
    const newSegment: SubtaskSegment = {
      id: generateSubtaskId(),
      label: `Subtask ${subtasks.length + 1}`,
      frameRange: [currentFrame, defaultEnd],
      color: getNextSubtaskColor(subtasks),
      source: 'manual',
    };
    addSubtask(newSegment);
    onSelectionChange?.(newSegment.id);
    setIsAddDialogOpen(false);
  }, [currentFrame, totalFrames, subtasks, addSubtask, onSelectionChange]);

  // Open add dialog with custom values
  const handleOpenAddDialog = useCallback(() => {
    setEditLabel(`Subtask ${subtasks.length + 1}`);
    setEditStart(currentFrame.toString());
    setEditEnd(Math.min(currentFrame + 100, totalFrames - 1).toString());
    setIsAddDialogOpen(true);
  }, [currentFrame, totalFrames, subtasks.length]);

  // Add with custom values
  const handleAddCustomSegment = useCallback(() => {
    const start = parseInt(editStart, 10);
    const end = parseInt(editEnd, 10);

    if (isNaN(start) || isNaN(end) || start < 0 || end >= totalFrames || start >= end) {
      return;
    }

    const newSegment: SubtaskSegment = {
      id: generateSubtaskId(),
      label: editLabel || `Subtask ${subtasks.length + 1}`,
      frameRange: [start, end],
      color: getNextSubtaskColor(subtasks),
      source: 'manual',
    };
    addSubtask(newSegment);
    onSelectionChange?.(newSegment.id);
    setIsAddDialogOpen(false);
  }, [editLabel, editStart, editEnd, totalFrames, subtasks, addSubtask, onSelectionChange]);

  // Delete selected segment
  const handleDeleteSelected = useCallback(() => {
    if (selectedSegmentId) {
      removeSubtask(selectedSegmentId);
      onSelectionChange?.(null);
    }
  }, [selectedSegmentId, removeSubtask, onSelectionChange]);

  // Update segment label
  const handleLabelChange = useCallback(
    (label: string) => {
      if (selectedSegmentId) {
        updateSubtask(selectedSegmentId, { label });
      }
    },
    [selectedSegmentId, updateSubtask]
  );

  // Update segment color
  const handleColorChange = useCallback(
    (color: string) => {
      if (selectedSegmentId) {
        updateSubtask(selectedSegmentId, { color });
      }
    },
    [selectedSegmentId, updateSubtask]
  );

  if (!currentEpisode) {
    return null;
  }

  return (
    <div className={cn('flex items-center gap-2', className)}>
      {/* Add segment button */}
      <Dialog open={isAddDialogOpen} onOpenChange={setIsAddDialogOpen}>
        <DialogTrigger asChild>
          <Button size="sm" variant="outline" onClick={handleOpenAddDialog}>
            <Plus className="h-4 w-4 mr-1" />
            Add Segment
          </Button>
        </DialogTrigger>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add Subtask Segment</DialogTitle>
            <DialogDescription>
              Define a labeled frame range for this subtask.
            </DialogDescription>
          </DialogHeader>

          <div className="grid gap-4 py-4">
            <div className="grid grid-cols-4 items-center gap-4">
              <Label htmlFor="segment-label" className="text-right">
                Label
              </Label>
              <Input
                id="segment-label"
                value={editLabel}
                onChange={(e) => setEditLabel(e.target.value)}
                className="col-span-3"
                placeholder="e.g., Pick up object"
              />
            </div>
            <div className="grid grid-cols-4 items-center gap-4">
              <Label htmlFor="segment-start" className="text-right">
                Start Frame
              </Label>
              <Input
                id="segment-start"
                type="number"
                min={0}
                max={totalFrames - 1}
                value={editStart}
                onChange={(e) => setEditStart(e.target.value)}
                className="col-span-3"
              />
            </div>
            <div className="grid grid-cols-4 items-center gap-4">
              <Label htmlFor="segment-end" className="text-right">
                End Frame
              </Label>
              <Input
                id="segment-end"
                type="number"
                min={0}
                max={totalFrames - 1}
                value={editEnd}
                onChange={(e) => setEditEnd(e.target.value)}
                className="col-span-3"
              />
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setIsAddDialogOpen(false)}>
              Cancel
            </Button>
            <Button onClick={handleAddCustomSegment}>Add Segment</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Quick add at current frame */}
      <Button size="sm" variant="ghost" onClick={handleAddSegment} title="Quick add at current frame">
        <Plus className="h-4 w-4" />
      </Button>

      {/* Segment controls (when selected) */}
      {selectedSegment && (
        <>
          <div className="h-4 w-px bg-border" />

          {/* Edit label */}
          <Input
            value={selectedSegment.label}
            onChange={(e) => handleLabelChange(e.target.value)}
            className="h-8 w-32"
            placeholder="Label"
          />

          {/* Color picker */}
          <Popover>
            <PopoverTrigger asChild>
              <Button size="sm" variant="outline" className="w-8 p-0">
                <div
                  className="w-4 h-4 rounded"
                  style={{ backgroundColor: selectedSegment.color }}
                />
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-auto p-2">
              <div className="grid grid-cols-4 gap-1">
                {SUBTASK_COLORS.map((color) => (
                  <button
                    key={color}
                    className={cn(
                      'w-6 h-6 rounded transition-transform hover:scale-110',
                      selectedSegment.color === color && 'ring-2 ring-ring ring-offset-2'
                    )}
                    style={{ backgroundColor: color }}
                    onClick={() => handleColorChange(color)}
                  />
                ))}
              </div>
            </PopoverContent>
          </Popover>

          {/* Delete */}
          <Button
            size="sm"
            variant="ghost"
            className="text-destructive hover:text-destructive"
            onClick={handleDeleteSelected}
          >
            <Trash2 className="h-4 w-4" />
          </Button>

          {/* Segment info */}
          <span className="text-xs text-muted-foreground">
            {selectedSegment.frameRange[0]} - {selectedSegment.frameRange[1]}
          </span>
        </>
      )}
    </div>
  );
}
