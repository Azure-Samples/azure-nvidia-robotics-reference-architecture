# Frontend Implementation Guide: Robotic Episode Annotation System

**Target Audience**: Frontend developers implementing the annotation UI in any framework
**Reference Implementation**: React + TypeScript + Vite
**Last Updated**: February 10, 2026

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Project Structure](#2-project-structure)
3. [Type Definitions](#3-type-definitions)
4. [State Management](#4-state-management)
5. [API Client Layer](#5-api-client-layer)
6. [Component Design Patterns](#6-component-design-patterns)
7. [Annotation Workspace](#7-annotation-workspace)
8. [Video Player and Timeline](#8-video-player-and-timeline)
9. [Episode Editing](#9-episode-editing)
10. [Offline Support](#10-offline-support)
11. [Performance Optimization](#11-performance-optimization)
12. [Testing Strategy](#12-testing-strategy)

---

## 1. Architecture Overview

### Component Architecture

The frontend follows a **feature-based component architecture**:

```text
┌──────────────────────────────────────────┐
│      App Shell (Layout, Navigation)      │
├──────────────────────────────────────────┤
│   Feature Components (Pages/Views)       │  ← Dashboard, AnnotationWorkspace
├──────────────────────────────────────────┤
│   Composite Components                   │  ← EpisodeViewer, AnnotationPanel
├──────────────────────────────────────────┤
│   Base Components (UI Library)           │  ← Button, Card, Input, etc.
├──────────────────────────────────────────┤
│   State Management (Stores/Context)      │  ← Zustand, Redux, MobX, Context API
├──────────────────────────────────────────┤
│   Data Layer (API Client, Hooks)         │  ← React Query, SWR, Apollo
└──────────────────────────────────────────┘
```

### Key Architectural Patterns

1. **Unidirectional Data Flow**: Data flows down (props), events flow up (callbacks)
2. **Container/Presentational**: Separate data-fetching components from UI components
3. **Composition over Inheritance**: Build complex UIs from small, reusable pieces
4. **Custom Hooks**: Encapsulate stateful logic for reuse

---

## 2. Project Structure

### Recommended Directory Layout

```text
frontend/
├── src/
│   ├── main.{tsx,jsx,ts,js}        # Application entry point
│   ├── App.{tsx,jsx}                # Root component
│   ├── components/                  # All components
│   │   ├── ui/                      # Base UI components (shadcn/ui, MUI, etc.)
│   │   ├── episode-viewer/          # Episode playback components
│   │   │   ├── VideoPlayer.tsx
│   │   │   ├── Timeline.tsx
│   │   │   ├── TrajectoryPlot.tsx
│   │   │   └── PlaybackControls.tsx
│   │   ├── annotation-panel/        # Annotation forms
│   │   │   ├── TaskCompletenessForm.tsx
│   │   │   ├── TrajectoryQualityForm.tsx
│   │   │   └── AnomalyMarker.tsx
│   │   ├── annotation-workspace/    # Main annotation view
│   │   ├── frame-editor/            # Image transforms & frame editing
│   │   ├── export/                  # Export dialog & progress
│   │   ├── dashboard/               # Statistics & progress
│   │   ├── curriculum/              # Curriculum builder
│   │   └── object-detection/        # Detection panel
│   ├── hooks/                       # Custom React hooks
│   │   ├── use-datasets.ts          # Dataset/episode queries
│   │   ├── use-annotations.ts       # Annotation CRUD
│   │   ├── use-ai-analysis.ts       # AI suggestions
│   │   ├── use-object-detection.ts  # Detection queries
│   │   └── use-keyboard-shortcuts.ts
│   ├── stores/                      # State management
│   │   ├── dataset-store.ts         # Current dataset
│   │   ├── episode-store.ts         # Current episode
│   │   ├── annotation-store.ts      # Annotation draft state
│   │   └── edit-store.ts            # Frame edit operations
│   ├── lib/                         # Utilities
│   │   ├── api-client.ts            # HTTP client configuration
│   │   ├── query-client.ts          # React Query setup
│   │   ├── offline-storage.ts       # IndexedDB wrapper
│   │   └── utils.ts                 # Helpers
│   ├── types/                       # TypeScript type definitions
│   │   ├── annotations.ts
│   │   ├── datasources.ts
│   │   ├── detection.ts
│   │   └── episode-edit.ts
│   └── api/                         # API client functions
│       ├── datasets.ts
│       ├── annotations.ts
│       ├── detection.ts
│       └── ai-analysis.ts
├── public/                          # Static assets
├── package.json
├── tsconfig.json
├── vite.config.ts / webpack.config.js
└── README.md
```

---

## 3. Type Definitions

### Core Types

Define strong types that match the backend schema:

```typescript
// types/annotations.ts

/** Task completion status rating */
export type TaskCompletenessRating = 'success' | 'partial' | 'failure' | 'unknown';

/** Annotator confidence level (1-5 scale) */
export type ConfidenceLevel = 1 | 2 | 3 | 4 | 5;

/** Task completeness annotation */
export interface TaskCompletenessAnnotation {
  rating: TaskCompletenessRating;
  confidence: ConfidenceLevel;
  completionPercentage?: number;
  failureReason?: string;
  subtaskReached?: string;
}

/** Quality score on 1-5 scale */
export type QualityScore = 1 | 2 | 3 | 4 | 5;

/** Trajectory quality flags */
export type TrajectoryFlag =
  | 'jittery'
  | 'inefficient-path'
  | 'near-collision'
  | 'over-extension'
  | 'under-reaching'
  | 'hesitation'
  | 'correction-heavy';

/** Trajectory quality metrics */
export interface TrajectoryQualityMetrics {
  smoothness: QualityScore;
  efficiency: QualityScore;
  safety: QualityScore;
  precision: QualityScore;
}

/** Trajectory quality annotation */
export interface TrajectoryQualityAnnotation {
  overallScore: QualityScore;
  metrics: TrajectoryQualityMetrics;
  flags: TrajectoryFlag[];
}

/** Anomaly marker */
export interface Anomaly {
  id: string;
  type: AnomalyType;
  severity: AnomalySeverity;
  frameRange: [number, number];
  timestamp: [number, number];
  description: string;
  autoDetected: boolean;
  verified: boolean;
}

/** Complete episode annotation */
export interface EpisodeAnnotation {
  annotatorId: string;
  timestamp: string; // ISO 8601
  taskCompleteness: TaskCompletenessAnnotation;
  trajectoryQuality: TrajectoryQualityAnnotation;
  dataQuality: DataQualityAnnotation;
  anomalies: Anomaly[];
  notes?: string;
}

/** Episode annotation file (server response) */
export interface EpisodeAnnotationFile {
  schemaVersion: string;
  episodeIndex: number;
  datasetId: string;
  annotations: EpisodeAnnotation[];
  consensus?: EpisodeConsensus;
}
```

### Episode and Dataset Types

```typescript
// types/datasources.ts

export interface EpisodeMeta {
  index: number;
  length: number;
  taskIndex: number;
  hasAnnotations: boolean;
}

export interface TrajectoryPoint {
  timestamp: number;
  frame: number;
  jointPositions: number[];
  jointVelocities: number[];
  endEffectorPose: number[];
  gripperState: number;
}

export interface EpisodeData {
  meta: EpisodeMeta;
  videoUrls: Record<string, string>; // camera name -> URL
  trajectoryData: TrajectoryPoint[];
}

export interface DatasetInfo {
  id: string;
  name: string;
  totalEpisodes: number;
  fps: number;
  features: Record<string, FeatureSchema>;
  tasks: TaskInfo[];
}
```

**Best Practices**:

- Use literal types for enums (`'success' | 'partial'` not `string`)
- Make optional fields explicit with `?` or `| undefined`
- Use `readonly` for immutable data
- Create utility types for common patterns

---

## 4. State Management

### Option 1: Zustand (Recommended for React)

Simple, hook-based state management:

```typescript
// stores/episode-store.ts
import { create } from 'zustand';
import type { EpisodeData } from '@/types';

interface EpisodeStore {
  currentEpisode: EpisodeData | null;
  currentFrame: number;
  isPlaying: boolean;
  playbackSpeed: number;

  // Actions
  setCurrentEpisode: (episode: EpisodeData | null) => void;
  setCurrentFrame: (frame: number) => void;
  togglePlayback: () => void;
  setPlaybackSpeed: (speed: number) => void;
}

export const useEpisodeStore = create<EpisodeStore>((set) => ({
  currentEpisode: null,
  currentFrame: 0,
  isPlaying: false,
  playbackSpeed: 1.0,

  setCurrentEpisode: (episode) => set({ currentEpisode: episode, currentFrame: 0 }),
  setCurrentFrame: (frame) => set({ currentFrame: frame }),
  togglePlayback: () => set((state) => ({ isPlaying: !state.isPlaying })),
  setPlaybackSpeed: (speed) => set({ playbackSpeed: speed }),
}));

// Usage in component
function VideoPlayer() {
  const currentFrame = useEpisodeStore((state) => state.currentFrame);
  const setCurrentFrame = useEpisodeStore((state) => state.setCurrentFrame);

  return <div>Frame: {currentFrame}</div>;
}
```

### Option 2: Redux Toolkit

For larger applications needing more structure:

```typescript
// stores/episodeSlice.ts
import { createSlice, PayloadAction } from '@reduxjs/toolkit';

interface EpisodeState {
  currentEpisode: EpisodeData | null;
  currentFrame: number;
  isPlaying: boolean;
}

const episodeSlice = createSlice({
  name: 'episode',
  initialState: {
    currentEpisode: null,
    currentFrame: 0,
    isPlaying: false,
  } as EpisodeState,
  reducers: {
    setCurrentEpisode: (state, action: PayloadAction<EpisodeData>) => {
      state.currentEpisode = action.payload;
      state.currentFrame = 0;
    },
    setCurrentFrame: (state, action: PayloadAction<number>) => {
      state.currentFrame = action.payload;
    },
    togglePlayback: (state) => {
      state.isPlaying = !state.isPlaying;
    },
  },
});

export const { setCurrentEpisode, setCurrentFrame, togglePlayback } = episodeSlice.actions;
export default episodeSlice.reducer;
```

### Edit Store - Complex State Example

```typescript
// stores/edit-store.ts
import { create } from 'zustand';
import type { ImageTransform, FrameInsertion } from '@/types/episode-edit';

interface EditStore {
  datasetId: string | null;
  episodeIndex: number | null;
  globalTransform: ImageTransform | null;
  cameraTransforms: Record<string, ImageTransform>;
  removedFrames: Set<number>;
  insertedFrames: Map<number, FrameInsertion>;
  trajectoryAdjustments: Map<number, TrajectoryAdjustment>;

  // Actions
  initializeEdit: (datasetId: string, episodeIndex: number) => void;
  setGlobalTransform: (transform: ImageTransform | null) => void;
  setCameraTransform: (camera: string, transform: ImageTransform | null) => void;
  addRemovedFrame: (frameIndex: number) => void;
  removeRemovedFrame: (frameIndex: number) => void;
  addInsertedFrame: (afterIndex: number, insertion: FrameInsertion) => void;
  clearEdits: () => void;
}

export const useEditStore = create<EditStore>((set, get) => ({
  datasetId: null,
  episodeIndex: null,
  globalTransform: null,
  cameraTransforms: {},
  removedFrames: new Set(),
  insertedFrames: new Map(),
  trajectoryAdjustments: new Map(),

  initializeEdit: (datasetId, episodeIndex) => set({
    datasetId,
    episodeIndex,
    globalTransform: null,
    cameraTransforms: {},
    removedFrames: new Set(),
    insertedFrames: new Map(),
    trajectoryAdjustments: new Map(),
  }),

  setGlobalTransform: (transform) => set({ globalTransform: transform }),

  setCameraTransform: (camera, transform) => set((state) => ({
    cameraTransforms: {
      ...state.cameraTransforms,
      [camera]: transform,
    },
  })),

  addRemovedFrame: (frameIndex) => set((state) => ({
    removedFrames: new Set(state.removedFrames).add(frameIndex),
  })),

  removeRemovedFrame: (frameIndex) => set((state) => {
    const newSet = new Set(state.removedFrames);
    newSet.delete(frameIndex);
    return { removedFrames: newSet };
  }),

  addInsertedFrame: (afterIndex, insertion) => set((state) => {
    const newMap = new Map(state.insertedFrames);
    newMap.set(afterIndex, insertion);
    return { insertedFrames: newMap };
  }),

  clearEdits: () => set({
    globalTransform: null,
    cameraTransforms: {},
    removedFrames: new Set(),
    insertedFrames: new Map(),
    trajectoryAdjustments: new Map(),
  }),
}));
```

**Key Patterns**:

- Use derived state sparingly (compute in selectors)
- Keep stores focused on single domains
- Avoid deeply nested state (normalize if needed)
- Use immer for immutable updates (built into Zustand and Redux Toolkit)

---

## 5. API Client Layer

### HTTP Client Setup

```typescript
// lib/api-client.ts
import axios from 'axios';

export const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:8000',
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor (e.g., for auth tokens)
apiClient.interceptors.request.use((config) => {
  const token = localStorage.getItem('auth_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Response interceptor (error handling)
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // Redirect to login
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);
```

### API Functions

```typescript
// api/datasets.ts
import { apiClient } from '@/lib/api-client';
import type { DatasetInfo, EpisodeMeta, EpisodeData } from '@/types';

/** List all datasets */
export async function listDatasets(): Promise<DatasetInfo[]> {
  const response = await apiClient.get<DatasetInfo[]>('/datasets');
  return response.data;
}

/** Get dataset metadata */
export async function getDataset(datasetId: string): Promise<DatasetInfo> {
  const response = await apiClient.get<DatasetInfo>(`/datasets/${datasetId}`);
  return response.data;
}

/** List episodes with pagination */
export async function listEpisodes(
  datasetId: string,
  options?: {
    offset?: number;
    limit?: number;
    hasAnnotations?: boolean;
    taskIndex?: number;
  }
): Promise<EpisodeMeta[]> {
  const response = await apiClient.get<EpisodeMeta[]>(
    `/datasets/${datasetId}/episodes`,
    { params: options }
  );
  return response.data;
}

/** Get episode data */
export async function getEpisode(
  datasetId: string,
  episodeIndex: number
): Promise<EpisodeData> {
  const response = await apiClient.get<EpisodeData>(
    `/datasets/${datasetId}/episodes/${episodeIndex}`
  );
  return response.data;
}
```

### React Query Hooks

Use React Query for data fetching and caching:

```typescript
// hooks/use-datasets.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import * as api from '@/api/datasets';

/** Query key factory for datasets */
export const datasetKeys = {
  all: ['datasets'] as const,
  lists: () => [...datasetKeys.all, 'list'] as const,
  list: () => [...datasetKeys.lists()] as const,
  details: () => [...datasetKeys.all, 'detail'] as const,
  detail: (id: string) => [...datasetKeys.details(), id] as const,
  episodes: (id: string) => [...datasetKeys.detail(id), 'episodes'] as const,
  episode: (datasetId: string, episodeIdx: number) =>
    [...datasetKeys.detail(datasetId), 'episode', episodeIdx] as const,
};

/** Hook to list all datasets */
export function useDatasets() {
  return useQuery({
    queryKey: datasetKeys.list(),
    queryFn: api.listDatasets,
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
}

/** Hook to get dataset details */
export function useDataset(datasetId: string) {
  return useQuery({
    queryKey: datasetKeys.detail(datasetId),
    queryFn: () => api.getDataset(datasetId),
    enabled: !!datasetId,
  });
}

/** Hook to list episodes */
export function useEpisodes(
  datasetId: string,
  options?: Parameters<typeof api.listEpisodes>[1]
) {
  return useQuery({
    queryKey: [...datasetKeys.episodes(datasetId), options],
    queryFn: () => api.listEpisodes(datasetId, options),
    enabled: !!datasetId,
  });
}

/** Hook to get episode data */
export function useEpisode(datasetId: string, episodeIndex: number) {
  return useQuery({
    queryKey: datasetKeys.episode(datasetId, episodeIndex),
    queryFn: () => api.getEpisode(datasetId, episodeIndex),
    enabled: !!datasetId && episodeIndex >= 0,
    staleTime: 10 * 60 * 1000, // 10 minutes
  });
}
```

### Annotation Hooks

```typescript
// hooks/use-annotations.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import * as api from '@/api/annotations';

export const annotationKeys = {
  all: ['annotations'] as const,
  detail: (datasetId: string, episodeIdx: number) =>
    [...annotationKeys.all, datasetId, episodeIdx] as const,
};

export function useAnnotation(datasetId: string, episodeIndex: number) {
  return useQuery({
    queryKey: annotationKeys.detail(datasetId, episodeIndex),
    queryFn: () => api.getAnnotation(datasetId, episodeIndex),
    enabled: !!datasetId && episodeIndex >= 0,
  });
}

export function useSaveAnnotation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: {
      datasetId: string;
      episodeIndex: number;
      annotation: EpisodeAnnotation;
    }) => api.saveAnnotation(params.datasetId, params.episodeIndex, params.annotation),

    onSuccess: (data, variables) => {
      // Invalidate and refetch
      queryClient.invalidateQueries({
        queryKey: annotationKeys.detail(variables.datasetId, variables.episodeIndex),
      });

      // Optimistically update
      queryClient.setQueryData(
        annotationKeys.detail(variables.datasetId, variables.episodeIndex),
        data
      );
    },
  });
}
```

**Benefits of React Query**:

- Automatic caching and background refetching
- Optimistic updates
- Request deduplication
- Loading/error states handled automatically
- Cache invalidation strategies

---

## 6. Component Design Patterns

### Presentational Component

Pure UI component with no side effects:

```typescript
// components/annotation-panel/TaskCompletenessForm.tsx
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import type { TaskCompletenessAnnotation, TaskCompletenessRating } from '@/types';

interface TaskCompletenessFormProps {
  value: TaskCompletenessAnnotation;
  onChange: (value: TaskCompletenessAnnotation) => void;
  disabled?: boolean;
}

export function TaskCompletenessForm({
  value,
  onChange,
  disabled = false,
}: TaskCompletenessFormProps) {
  const handleRatingChange = (rating: TaskCompletenessRating) => {
    onChange({ ...value, rating });
  };

  const handleConfidenceChange = (confidence: number) => {
    onChange({ ...value, confidence: confidence as ConfidenceLevel });
  };

  return (
    <div className="space-y-4">
      <div>
        <Label>Task Completion Rating</Label>
        <RadioGroup
          value={value.rating}
          onValueChange={handleRatingChange}
          disabled={disabled}
        >
          <div className="flex items-center space-x-2">
            <RadioGroupItem value="success" id="success" />
            <Label htmlFor="success">Success</Label>
          </div>
          <div className="flex items-center space-x-2">
            <RadioGroupItem value="partial" id="partial" />
            <Label htmlFor="partial">Partial</Label>
          </div>
          <div className="flex items-center space-x-2">
            <RadioGroupItem value="failure" id="failure" />
            <Label htmlFor="failure">Failure</Label>
          </div>
          <div className="flex items-center space-x-2">
            <RadioGroupItem value="unknown" id="unknown" />
            <Label htmlFor="unknown">Unknown</Label>
          </div>
        </RadioGroup>
      </div>

      <div>
        <Label>Confidence (1-5)</Label>
        <div className="flex gap-2">
          {[1, 2, 3, 4, 5].map((level) => (
            <Button
              key={level}
              variant={value.confidence === level ? 'default' : 'outline'}
              size="sm"
              onClick={() => handleConfidenceChange(level)}
              disabled={disabled}
            >
              {level}
            </Button>
          ))}
        </div>
      </div>

      {value.rating === 'partial' && (
        <div>
          <Label htmlFor="percentage">Completion Percentage</Label>
          <input
            id="percentage"
            type="number"
            min="0"
            max="100"
            value={value.completionPercentage ?? 0}
            onChange={(e) => onChange({
              ...value,
              completionPercentage: parseInt(e.target.value),
            })}
            className="w-full"
            disabled={disabled}
          />
        </div>
      )}

      {value.rating === 'failure' && (
        <div>
          <Label htmlFor="reason">Failure Reason</Label>
          <textarea
            id="reason"
            value={value.failureReason ?? ''}
            onChange={(e) => onChange({
              ...value,
              failureReason: e.target.value,
            })}
            className="w-full"
            disabled={disabled}
          />
        </div>
      )}
    </div>
  );
}
```

### Container Component

Handles data fetching and business logic:

```typescript
// components/annotation-panel/AnnotationPanel.tsx
import { useState, useEffect } from 'react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { useAnnotation, useSaveAnnotation } from '@/hooks/use-annotations';
import { useDatasetStore, useEpisodeStore } from '@/stores';
import { TaskCompletenessForm } from './TaskCompletenessForm';
import { TrajectoryQualityForm } from './TrajectoryQualityForm';
import type { EpisodeAnnotation } from '@/types';

export function AnnotationPanel() {
  const currentDataset = useDatasetStore((state) => state.currentDataset);
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);

  const datasetId = currentDataset?.id;
  const episodeIndex = currentEpisode?.meta.index;

  const { data: annotationFile, isLoading } = useAnnotation(
    datasetId!,
    episodeIndex!
  );

  const { mutate: saveAnnotation, isPending: isSaving } = useSaveAnnotation();

  const [draft, setDraft] = useState<EpisodeAnnotation | null>(null);

  useEffect(() => {
    if (annotationFile && annotationFile.annotations.length > 0) {
      // Load existing annotation
      setDraft(annotationFile.annotations[0]);
    } else if (datasetId && episodeIndex !== undefined) {
      // Initialize new annotation
      setDraft({
        annotatorId: 'current-user', // Get from auth
        timestamp: new Date().toISOString(),
        taskCompleteness: {
          rating: 'unknown',
          confidence: 3,
        },
        trajectoryQuality: {
          overallScore: 3,
          metrics: {
            smoothness: 3,
            efficiency: 3,
            safety: 3,
            precision: 3,
          },
          flags: [],
        },
        dataQuality: {
          overallQuality: 'good',
          issues: [],
        },
        anomalies: [],
      });
    }
  }, [annotationFile, datasetId, episodeIndex]);

  const handleSave = () => {
    if (!draft || !datasetId || episodeIndex === undefined) return;

    saveAnnotation({
      datasetId,
      episodeIndex,
      annotation: draft,
    });
  };

  if (isLoading || !draft) {
    return <div>Loading...</div>;
  }

  return (
    <div className="h-full flex flex-col">
      <Tabs defaultValue="annotate" className="flex-1">
        <TabsList className="grid w-full grid-cols-3">
          <TabsTrigger value="annotate">Annotate</TabsTrigger>
          <TabsTrigger value="ai">AI Suggestions</TabsTrigger>
          <TabsTrigger value="history">History</TabsTrigger>
        </TabsList>

        <TabsContent value="annotate" className="flex-1 overflow-y-auto p-4 space-y-6">
          <section>
            <h3 className="font-semibold mb-2">Task Completion</h3>
            <TaskCompletenessForm
              value={draft.taskCompleteness}
              onChange={(taskCompleteness) => setDraft({ ...draft, taskCompleteness })}
            />
          </section>

          <section>
            <h3 className="font-semibold mb-2">Trajectory Quality</h3>
            <TrajectoryQualityForm
              value={draft.trajectoryQuality}
              onChange={(trajectoryQuality) => setDraft({ ...draft, trajectoryQuality })}
            />
          </section>

          {/* More sections... */}
        </TabsContent>

        {/* Other tabs... */}
      </Tabs>

      <div className="border-t p-4 flex justify-end gap-2">
        <Button variant="outline" onClick={() => setDraft(null)}>
          Reset
        </Button>
        <Button onClick={handleSave} disabled={isSaving}>
          {isSaving ? 'Saving...' : 'Save Annotation'}
        </Button>
      </div>
    </div>
  );
}
```

---

## 7. Annotation Workspace

### Main Workspace Layout

```typescript
// components/annotation-workspace/AnnotationWorkspace.tsx
import { useState, useEffect } from 'react';
import { VideoPlayer } from '@/components/episode-viewer/VideoPlayer';
import { Timeline } from '@/components/episode-viewer/Timeline';
import { TrajectoryPlot } from '@/components/episode-viewer/TrajectoryPlot';
import { AnnotationPanel } from '@/components/annotation-panel/AnnotationPanel';
import { SubtaskTimelineTrack } from '@/components/subtask-timeline/SubtaskTimelineTrack';
import { useDatasetStore, useEpisodeStore, useEditStore } from '@/stores';

export function AnnotationWorkspace() {
  const currentDataset = useDatasetStore((state) => state.currentDataset);
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);
  const currentFrame = useEpisodeStore((state) => state.currentFrame);

  if (!currentDataset || !currentEpisode) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-muted-foreground">Select an episode to begin</p>
      </div>
    );
  }

  return (
    <div className="flex h-screen">
      {/* Left Panel - Episode Viewer */}
      <div className="flex-1 flex flex-col border-r">
        <div className="flex-1">
          <VideoPlayer />
        </div>

        <div className="border-t">
          <Timeline />
          <SubtaskTimelineTrack />
        </div>

        <div className="border-t h-48">
          <TrajectoryPlot />
        </div>
      </div>

      {/* Right Panel - Annotation Controls */}
      <div className="w-96">
        <AnnotationPanel />
      </div>
    </div>
  );
}
```

---

## 8. Video Player and Timeline

### Video Player with Frame Extraction

```typescript
// components/episode-viewer/VideoPlayer.tsx
import { useEffect, useRef, useState } from 'react';
import { useDatasetStore, useEpisodeStore } from '@/stores';

export function VideoPlayer() {
  const currentDataset = useDatasetStore((state) => state.currentDataset);
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);
  const currentFrame = useEpisodeStore((state) => state.currentFrame);
  const setCurrentFrame = useEpisodeStore((state) => state.setCurrentFrame);

  const [imageUrl, setImageUrl] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (!currentDataset || !currentEpisode) return;

    const fetchFrame = async () => {
      setIsLoading(true);
      try {
        const url = `/api/datasets/${currentDataset.id}/episodes/${currentEpisode.meta.index}/frames/${currentFrame}?camera=il-camera`;
        setImageUrl(url);
      } finally {
        setIsLoading(false);
      }
    };

    fetchFrame();
  }, [currentDataset, currentEpisode, currentFrame]);

  return (
    <div className="relative w-full h-full bg-black flex items-center justify-center">
      {isLoading && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="text-white">Loading frame...</div>
        </div>
      )}

      {imageUrl && (
        <img
          src={imageUrl}
          alt={`Frame ${currentFrame}`}
          className="max-w-full max-h-full object-contain"
          onError={() => setImageUrl(null)}
        />
      )}

      {/* Frame number overlay */}
      <div className="absolute bottom-4 right-4 bg-black/70 text-white px-3 py-1 rounded">
        Frame: {currentFrame} / {currentEpisode?.meta.length ?? 0}
      </div>
    </div>
  );
}
```

### Timeline Component

```typescript
// components/episode-viewer/Timeline.tsx
import { useRef, useEffect, useState } from 'react';
import { useEpisodeStore } from '@/stores';

export function Timeline() {
  const currentFrame = useEpisodeStore((state) => state.currentFrame);
  const setCurrentFrame = useEpisodeStore((state) => state.setCurrentFrame);
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);

  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [isDragging, setIsDragging] = useState(false);

  const totalFrames = currentEpisode?.meta.length ?? 100;

  const handleMouseDown = (e: React.MouseEvent<HTMLCanvasElement>) => {
    setIsDragging(true);
    updateFrameFromMouse(e);
  };

  const handleMouseMove = (e: React.MouseEvent<HTMLCanvasElement>) => {
    if (isDragging) {
      updateFrameFromMouse(e);
    }
  };

  const handleMouseUp = () => {
    setIsDragging(false);
  };

  const updateFrameFromMouse = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const fraction = x / rect.width;
    const frame = Math.floor(fraction * totalFrames);
    setCurrentFrame(Math.max(0, Math.min(frame, totalFrames - 1)));
  };

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Draw timeline
    const width = canvas.width;
    const height = canvas.height;

    ctx.clearRect(0, 0, width, height);

    // Background
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, width, height);

    // Current position indicator
    const position = (currentFrame / totalFrames) * width;
    ctx.fillStyle = '#3b82f6';
    ctx.fillRect(position - 2, 0, 4, height);

    // Frame markers every 100 frames
    ctx.fillStyle = '#666';
    for (let i = 0; i < totalFrames; i += 100) {
      const x = (i / totalFrames) * width;
      ctx.fillRect(x, height - 10, 1, 10);
    }
  }, [currentFrame, totalFrames]);

  return (
    <canvas
      ref={canvasRef}
      width={800}
      height={60}
      className="w-full cursor-pointer"
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onMouseLeave={handleMouseUp}
    />
  );
}
```

### Playback Controls

```typescript
// stores/playback-controls.ts (custom hook)
import { useEffect, useCallback } from 'react';
import { useEpisodeStore } from './episode-store';

export function usePlaybackControls() {
  const currentFrame = useEpisodeStore((state) => state.currentFrame);
  const setCurrentFrame = useEpisodeStore((state) => state.setCurrentFrame);
  const isPlaying = useEpisodeStore((state) => state.isPlaying);
  const togglePlayback = useEpisodeStore((state) => state.togglePlayback);
  const playbackSpeed = useEpisodeStore((state) => state.playbackSpeed);
  const currentEpisode = useEpisodeStore((state) => state.currentEpisode);

  const totalFrames = currentEpisode?.meta.length ?? 0;

  // Playback loop
  useEffect(() => {
    if (!isPlaying) return;

    const fps = currentEpisode?.meta.fps ?? 30;
    const interval = (1000 / fps) / playbackSpeed;

    const timer = setInterval(() => {
      setCurrentFrame((prev) => {
        const next = prev + 1;
        if (next >= totalFrames) {
          return 0; // Loop
        }
        return next;
      });
    }, interval);

    return () => clearInterval(timer);
  }, [isPlaying, playbackSpeed, totalFrames, currentEpisode, setCurrentFrame]);

  const stepForward = useCallback(() => {
    setCurrentFrame((prev) => Math.min(prev + 1, totalFrames - 1));
  }, [setCurrentFrame, totalFrames]);

  const stepBackward = useCallback(() => {
    setCurrentFrame((prev) => Math.max(prev - 1, 0));
  }, [setCurrentFrame]);

  return {
    currentFrame,
    setCurrentFrame,
    isPlaying,
    togglePlayback,
    playbackSpeed,
    stepForward,
    stepBackward,
  };
}
```

---

## 9. Episode Editing

### Image Transform Controls

```typescript
// components/frame-editor/TransformControls.tsx
import { Slider } from '@/components/ui/slider';
import { Label } from '@/components/ui/label';
import { useEditStore } from '@/stores/edit-store';

export function TransformControls() {
  const globalTransform = useEditStore((state) => state.globalTransform);
  const setGlobalTransform = useEditStore((state) => state.setGlobalTransform);

  const handleBrightnessChange = (value: number[]) => {
    setGlobalTransform({
      ...globalTransform,
      colorAdjustment: {
        ...globalTransform?.colorAdjustment,
        brightness: value[0],
      },
    });
  };

  return (
    <div className="space-y-4">
      <div>
        <Label>Brightness</Label>
        <Slider
          value={[globalTransform?.colorAdjustment?.brightness ?? 0]}
          onValueChange={handleBrightnessChange}
          min={-1}
          max={1}
          step={0.1}
        />
      </div>

      {/* Similar controls for contrast, saturation, etc. */}
    </div>
  );
}
```

### Frame Removal

```typescript
// components/frame-editor/FrameRemovalToolbar.tsx
import { Button } from '@/components/ui/button';
import { useEditStore } from '@/stores/edit-store';
import { useEpisodeStore } from '@/stores/episode-store';

export function FrameRemovalToolbar() {
  const currentFrame = useEpisodeStore((state) => state.currentFrame);
  const removedFrames = useEditStore((state) => state.removedFrames);
  const addRemovedFrame = useEditStore((state) => state.addRemovedFrame);
  const removeRemovedFrame = useEditStore((state) => state.removeRemovedFrame);

  const isRemoved = removedFrames.has(currentFrame);

  const handleToggle = () => {
    if (isRemoved) {
      removeRemovedFrame(currentFrame);
    } else {
      addRemovedFrame(currentFrame);
    }
  };

  return (
    <div className="flex items-center gap-2">
      <Button
        variant={isRemoved ? 'destructive' : 'outline'}
        onClick={handleToggle}
      >
        {isRemoved ? 'Restore Frame' : 'Remove Frame'}
      </Button>

      <span className="text-sm text-muted-foreground">
        {removedFrames.size} frames removed
      </span>
    </div>
  );
}
```

---

## 10. Offline Support

### IndexedDB Wrapper

```typescript
// lib/offline-storage.ts
import { openDB, type IDBPDatabase } from 'idb';

const DB_NAME = 'robotic-training-annotations';
const DB_VERSION = 1;

let db: IDBPDatabase | null = null;

export async function getDB() {
  if (db) return db;

  db = await openDB(DB_NAME, DB_VERSION, {
    upgrade(database) {
      // Annotations store
      if (!database.objectStoreNames.contains('annotations')) {
        const store = database.createObjectStore('annotations', {
          keyPath: 'id',
        });
        store.createIndex('by-dataset', 'datasetId');
        store.createIndex('by-sync-status', 'syncStatus');
      }

      // Sync queue store
      if (!database.objectStoreNames.contains('syncQueue')) {
        const store = database.createObjectStore('syncQueue', {
          keyPath: 'id',
        });
        store.createIndex('by-created', 'createdAt');
      }
    },
  });

  return db;
}

export async function saveAnnotationOffline(
  datasetId: string,
  episodeId: string,
  annotation: any
) {
  const database = await getDB();

  await database.put('annotations', {
    id: `${datasetId}-${episodeId}`,
    datasetId,
    episodeId,
    data: annotation,
    localUpdatedAt: new Date().toISOString(),
    syncStatus: 'pending',
  });

  // Add to sync queue
  await database.add('syncQueue', {
    id: crypto.randomUUID(),
    type: 'update',
    datasetId,
    episodeId,
    annotationId: `${datasetId}-${episodeId}`,
    payload: annotation,
    createdAt: new Date().toISOString(),
    retryCount: 0,
  });
}

export async function syncPendingAnnotations() {
  const database = await getDB();
  const queue = await database.getAll('syncQueue');

  for (const item of queue) {
    try {
      // Attempt to sync to server
      await apiClient.put(
        `/datasets/${item.datasetId}/episodes/${item.episodeId}/annotations`,
        item.payload
      );

      // Mark as synced
      await database.delete('syncQueue', item.id);

      const annotation = await database.get('annotations', item.annotationId);
      if (annotation) {
        annotation.syncStatus = 'synced';
        await database.put('annotations', annotation);
      }
    } catch (error) {
      // Increment retry count
      item.retryCount++;
      item.lastError = error.message;
      await database.put('syncQueue', item);
    }
  }
}
```

---

## 11. Performance Optimization

### Memoization

```typescript
import { memo, useMemo } from 'react';

// Memoize expensive components
export const EpisodeListItem = memo(function EpisodeListItem({
  episode,
  isSelected,
  onSelect,
}: Props) {
  // Component logic
  return <div>...</div>;
});

// Memoize expensive computations
function TrajectoryPlot({ trajectoryData }: Props) {
  const plotData = useMemo(() => {
    // Expensive data transformation
    return trajectoryData.map(point => ({
      x: point.timestamp,
      y: point.jointPositions[0],
    }));
  }, [trajectoryData]);

  return <Plot data={plotData} />;
}
```

### Virtual Scrolling

For large lists (e.g., 10,000+ episodes):

```typescript
import { useVirtualizer } from '@tanstack/react-virtual';

function EpisodeList({ episodes }: { episodes: EpisodeMeta[] }) {
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: episodes.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 80, // Estimated row height
  });

  return (
    <div ref={parentRef} className="h-full overflow-y-auto">
      <div
        style={{
          height: `${virtualizer.getTotalSize()}px`,
          position: 'relative',
        }}
      >
        {virtualizer.getVirtualItems().map((virtualRow) => {
          const episode = episodes[virtualRow.index];
          return (
            <div
              key={virtualRow.index}
              style={{
                position: 'absolute',
                top: 0,
                left: 0,
                width: '100%',
                height: `${virtualRow.size}px`,
                transform: `translateY(${virtualRow.start}px)`,
              }}
            >
              <EpisodeListItem episode={episode} />
            </div>
          );
        })}
      </div>
    </div>
  );
}
```

### Lazy Loading

```typescript
import { lazy, Suspense } from 'react';

const ObjectDetectionPanel = lazy(() =>
  import('@/components/object-detection/DetectionPanel')
);

function App() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <ObjectDetectionPanel />
    </Suspense>
  );
}
```

---

## 12. Testing Strategy

### Component Tests (React Testing Library)

```typescript
import { render, screen, fireEvent } from '@testing-library/react';
import { TaskCompletenessForm } from './TaskCompletenessForm';

describe('TaskCompletenessForm', () => {
  it('renders rating options', () => {
    const onChange = jest.fn();
    const value = {
      rating: 'unknown' as const,
      confidence: 3 as const,
    };

    render(<TaskCompletenessForm value={value} onChange={onChange} />);

    expect(screen.getByLabelText('Success')).toBeInTheDocument();
    expect(screen.getByLabelText('Partial')).toBeInTheDocument();
    expect(screen.getByLabelText('Failure')).toBeInTheDocument();
  });

  it('calls onChange when rating is selected', () => {
    const onChange = jest.fn();
    const value = {
      rating: 'unknown' as const,
      confidence: 3 as const,
    };

    render(<TaskCompletenessForm value={value} onChange={onChange} />);

    fireEvent.click(screen.getByLabelText('Success'));

    expect(onChange).toHaveBeenCalledWith({
      rating: 'success',
      confidence: 3,
    });
  });

  it('shows completion percentage field when partial is selected', () => {
    const onChange = jest.fn();
    const value = {
      rating: 'partial' as const,
      confidence: 3 as const,
      completionPercentage: 50,
    };

    render(<TaskCompletenessForm value={value} onChange={onChange} />);

    expect(screen.getByLabelText('Completion Percentage')).toBeInTheDocument();
  });
});
```

### Hook Tests

```typescript
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useEpisodes } from './use-datasets';

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
    },
  });

  return ({ children }) => (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  );
}

describe('useEpisodes', () => {
  it('fetches episodes for a dataset', async () => {
    const { result } = renderHook(
      () => useEpisodes('test_dataset', { limit: 10 }),
      { wrapper: createWrapper() }
    );

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(result.current.data).toHaveLength(10);
  });
});
```

---

## Summary

This guide provides comprehensive patterns for building the frontend:

1. **Strong typing**: TypeScript for type safety and self-documentation
2. **State management**: Zustand/Redux for global state, React Query for server state
3. **Component patterns**: Presentational/container separation, custom hooks
4. **API layer**: Centralized HTTP client, React Query hooks
5. **Performance**: Memoization, virtual scrolling, lazy loading
6. **Offline support**: IndexedDB for local persistence, sync queue
7. **Testing**: Unit tests for components and hooks

Adapt these patterns to your chosen framework (Vue, Angular, Svelte) while preserving the architectural principles.

---

## End of Frontend Implementation Guide
