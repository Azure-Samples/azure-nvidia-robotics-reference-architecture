/**
 * API client functions for YOLO11 object detection.
 */

import type { DetectionRequest, EpisodeDetectionSummary } from '@/types/detection';

import { apiClient } from './client';

/**
 * Run YOLO11 object detection on episode frames.
 */
export async function runDetection(
  datasetId: string,
  episodeIdx: number,
  request: DetectionRequest = {}
): Promise<EpisodeDetectionSummary> {
  const url = `/api/datasets/${datasetId}/episodes/${episodeIdx}/detect`;
  const result = await apiClient.post<EpisodeDetectionSummary>(url, request);
  return result;
}

/**
 * Get cached detection results for an episode.
 */
export async function getDetections(
  datasetId: string,
  episodeIdx: number
): Promise<EpisodeDetectionSummary | null> {
  return apiClient.get<EpisodeDetectionSummary | null>(
    `/api/datasets/${datasetId}/episodes/${episodeIdx}/detections`
  );
}

/**
 * Clear cached detection results for an episode.
 */
export async function clearDetections(
  datasetId: string,
  episodeIdx: number
): Promise<{ cleared: boolean }> {
  return apiClient.delete<{ cleared: boolean }>(
    `/api/datasets/${datasetId}/episodes/${episodeIdx}/detections`
  );
}
