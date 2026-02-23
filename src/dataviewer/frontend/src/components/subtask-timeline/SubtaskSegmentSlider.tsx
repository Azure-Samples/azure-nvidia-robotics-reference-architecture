/**
 * Subtask segment slider with dual thumbs for range editing.
 *
 * Uses Radix UI Slider for accessible range selection.
 */

import { useCallback } from 'react';
import * as Slider from '@radix-ui/react-slider';
import { cn } from '@/lib/utils';
import type { SubtaskSegment } from '@/types/episode-edit';

interface SubtaskSegmentSliderProps {
  /** The segment to display/edit */
  segment: SubtaskSegment;
  /** Total frames in the episode */
  totalFrames: number;
  /** Callback when range changes */
  onRangeChange: (range: [number, number]) => void;
  /** Callback when segment is clicked */
  onClick?: () => void;
  /** Additional CSS classes */
  className?: string;
}

/**
 * Dual-thumb slider for editing a subtask segment's frame range.
 *
 * @example
 * ```tsx
 * <SubtaskSegmentSlider
 *   segment={segment}
 *   totalFrames={1000}
 *   onRangeChange={(range) => updateSegment(segment.id, { frameRange: range })}
 * />
 * ```
 */
export function SubtaskSegmentSlider({
  segment,
  totalFrames,
  onRangeChange,
  onClick,
  className,
}: SubtaskSegmentSliderProps) {
  const handleValueChange = useCallback(
    (values: number[]) => {
      if (values.length === 2) {
        onRangeChange([values[0], values[1]]);
      }
    },
    [onRangeChange]
  );

  return (
    <Slider.Root
      className={cn(
        'absolute top-1 bottom-1 touch-none select-none',
        className
      )}
      style={{
        left: 0,
        right: 0,
      }}
      value={[segment.frameRange[0], segment.frameRange[1]]}
      onValueChange={handleValueChange}
      min={0}
      max={totalFrames}
      step={1}
      minStepsBetweenThumbs={1}
    >
      <Slider.Track className="relative h-full w-full">
        <Slider.Range
          className="absolute h-full rounded-sm cursor-pointer transition-opacity hover:opacity-90"
          style={{ backgroundColor: segment.color }}
          onClick={onClick}
        />
      </Slider.Track>

      {/* Start thumb */}
      <Slider.Thumb
        className={cn(
          'block h-4 w-2 rounded-sm bg-background border-2 shadow-sm',
          'focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2',
          'hover:scale-110 transition-transform cursor-ew-resize'
        )}
        style={{ borderColor: segment.color }}
        aria-label={`${segment.label} start frame`}
      />

      {/* End thumb */}
      <Slider.Thumb
        className={cn(
          'block h-4 w-2 rounded-sm bg-background border-2 shadow-sm',
          'focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2',
          'hover:scale-110 transition-transform cursor-ew-resize'
        )}
        style={{ borderColor: segment.color }}
        aria-label={`${segment.label} end frame`}
      />
    </Slider.Root>
  );
}
