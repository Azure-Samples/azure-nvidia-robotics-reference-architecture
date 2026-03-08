import { ArrowDown, ArrowUp, ListChecks, Trash2 } from 'lucide-react';

import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { usePlaybackControls, useSubtaskState } from '@/stores';

interface SubtaskListProps {
  selectedSubtaskId?: string | null;
  onSelectionChange?: (id: string | null) => void;
  className?: string;
}

export function SubtaskList({
  selectedSubtaskId,
  onSelectionChange,
  className,
}: SubtaskListProps) {
  const { subtasks, updateSubtask, removeSubtask, reorderSubtasks } = useSubtaskState();
  const { setCurrentFrame } = usePlaybackControls();

  if (subtasks.length === 0) {
    return (
      <div className={cn('rounded-lg border border-dashed p-4 text-sm text-muted-foreground', className)}>
        <div className="flex items-center gap-2 font-medium text-foreground">
          <ListChecks className="h-4 w-4" />
          Subtasks
        </div>
        <p className="mt-2 text-xs">
          Drag on the trajectory graph to select a frame range, then right click to create a subtask.
        </p>
      </div>
    );
  }

  return (
    <div className={cn('rounded-lg border p-3', className)}>
      <div className="mb-3 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <ListChecks className="h-4 w-4" />
          <h4 className="text-sm font-medium">Subtasks</h4>
        </div>
        {selectedSubtaskId && (
          <Button size="sm" variant="ghost" onClick={() => onSelectionChange?.(null)}>
            Clear
          </Button>
        )}
      </div>
      <div className="flex flex-col gap-2">
        {subtasks.map((segment, index) => {
          const isSelected = segment.id === selectedSubtaskId;

          return (
            <div
              key={segment.id}
              className={cn(
                'rounded-md border p-2 transition-colors',
                isSelected ? 'border-primary bg-primary/5' : 'border-border bg-background',
              )}
            >
              <div className="flex items-start justify-between gap-2">
                <button
                  type="button"
                  className="flex min-w-0 flex-1 items-start gap-2 text-left"
                  onClick={() => {
                    setCurrentFrame(segment.frameRange[0]);
                    onSelectionChange?.(segment.id);
                  }}
                >
                  <span
                    className="mt-1 h-3 w-3 shrink-0 rounded-sm"
                    style={{ backgroundColor: segment.color }}
                  />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="truncate text-sm font-medium">{segment.label}</span>
                      {isSelected && (
                        <span className="rounded bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary">
                          Active
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-muted-foreground">
                      Frames {segment.frameRange[0]} to {segment.frameRange[1]}
                    </p>
                  </div>
                </button>
                <div className="flex shrink-0 items-center gap-1">
                  <Button
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7"
                    disabled={index === 0}
                    onClick={() => reorderSubtasks(index, index - 1)}
                    aria-label={`Move ${segment.label} up`}
                  >
                    <ArrowUp className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7"
                    disabled={index === subtasks.length - 1}
                    onClick={() => reorderSubtasks(index, index + 1)}
                    aria-label={`Move ${segment.label} down`}
                  >
                    <ArrowDown className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7 text-destructive hover:text-destructive"
                    onClick={() => {
                      removeSubtask(segment.id);
                      if (isSelected) {
                        onSelectionChange?.(null);
                      }
                    }}
                    aria-label={`Delete ${segment.label}`}
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>
              <div className="mt-2 flex items-center gap-2">
                <Input
                  value={segment.label}
                  onChange={(event) => updateSubtask(segment.id, { label: event.target.value })}
                  className="h-8"
                  aria-label={`${segment.label} label`}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
