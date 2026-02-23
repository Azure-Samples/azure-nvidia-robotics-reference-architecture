/**
 * Custom hooks for data fetching and state management.
 */

export {
  useDatasets,
  useDataset,
  useEpisodes,
  useEpisode,
  datasetKeys,
} from './use-datasets';

export {
  useEpisodeList,
  useCurrentEpisode,
  useEpisodeNavigationWithPrefetch,
  episodeKeys,
} from './use-episodes';

export {
  useEpisodeAnnotations,
  useSaveAnnotation,
  useSaveCurrentAnnotation,
  useDeleteAnnotation,
  useAutoAnalysis,
  useCurrentEpisodeAutoAnalysis,
  useAnnotationSummary,
  annotationKeys,
} from './use-annotations';

export {
  useKeyboardShortcuts,
  useAnnotationShortcuts,
  formatShortcut,
  type KeyboardShortcut,
} from './use-keyboard-shortcuts';

export { useAnnotationWorkflow } from './use-annotation-workflow';

export {
  useBatchSelection,
  useBatchSelectionStore,
} from './use-batch-selection';

export {
  useAISuggestion,
  useTrajectoryAnalysis,
  useAnomalyDetection,
  useRequestAISuggestion,
  aiAnalysisKeys,
  type AnnotationSuggestion,
  type TrajectoryMetrics,
  type AnomalyDetectionResponse,
  type SuggestAnnotationRequest,
} from './use-ai-analysis';

export {
  useDashboardStats,
  useDashboardMetrics,
  dashboardKeys,
  type DashboardStats,
  type AnnotatorStats,
  type ActivityItem,
} from './use-dashboard';

export {
  useOfflineAnnotations,
  type OfflineAnnotation,
  type UseOfflineAnnotationsResult,
} from './use-offline-annotations';

export { useExport } from './use-export';

export {
  useObjectDetection,
  detectionKeys,
} from './use-object-detection';

export {
  useDatasetLabels,
  useSaveEpisodeLabels,
  useAddLabelOption,
  useSaveAllLabels,
  useCurrentEpisodeLabels,
  labelKeys,
} from './use-labels';
