/**
 * Viewer display settings store.
 *
 * Non-destructive display adjustments applied via CSS filters.
 * These settings affect only the visual rendering and do NOT modify
 * frame data or export output.
 */

import { create } from 'zustand';
import { devtools } from 'zustand/middleware';
import { useShallow } from 'zustand/react/shallow';

import type { ColorAdjustment } from '@/types/episode-edit';

interface ViewerSettingsState {
  /** Display-only color adjustments */
  displayAdjustment: Required<ColorAdjustment>;
  /** Whether viewer adjustments are active (non-default) */
  isActive: boolean;
}

interface ViewerSettingsActions {
  /** Update a single adjustment parameter */
  setAdjustment: (key: keyof ColorAdjustment, value: number) => void;
  /** Reset all display adjustments to defaults */
  resetAdjustments: () => void;
}

type ViewerSettingsStore = ViewerSettingsState & ViewerSettingsActions;

const DEFAULT_DISPLAY: Required<ColorAdjustment> = {
  brightness: 0,
  contrast: 0,
  saturation: 0,
  gamma: 1,
  hue: 0,
};

function isNonDefault(adj: Required<ColorAdjustment>): boolean {
  return (
    adj.brightness !== 0 ||
    adj.contrast !== 0 ||
    adj.saturation !== 0 ||
    adj.gamma !== 1 ||
    adj.hue !== 0
  );
}

export const useViewerSettingsStore = create<ViewerSettingsStore>()(
  devtools(
    (set) => ({
      displayAdjustment: { ...DEFAULT_DISPLAY },
      isActive: false,

      setAdjustment: (key, value) =>
        set((state) => {
          const next = { ...state.displayAdjustment, [key]: value };
          return { displayAdjustment: next, isActive: isNonDefault(next) };
        }),

      resetAdjustments: () =>
        set({ displayAdjustment: { ...DEFAULT_DISPLAY }, isActive: false }),
    }),
    { name: 'viewer-settings' },
  ),
);

/** Convenience hook returning display adjustment and actions. */
export function useViewerDisplay() {
  return useViewerSettingsStore(
    useShallow((s) => ({
      displayAdjustment: s.displayAdjustment,
      isActive: s.isActive,
      setAdjustment: s.setAdjustment,
      resetAdjustments: s.resetAdjustments,
    })),
  );
}
