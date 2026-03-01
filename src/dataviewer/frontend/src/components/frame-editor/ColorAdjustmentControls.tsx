/**
 * Color adjustment controls for image processing.
 *
 * Provides sliders for brightness, contrast, saturation, gamma, and hue,
 * plus preset color filter buttons.
 */

import { useState, useCallback, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { useTransformState } from '@/stores';
import { cn } from '@/lib/utils';
import type { ColorAdjustment, ColorFilterPreset } from '@/types/episode-edit';
import { RotateCcw, Sun, Contrast, Droplets, Palette, SunDim } from 'lucide-react';

interface ColorAdjustmentControlsProps {
  /** Camera name for per-camera transforms */
  cameraName?: string;
  /** Additional CSS classes */
  className?: string;
}

/** Default color adjustment values */
const DEFAULT_ADJUSTMENT: Required<ColorAdjustment> = {
  brightness: 0,
  contrast: 0,
  saturation: 0,
  gamma: 1,
  hue: 0,
};

/** Available color filter presets */
const FILTER_PRESETS: { value: ColorFilterPreset; label: string }[] = [
  { value: 'none', label: 'None' },
  { value: 'grayscale', label: 'Grayscale' },
  { value: 'sepia', label: 'Sepia' },
  { value: 'invert', label: 'Invert' },
  { value: 'warm', label: 'Warm' },
  { value: 'cool', label: 'Cool' },
];

interface SliderControlProps {
  label: string;
  value: number;
  onChange: (value: number) => void;
  min: number;
  max: number;
  step: number;
  icon: React.ReactNode;
  formatValue?: (value: number) => string;
}

/** Individual slider control for an adjustment parameter */
function SliderControl({
  label,
  value,
  onChange,
  min,
  max,
  step,
  icon,
  formatValue = (v) => v.toString(),
}: SliderControlProps) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <Label className="flex items-center gap-1.5 text-xs text-muted-foreground">
          {icon}
          {label}
        </Label>
        <span className="text-xs font-mono text-muted-foreground w-12 text-right">
          {formatValue(value)}
        </span>
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        className="w-full h-2 bg-muted rounded-lg appearance-none cursor-pointer
          [&::-webkit-slider-thumb]:appearance-none
          [&::-webkit-slider-thumb]:w-4
          [&::-webkit-slider-thumb]:h-4
          [&::-webkit-slider-thumb]:rounded-full
          [&::-webkit-slider-thumb]:bg-primary
          [&::-webkit-slider-thumb]:cursor-pointer
          [&::-webkit-slider-thumb]:transition-all
          [&::-webkit-slider-thumb]:hover:scale-110
          [&::-moz-range-thumb]:w-4
          [&::-moz-range-thumb]:h-4
          [&::-moz-range-thumb]:rounded-full
          [&::-moz-range-thumb]:bg-primary
          [&::-moz-range-thumb]:border-0
          [&::-moz-range-thumb]:cursor-pointer"
      />
    </div>
  );
}

/**
 * Color adjustment controls for frame editing.
 *
 * @example
 * ```tsx
 * <ColorAdjustmentControls cameraName="top" />
 * ```
 */
export function ColorAdjustmentControls({
  cameraName,
  className,
}: ColorAdjustmentControlsProps) {
  const { globalTransform, setGlobalTransform, setCameraTransform } =
    useTransformState();

  // Get current color settings from store
  const currentAdjustment = cameraName
    ? undefined // Would need to get from cameraTransforms
    : globalTransform?.colorAdjustment;
  const currentFilter = cameraName
    ? undefined
    : globalTransform?.colorFilter;

  // Local state for adjustments (with defaults merged in)
  const [adjustment, setAdjustment] = useState<Required<ColorAdjustment>>(() => ({
    ...DEFAULT_ADJUSTMENT,
    ...currentAdjustment,
  }));
  const [filter, setFilter] = useState<ColorFilterPreset>(currentFilter ?? 'none');

  // Sync local state with store when store changes
  useEffect(() => {
    if (currentAdjustment) {
      setAdjustment({ ...DEFAULT_ADJUSTMENT, ...currentAdjustment });
    }
  }, [currentAdjustment]);

  useEffect(() => {
    setFilter(currentFilter ?? 'none');
  }, [currentFilter]);

  // Update a single adjustment value
  const updateAdjustment = useCallback(
    (key: keyof ColorAdjustment, value: number) => {
      setAdjustment((prev) => ({ ...prev, [key]: value }));
    },
    []
  );

  // Apply adjustments to store
  const handleApply = useCallback(() => {
    // Only include non-default values
    const colorAdjustment: ColorAdjustment = {};
    if (adjustment.brightness !== 0) colorAdjustment.brightness = adjustment.brightness;
    if (adjustment.contrast !== 0) colorAdjustment.contrast = adjustment.contrast;
    if (adjustment.saturation !== 0) colorAdjustment.saturation = adjustment.saturation;
    if (adjustment.gamma !== 1) colorAdjustment.gamma = adjustment.gamma;
    if (adjustment.hue !== 0) colorAdjustment.hue = adjustment.hue;

    const colorFilter = filter !== 'none' ? filter : undefined;

    if (cameraName) {
      setCameraTransform(cameraName, {
        colorAdjustment: Object.keys(colorAdjustment).length > 0 ? colorAdjustment : undefined,
        colorFilter,
      });
    } else {
      setGlobalTransform({
        ...globalTransform,
        colorAdjustment: Object.keys(colorAdjustment).length > 0 ? colorAdjustment : undefined,
        colorFilter,
      });
    }
  }, [
    adjustment,
    filter,
    cameraName,
    globalTransform,
    setGlobalTransform,
    setCameraTransform,
  ]);

  // Reset to defaults
  const handleReset = useCallback(() => {
    setAdjustment(DEFAULT_ADJUSTMENT);
    setFilter('none');

    if (cameraName) {
      setCameraTransform(cameraName, {
        ...globalTransform,
        colorAdjustment: undefined,
        colorFilter: undefined,
      });
    } else {
      setGlobalTransform({
        ...globalTransform,
        colorAdjustment: undefined,
        colorFilter: undefined,
      });
    }
  }, [cameraName, globalTransform, setGlobalTransform, setCameraTransform]);

  // Check if any adjustments have been made
  const hasChanges =
    adjustment.brightness !== 0 ||
    adjustment.contrast !== 0 ||
    adjustment.saturation !== 0 ||
    adjustment.gamma !== 1 ||
    adjustment.hue !== 0 ||
    filter !== 'none';

  return (
    <div className={cn('flex flex-col gap-4', className)}>
      {/* Adjustment sliders */}
      <div className="space-y-4">
        <Label className="text-sm font-medium">Color Adjustments</Label>

        <div className="space-y-3">
          <SliderControl
            label="Brightness"
            value={adjustment.brightness}
            onChange={(v) => updateAdjustment('brightness', v)}
            min={-1}
            max={1}
            step={0.05}
            icon={<Sun className="h-3 w-3" />}
            formatValue={(v) => `${v > 0 ? '+' : ''}${Math.round(v * 100)}%`}
          />

          <SliderControl
            label="Contrast"
            value={adjustment.contrast}
            onChange={(v) => updateAdjustment('contrast', v)}
            min={-1}
            max={1}
            step={0.05}
            icon={<Contrast className="h-3 w-3" />}
            formatValue={(v) => `${v > 0 ? '+' : ''}${Math.round(v * 100)}%`}
          />

          <SliderControl
            label="Saturation"
            value={adjustment.saturation}
            onChange={(v) => updateAdjustment('saturation', v)}
            min={-1}
            max={1}
            step={0.05}
            icon={<Droplets className="h-3 w-3" />}
            formatValue={(v) => `${v > 0 ? '+' : ''}${Math.round(v * 100)}%`}
          />

          <SliderControl
            label="Gamma"
            value={adjustment.gamma}
            onChange={(v) => updateAdjustment('gamma', v)}
            min={0.1}
            max={3}
            step={0.1}
            icon={<SunDim className="h-3 w-3" />}
            formatValue={(v) => v.toFixed(1)}
          />

          <SliderControl
            label="Hue"
            value={adjustment.hue}
            onChange={(v) => updateAdjustment('hue', v)}
            min={-180}
            max={180}
            step={5}
            icon={<Palette className="h-3 w-3" />}
            formatValue={(v) => `${v > 0 ? '+' : ''}${Math.round(v)}°`}
          />
        </div>
      </div>

      {/* Filter presets */}
      <div className="space-y-2">
        <Label className="text-sm font-medium">Color Filters</Label>
        <div className="flex flex-wrap gap-1">
          {FILTER_PRESETS.map((preset) => (
            <Button
              key={preset.value}
              variant={filter === preset.value ? 'default' : 'outline'}
              size="sm"
              className="h-7 text-xs px-2"
              onClick={() => setFilter(preset.value)}
            >
              {preset.label}
            </Button>
          ))}
        </div>
      </div>

      {/* Action buttons */}
      <div className="flex gap-2">
        <Button size="sm" onClick={handleApply} className="flex-1">
          Apply Colors
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={handleReset}
          disabled={!hasChanges}
        >
          <RotateCcw className="h-4 w-4 mr-1" />
          Reset
        </Button>
      </div>

      {/* Current color info */}
      {(globalTransform?.colorAdjustment || globalTransform?.colorFilter) && (
        <div className="text-xs text-muted-foreground p-2 bg-muted rounded">
          <div className="font-medium mb-1">Active Color Settings:</div>
          {globalTransform.colorAdjustment && (
            <div className="space-y-0.5">
              {globalTransform.colorAdjustment.brightness !== undefined && (
                <div>Brightness: {Math.round(globalTransform.colorAdjustment.brightness * 100)}%</div>
              )}
              {globalTransform.colorAdjustment.contrast !== undefined && (
                <div>Contrast: {Math.round(globalTransform.colorAdjustment.contrast * 100)}%</div>
              )}
              {globalTransform.colorAdjustment.saturation !== undefined && (
                <div>Saturation: {Math.round(globalTransform.colorAdjustment.saturation * 100)}%</div>
              )}
              {globalTransform.colorAdjustment.gamma !== undefined && (
                <div>Gamma: {globalTransform.colorAdjustment.gamma.toFixed(1)}</div>
              )}
              {globalTransform.colorAdjustment.hue !== undefined && (
                <div>Hue: {Math.round(globalTransform.colorAdjustment.hue)}°</div>
              )}
            </div>
          )}
          {globalTransform.colorFilter && globalTransform.colorFilter !== 'none' && (
            <div>Filter: {globalTransform.colorFilter}</div>
          )}
        </div>
      )}
    </div>
  );
}
