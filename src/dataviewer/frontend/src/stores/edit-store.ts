/**
 * Edit store for managing episode editing state.
 *
 * Tracks non-destructive edit operations including:
 * - Image transforms (crop/resize)
 * - Frame removal
 * - Sub-task segmentation
 */

import { create } from 'zustand';
import { devtools } from 'zustand/middleware';
import { useShallow } from 'zustand/react/shallow';

import { loadPersistedEditDraft, persistEditDraft } from '@/lib/edit-draft-storage';
import type {
  EpisodeEditOperations,
  FrameInsertion,
  ImageTransform,
  SubtaskSegment,
  TrajectoryAdjustment,
} from '@/types/episode-edit';
import {
  createDefaultSubtask,
  validateSegments,
} from '@/types/episode-edit';

interface EditState {
  /** Current episode being edited */
  datasetId: string | null;
  episodeIndex: number | null;

  /** Global transform applied to all cameras */
  globalTransform: ImageTransform | null;
  /** Per-camera transform overrides */
  cameraTransforms: Record<string, ImageTransform>;
  /** Set of frame indices marked for removal */
  removedFrames: Set<number>;
  /** Map of inserted frames keyed by afterFrameIndex */
  insertedFrames: Map<number, FrameInsertion>;
  /** Sub-task segments */
  subtasks: SubtaskSegment[];
  /** Trajectory adjustments per frame */
  trajectoryAdjustments: Map<number, TrajectoryAdjustment>;

  /** Original state for dirty checking */
  originalState: {
    globalTransform: ImageTransform | null;
    cameraTransforms: Record<string, ImageTransform>;
    removedFrames: Set<number>;
    insertedFrames: Map<number, FrameInsertion>;
    subtasks: SubtaskSegment[];
    trajectoryAdjustments: Map<number, TrajectoryAdjustment>;
  } | null;

  /** Whether there are unsaved changes */
  isDirty: boolean;
  /** Validation errors */
  validationErrors: string[];
  /** Saved draft operations keyed by dataset and episode */
  savedEpisodeDrafts: Record<string, EpisodeEditOperations>;
}

interface EditActions {
  /** Initialize edit state for an episode */
  initializeEdit: (datasetId: string, episodeIndex: number) => void;
  /** Load existing edit operations */
  loadEditOperations: (ops: EpisodeEditOperations) => void;

  // Transform actions
  /** Set the global transform */
  setGlobalTransform: (transform: ImageTransform | null) => void;
  /** Set a camera-specific transform */
  setCameraTransform: (camera: string, transform: ImageTransform | null) => void;
  /** Clear all transforms */
  clearTransforms: () => void;

  // Frame removal actions
  /** Toggle frame removal status */
  toggleFrameRemoval: (frameIndex: number) => void;
  /** Add a range of frames to removal */
  addFrameRange: (start: number, end: number) => void;
  /** Add frames at a configurable frequency (every Nth frame) */
  addFramesByFrequency: (start: number, end: number, frequency: number) => void;
  /** Remove a range of frames from removal */
  removeFrameRange: (start: number, end: number) => void;
  /** Clear all removed frames */
  clearRemovedFrames: () => void;

  // Frame insertion actions
  /** Insert a frame after the specified index */
  insertFrame: (afterFrameIndex: number, factor?: number) => void;
  /** Remove an inserted frame */
  removeInsertedFrame: (afterFrameIndex: number) => void;
  /** Clear all inserted frames */
  clearInsertedFrames: () => void;

  // Subtask actions
  /** Add a new subtask segment */
  addSubtask: (segment: SubtaskSegment) => void;
  /** Add a subtask from frame range */
  addSubtaskFromRange: (start: number, end: number) => void;
  /** Update a subtask segment */
  updateSubtask: (id: string, update: Partial<SubtaskSegment>) => void;
  /** Remove a subtask segment */
  removeSubtask: (id: string) => void;
  /** Reorder subtasks */
  reorderSubtasks: (fromIndex: number, toIndex: number) => void;

  // Trajectory adjustment actions
  /** Set a trajectory adjustment for a specific frame */
  setTrajectoryAdjustment: (frameIndex: number, adjustment: Omit<TrajectoryAdjustment, 'frameIndex'>) => void;
  /** Remove a trajectory adjustment for a specific frame */
  removeTrajectoryAdjustment: (frameIndex: number) => void;
  /** Get trajectory adjustment for a specific frame */
  getTrajectoryAdjustment: (frameIndex: number) => TrajectoryAdjustment | undefined;
  /** Clear all trajectory adjustments */
  clearTrajectoryAdjustments: () => void;

  // State management
  /** Get the current edit operations for export */
  getEditOperations: () => EpisodeEditOperations | null;
  /** Commit the current episode edits as the saved draft baseline */
  saveEpisodeDraft: () => void;
  /** Mark current state as saved */
  markSaved: () => void;
  /** Reset to original state */
  resetEdits: () => void;
  /** Clear all edit state */
  clear: () => void;
}

type EditStore = EditState & EditActions;

const initialState: EditState = {
  datasetId: null,
  episodeIndex: null,
  globalTransform: null,
  cameraTransforms: {},
  removedFrames: new Set(),
  insertedFrames: new Map(),
  subtasks: [],
  trajectoryAdjustments: new Map(),
  originalState: null,
  isDirty: false,
  validationErrors: [],
  savedEpisodeDrafts: {},
};

function getEpisodeDraftKey(datasetId: string, episodeIndex: number) {
  return `${datasetId}:${episodeIndex}`;
}

function buildOriginalState(state: Pick<EditState, 'globalTransform' | 'cameraTransforms' | 'removedFrames' | 'insertedFrames' | 'subtasks' | 'trajectoryAdjustments'>) {
  return {
    globalTransform: state.globalTransform,
    cameraTransforms: structuredClone(state.cameraTransforms),
    removedFrames: new Set(state.removedFrames),
    insertedFrames: new Map(state.insertedFrames),
    subtasks: structuredClone(state.subtasks),
    trajectoryAdjustments: new Map(state.trajectoryAdjustments),
  };
}

function buildEditOperations(state: EditState): EpisodeEditOperations | null {
  if (!state.datasetId || state.episodeIndex === null) {
    return null;
  }

  return {
    datasetId: state.datasetId,
    episodeIndex: state.episodeIndex,
    globalTransform: state.globalTransform ?? undefined,
    cameraTransforms:
      Object.keys(state.cameraTransforms).length > 0
        ? state.cameraTransforms
        : undefined,
    removedFrames:
      state.removedFrames.size > 0
        ? Array.from(state.removedFrames).sort((a, b) => a - b)
        : undefined,
    insertedFrames:
      state.insertedFrames.size > 0
        ? Array.from(state.insertedFrames.values())
            .sort((a, b) => a.afterFrameIndex - b.afterFrameIndex)
        : undefined,
    subtasks: state.subtasks.length > 0 ? state.subtasks : undefined,
    trajectoryAdjustments:
      state.trajectoryAdjustments.size > 0
        ? Array.from(state.trajectoryAdjustments.values())
        : undefined,
  };
}

function hasEditContent(operations: EpisodeEditOperations) {
  return !!(
    operations.globalTransform ||
    operations.cameraTransforms ||
    operations.removedFrames ||
    operations.insertedFrames ||
    operations.subtasks ||
    operations.trajectoryAdjustments
  );
}

/** Check if state has changed from original */
function computeDirty(state: EditState): boolean {
  if (!state.originalState) return false;

  // Check global transform
  if (JSON.stringify(state.globalTransform) !== JSON.stringify(state.originalState.globalTransform)) {
    return true;
  }

  // Check camera transforms
  if (JSON.stringify(state.cameraTransforms) !== JSON.stringify(state.originalState.cameraTransforms)) {
    return true;
  }

  // Check removed frames
  if (state.removedFrames.size !== state.originalState.removedFrames.size) {
    return true;
  }
  for (const frame of state.removedFrames) {
    if (!state.originalState.removedFrames.has(frame)) {
      return true;
    }
  }

  // Check inserted frames
  if (state.insertedFrames.size !== state.originalState.insertedFrames.size) {
    return true;
  }
  for (const [afterIdx, insertion] of state.insertedFrames) {
    const origInsertion = state.originalState.insertedFrames.get(afterIdx);
    if (!origInsertion ||
        insertion.interpolationFactor !== origInsertion.interpolationFactor) {
      return true;
    }
  }

  // Check subtasks
  if (JSON.stringify(state.subtasks) !== JSON.stringify(state.originalState.subtasks)) {
    return true;
  }

  // Check trajectory adjustments
  if (state.trajectoryAdjustments.size !== state.originalState.trajectoryAdjustments.size) {
    return true;
  }
  for (const [frame, adj] of state.trajectoryAdjustments) {
    const origAdj = state.originalState.trajectoryAdjustments.get(frame);
    if (!origAdj || JSON.stringify(adj) !== JSON.stringify(origAdj)) {
      return true;
    }
  }

  return false;
}

/**
 * Compute effective index accounting for insertions and removals.
 *
 * @param originalIndex - Index in original frame space
 * @param insertedFrames - Map of inserted frames
 * @param removedFrames - Set of removed frames
 * @returns Effective index in the edited frame space
 */
export function getEffectiveIndex(
  originalIndex: number,
  insertedFrames: Map<number, FrameInsertion>,
  removedFrames: Set<number>,
): number {
  let offset = 0;

  // Count insertions before this index
  for (const afterIdx of insertedFrames.keys()) {
    if (afterIdx < originalIndex && !removedFrames.has(afterIdx)) {
      offset++;
    }
  }

  // Count removals before this index
  for (const removedIdx of removedFrames) {
    if (removedIdx < originalIndex) {
      offset--;
    }
  }

  return originalIndex + offset;
}

/**
 * Convert effective index back to original frame index.
 *
 * @param effectiveIndex - Index in edited frame space
 * @param insertedFrames - Map of inserted frames
 * @param removedFrames - Set of removed frames
 * @returns Original frame index, or null if position is an inserted frame
 */
export function getOriginalIndex(
  effectiveIndex: number,
  insertedFrames: Map<number, FrameInsertion>,
  removedFrames: Set<number>,
): number | null {
  // Build sorted list of effective insertion positions
  const insertionPositions: number[] = [];
  for (const afterIdx of insertedFrames.keys()) {
    if (!removedFrames.has(afterIdx)) {
      const effectivePos = getEffectiveIndex(afterIdx, insertedFrames, removedFrames) + 1;
      insertionPositions.push(effectivePos);
    }
  }
  insertionPositions.sort((a, b) => a - b);

  // Check if effectiveIndex is an inserted frame
  if (insertionPositions.includes(effectiveIndex)) {
    return null; // This is an inserted frame, no original index
  }

  // Count how many insertions are before this position
  let insertionsBefore = 0;
  for (const pos of insertionPositions) {
    if (pos < effectiveIndex) insertionsBefore++;
  }

  // Count removals to adjust
  const candidateOriginal = effectiveIndex - insertionsBefore;
  let removedBefore = 0;
  const sortedRemovals = Array.from(removedFrames).sort((a, b) => a - b);
  for (const removedIdx of sortedRemovals) {
    if (removedIdx <= candidateOriginal + removedBefore) {
      removedBefore++;
    }
  }

  return candidateOriginal + removedBefore;
}

/**
 * Get the total effective frame count after edits.
 *
 * @param originalCount - Original frame count
 * @param insertedFrames - Map of inserted frames
 * @param removedFrames - Set of removed frames
 * @returns Effective frame count
 */
export function getEffectiveFrameCount(
  originalCount: number,
  insertedFrames: Map<number, FrameInsertion>,
  removedFrames: Set<number>,
): number {
  // Valid insertions (not after removed frames)
  let validInsertions = 0;
  for (const afterIdx of insertedFrames.keys()) {
    if (!removedFrames.has(afterIdx) && afterIdx < originalCount - 1) {
      validInsertions++;
    }
  }

  return originalCount - removedFrames.size + validInsertions;
}

/**
 * Zustand store for episode edit state management.
 *
 * @example
 * ```tsx
 * const {
 *   globalTransform,
 *   setGlobalTransform,
 *   removedFrames,
 *   toggleFrameRemoval,
 *   subtasks,
 *   addSubtaskFromRange,
 * } = useEditStore();
 *
 * // Set a crop transform
 * setGlobalTransform({ crop: { x: 10, y: 10, width: 200, height: 150 } });
 *
 * // Mark a frame for removal
 * toggleFrameRemoval(42);
 *
 * // Add a subtask segment
 * addSubtaskFromRange(100, 200);
 * ```
 */
export const useEditStore = create<EditStore>()(
  devtools(
    (set, get) => ({
      ...initialState,



      initializeEdit: (datasetId, episodeIndex) => {
        const draftKey = getEpisodeDraftKey(datasetId, episodeIndex);
        const savedDraft = get().savedEpisodeDrafts[draftKey];

        if (savedDraft) {
          get().loadEditOperations(savedDraft);
          return;
        }

        const newState = {
          datasetId,
          episodeIndex,
          globalTransform: null,
          cameraTransforms: {},
          removedFrames: new Set<number>(),
          insertedFrames: new Map<number, FrameInsertion>(),
          subtasks: [],
          trajectoryAdjustments: new Map<number, TrajectoryAdjustment>(),
        };

        set(
          {
            ...newState,
            originalState: buildOriginalState(newState),
            isDirty: false,
            validationErrors: [],
          },
          false,
          'initializeEdit'
        );

        void loadPersistedEditDraft(datasetId, episodeIndex).then((persistedDraft) => {
          if (!persistedDraft) {
            return;
          }

          const currentState = get();

          if (currentState.datasetId !== datasetId || currentState.episodeIndex !== episodeIndex) {
            return;
          }

          set(
            (state) => ({
              savedEpisodeDrafts: {
                ...state.savedEpisodeDrafts,
                [draftKey]: persistedDraft,
              },
            }),
            false,
            'hydratePersistedEpisodeDraft'
          );

          get().loadEditOperations(persistedDraft);
        });
      },

      loadEditOperations: (ops) => {
        const removedSet = new Set(ops.removedFrames ?? []);
        const insertedMap = new Map<number, FrameInsertion>();
        for (const ins of ops.insertedFrames ?? []) {
          insertedMap.set(ins.afterFrameIndex, ins);
        }
        const subtasks = ops.subtasks ?? [];
        const trajectoryAdjustments = new Map<number, TrajectoryAdjustment>();
        for (const adj of ops.trajectoryAdjustments ?? []) {
          trajectoryAdjustments.set(adj.frameIndex, adj);
        }

        set(
          {
            datasetId: ops.datasetId,
            episodeIndex: ops.episodeIndex,
            globalTransform: ops.globalTransform ?? null,
            cameraTransforms: ops.cameraTransforms ?? {},
            removedFrames: removedSet,
            insertedFrames: insertedMap,
            subtasks,
            trajectoryAdjustments,
            originalState: buildOriginalState({
              globalTransform: ops.globalTransform ?? null,
              cameraTransforms: ops.cameraTransforms ?? {},
              removedFrames: removedSet,
              insertedFrames: insertedMap,
              subtasks,
              trajectoryAdjustments,
            }),
            isDirty: false,
            validationErrors: validateSegments(subtasks),
          },
          false,
          'loadEditOperations'
        );

        void persistEditDraft(
          ops.datasetId,
          ops.episodeIndex,
          hasEditContent(ops) ? ops : null,
        );
      },

      setGlobalTransform: (transform) => {
        set(
          (state) => {
            const newState = { ...state, globalTransform: transform };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'setGlobalTransform'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      setCameraTransform: (camera, transform) => {
        set(
          (state) => {
            const newCameraTransforms = { ...state.cameraTransforms };
            if (transform) {
              newCameraTransforms[camera] = transform;
            } else {
              delete newCameraTransforms[camera];
            }
            const newState = { ...state, cameraTransforms: newCameraTransforms };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'setCameraTransform'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      clearTransforms: () => {
        set(
          (state) => {
            const newState = {
              ...state,
              globalTransform: null,
              cameraTransforms: {},
            };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'clearTransforms'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      toggleFrameRemoval: (frameIndex) => {
        set(
          (state) => {
            const newRemoved = new Set(state.removedFrames);
            if (newRemoved.has(frameIndex)) {
              newRemoved.delete(frameIndex);
            } else {
              newRemoved.add(frameIndex);
            }
            const newState = { ...state, removedFrames: newRemoved };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'toggleFrameRemoval'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      addFrameRange: (start, end) => {
        set(
          (state) => {
            const newRemoved = new Set(state.removedFrames);
            for (let i = start; i <= end; i++) {
              newRemoved.add(i);
            }
            const newState = { ...state, removedFrames: newRemoved };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'addFrameRange'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      addFramesByFrequency: (start, end, frequency) => {
        set(
          (state) => {
            const newRemoved = new Set(state.removedFrames);
            for (let i = start; i <= end; i += frequency) {
              newRemoved.add(i);
            }
            const newState = { ...state, removedFrames: newRemoved };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'addFramesByFrequency'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      removeFrameRange: (start, end) => {
        set(
          (state) => {
            const newRemoved = new Set(state.removedFrames);
            for (let i = start; i <= end; i++) {
              newRemoved.delete(i);
            }
            const newState = { ...state, removedFrames: newRemoved };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'removeFrameRange'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      clearRemovedFrames: () => {
        set(
          (state) => {
            const newState = { ...state, removedFrames: new Set<number>() };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'clearRemovedFrames'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      insertFrame: (afterFrameIndex, factor = 0.5) => {
        set(
          (state) => {
            const newInserted = new Map(state.insertedFrames);
            newInserted.set(afterFrameIndex, {
              afterFrameIndex,
              interpolationFactor: factor,
            });
            const newState = { ...state, insertedFrames: newInserted };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'insertFrame'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      removeInsertedFrame: (afterFrameIndex) => {
        set(
          (state) => {
            const newInserted = new Map(state.insertedFrames);
            newInserted.delete(afterFrameIndex);
            const newState = { ...state, insertedFrames: newInserted };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'removeInsertedFrame'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      clearInsertedFrames: () => {
        set(
          (state) => {
            const newState = { ...state, insertedFrames: new Map<number, FrameInsertion>() };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'clearInsertedFrames'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      addSubtask: (segment) => {
        set(
          (state) => {
            const newSubtasks = [...state.subtasks, segment];
            const newState = { ...state, subtasks: newSubtasks };
            return {
              ...newState,
              isDirty: computeDirty(newState),
              validationErrors: validateSegments(newSubtasks),
            };
          },
          false,
          'addSubtask'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      addSubtaskFromRange: (start, end) => {
        const { subtasks } = get();
        const segment = createDefaultSubtask([start, end], subtasks);
        get().addSubtask(segment);
      },

      updateSubtask: (id, update) => {
        set(
          (state) => {
            const newSubtasks = state.subtasks.map((s) =>
              s.id === id ? { ...s, ...update } : s
            );
            const newState = { ...state, subtasks: newSubtasks };
            return {
              ...newState,
              isDirty: computeDirty(newState),
              validationErrors: validateSegments(newSubtasks),
            };
          },
          false,
          'updateSubtask'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      removeSubtask: (id) => {
        set(
          (state) => {
            const newSubtasks = state.subtasks.filter((s) => s.id !== id);
            const newState = { ...state, subtasks: newSubtasks };
            return {
              ...newState,
              isDirty: computeDirty(newState),
              validationErrors: validateSegments(newSubtasks),
            };
          },
          false,
          'removeSubtask'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      reorderSubtasks: (fromIndex, toIndex) => {
        set(
          (state) => {
            const newSubtasks = [...state.subtasks];
            const [removed] = newSubtasks.splice(fromIndex, 1);
            newSubtasks.splice(toIndex, 0, removed);
            const newState = { ...state, subtasks: newSubtasks };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'reorderSubtasks'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      setTrajectoryAdjustment: (frameIndex, adjustment) => {
        set(
          (state) => {
            const newAdjustments = new Map(state.trajectoryAdjustments);
            newAdjustments.set(frameIndex, { ...adjustment, frameIndex });
            const newState = { ...state, trajectoryAdjustments: newAdjustments };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'setTrajectoryAdjustment'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      removeTrajectoryAdjustment: (frameIndex) => {
        set(
          (state) => {
            const newAdjustments = new Map(state.trajectoryAdjustments);
            newAdjustments.delete(frameIndex);
            const newState = { ...state, trajectoryAdjustments: newAdjustments };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'removeTrajectoryAdjustment'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      getTrajectoryAdjustment: (frameIndex) => {
        return get().trajectoryAdjustments.get(frameIndex);
      },

      clearTrajectoryAdjustments: () => {
        set(
          (state) => {
            const newState = { ...state, trajectoryAdjustments: new Map<number, TrajectoryAdjustment>() };
            return { ...newState, isDirty: computeDirty(newState) };
          },
          false,
          'clearTrajectoryAdjustments'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      getEditOperations: () => {
        return buildEditOperations(get());
      },

      saveEpisodeDraft: () => {
        const currentState = get();
        const operations = buildEditOperations(currentState);
        const datasetId = currentState.datasetId;
        const episodeIndex = currentState.episodeIndex;

        if (!operations || !datasetId || episodeIndex === null) {
          return;
        }

        const shouldPersistDraft = hasEditContent(operations) ? operations : null;

        set(
          (state) => {
            const draftKey = getEpisodeDraftKey(datasetId, episodeIndex);
            const nextSavedEpisodeDrafts = { ...state.savedEpisodeDrafts };

            if (shouldPersistDraft) {
              nextSavedEpisodeDrafts[draftKey] = operations;
            } else {
              delete nextSavedEpisodeDrafts[draftKey];
            }

            return {
              savedEpisodeDrafts: nextSavedEpisodeDrafts,
              originalState: buildOriginalState(state),
              isDirty: false,
            };
          },
          false,
          'saveEpisodeDraft'
        );

        void persistEditDraft(datasetId, episodeIndex, shouldPersistDraft);
      },

      markSaved: () => {
        set(
          (state) => ({
            originalState: buildOriginalState(state),
            isDirty: false,
          }),
          false,
          'markSaved'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      resetEdits: () => {
        set(
          (state) => {
            if (!state.originalState) return state;
            return {
              ...state,
              globalTransform: state.originalState.globalTransform,
              cameraTransforms: structuredClone(state.originalState.cameraTransforms),
              removedFrames: new Set(state.originalState.removedFrames),
              insertedFrames: new Map(state.originalState.insertedFrames),
              subtasks: structuredClone(state.originalState.subtasks),
              trajectoryAdjustments: new Map(state.originalState.trajectoryAdjustments),
              isDirty: false,
              validationErrors: validateSegments(state.originalState.subtasks),
            };
          },
          false,
          'resetEdits'
        );

        const nextState = get();
        const operations = buildEditOperations(nextState);
        if (nextState.datasetId && nextState.episodeIndex !== null) {
          void persistEditDraft(nextState.datasetId, nextState.episodeIndex, operations && hasEditContent(operations) ? operations : null);
        }
      },

      clear: () => {
        set(initialState, false, 'clear');
      },
    }),
    { name: 'edit-store' }
  )
);

// ============================================================================
// Selector Hooks
// ============================================================================

/** Get transform state */
export const useTransformState = () =>
  useEditStore(
    useShallow((state) => ({
      globalTransform: state.globalTransform,
      cameraTransforms: state.cameraTransforms,
      setGlobalTransform: state.setGlobalTransform,
      setCameraTransform: state.setCameraTransform,
      clearTransforms: state.clearTransforms,
    }))
  );

/** Get frame removal state */
export const useFrameRemovalState = () =>
  useEditStore(
    useShallow((state) => ({
      removedFrames: state.removedFrames,
      toggleFrameRemoval: state.toggleFrameRemoval,
      addFrameRange: state.addFrameRange,
      addFramesByFrequency: state.addFramesByFrequency,
      removeFrameRange: state.removeFrameRange,
      clearRemovedFrames: state.clearRemovedFrames,
    }))
  );

/** Get frame insertion state */
export const useFrameInsertionState = () =>
  useEditStore(
    useShallow((state) => ({
      insertedFrames: state.insertedFrames,
      insertFrame: state.insertFrame,
      removeInsertedFrame: state.removeInsertedFrame,
      clearInsertedFrames: state.clearInsertedFrames,
    }))
  );

/** Get subtask state */
export const useSubtaskState = () =>
  useEditStore(
    useShallow((state) => ({
      subtasks: state.subtasks,
      validationErrors: state.validationErrors,
      addSubtask: state.addSubtask,
      addSubtaskFromRange: state.addSubtaskFromRange,
      updateSubtask: state.updateSubtask,
      removeSubtask: state.removeSubtask,
      reorderSubtasks: state.reorderSubtasks,
    }))
  );

/** Get edit dirty state */
export const useEditDirtyState = () =>
  useEditStore(
    useShallow((state) => ({
      isDirty: state.isDirty,
      markSaved: state.markSaved,
      resetEdits: state.resetEdits,
    }))
  );

/** Get trajectory adjustment state */
export const useTrajectoryAdjustmentState = () =>
  useEditStore(
    useShallow((state) => ({
      trajectoryAdjustments: state.trajectoryAdjustments,
      setTrajectoryAdjustment: state.setTrajectoryAdjustment,
      removeTrajectoryAdjustment: state.removeTrajectoryAdjustment,
      getTrajectoryAdjustment: state.getTrajectoryAdjustment,
      clearTrajectoryAdjustments: state.clearTrajectoryAdjustments,
    }))
  );
