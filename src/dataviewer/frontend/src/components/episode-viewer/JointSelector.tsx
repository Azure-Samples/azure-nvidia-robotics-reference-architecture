/**
 * Joint selector for trajectory visualization.
 */

import { useState, useRef, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { ChevronDown, Check } from 'lucide-react';
import { cn } from '@/lib/utils';

// Labels for bimanual task-space observations
const OBSERVATION_LABELS: Record<number, string> = {
  0: 'Right X',
  1: 'Right Y',
  2: 'Right Z',
  3: 'Right Qx',
  4: 'Right Qy',
  5: 'Right Qz',
  6: 'Right Qw',
  7: 'Right Gripper',
  8: 'Left X',
  9: 'Left Y',
  10: 'Left Z',
  11: 'Left Qx',
  12: 'Left Qy',
  13: 'Left Qz',
  14: 'Left Qw',
  15: 'Left Gripper',
};

interface JointSelectorProps {
  /** Total number of joints available */
  jointCount: number;
  /** Currently selected joint indices */
  selectedJoints: number[];
  /** Callback when selection changes */
  onSelectJoints: (joints: number[]) => void;
  /** Color palette for joints */
  colors: string[];
}

/**
 * Multi-select dropdown for choosing which joints to display.
 */
export function JointSelector({
  jointCount,
  selectedJoints,
  onSelectJoints,
  colors,
}: JointSelectorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(e.target as Node)
      ) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const toggleJoint = (jointIdx: number) => {
    if (selectedJoints.includes(jointIdx)) {
      onSelectJoints(selectedJoints.filter((j) => j !== jointIdx));
    } else {
      onSelectJoints([...selectedJoints, jointIdx].sort((a, b) => a - b));
    }
  };

  const selectAll = () => {
    onSelectJoints(Array.from({ length: jointCount }, (_, i) => i));
  };

  const clearAll = () => {
    onSelectJoints([]);
  };

  if (jointCount === 0) {
    return (
      <span className="text-sm text-muted-foreground">No joints available</span>
    );
  }

  return (
    <div className="relative" ref={dropdownRef}>
      <Button
        variant="outline"
        size="sm"
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2"
      >
        <span>
          {selectedJoints.length} / {jointCount} Joints
        </span>
        <ChevronDown
          className={cn(
            'h-4 w-4 transition-transform',
            isOpen && 'rotate-180'
          )}
        />
      </Button>

      {isOpen && (
        <div className="absolute top-full left-0 mt-1 z-50 min-w-[200px] bg-popover border rounded-md shadow-lg">
          {/* Quick actions */}
          <div className="flex gap-2 p-2 border-b">
            <button
              onClick={selectAll}
              className="text-xs text-primary hover:underline"
            >
              Select All
            </button>
            <span className="text-muted-foreground">|</span>
            <button
              onClick={clearAll}
              className="text-xs text-primary hover:underline"
            >
              Clear
            </button>
          </div>

          {/* Joint list */}
          <div className="max-h-48 overflow-y-auto">
            {Array.from({ length: jointCount }, (_, idx) => (
              <button
                key={idx}
                onClick={() => toggleJoint(idx)}
                className="w-full px-3 py-2 flex items-center gap-2 hover:bg-accent transition-colors"
              >
                <div
                  className="w-3 h-3 rounded-full"
                  style={{ backgroundColor: colors[idx % colors.length] }}
                />
                <span className="flex-1 text-left text-sm">
                  {OBSERVATION_LABELS[idx] || `Channel ${idx}`}
                </span>
                {selectedJoints.includes(idx) && (
                  <Check className="h-4 w-4 text-primary" />
                )}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
