import type { ExportResult, ExportProgress, EpisodeEditOperations } from '@/types';

export interface ExportPreviewStats {
  totalEpisodes: number;
  totalFrames: number;
  estimatedOutputSize: string;
  removedFramesCount: number;
}

/** Extended export request with per-episode edits */
export interface ExportRequestWithEdits {
  episodeIndices: number[];
  outputPath: string;
  applyEdits: boolean;
  includeSubtasks: boolean;
  format: 'hdf5' | 'parquet';
  edits?: Record<number, EpisodeEditOperations>;
}

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';
const DATASETS_API = `${API_BASE_URL}/api/datasets`;

/**
 * Start a synchronous export operation
 */
export async function exportEpisodes(
  datasetId: string,
  request: ExportRequestWithEdits
): Promise<ExportResult> {
  const response = await fetch(`${DATASETS_API}/${datasetId}/export`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  if (!response.ok) {
    throw new Error(`Export failed: ${response.statusText}`);
  }
  return response.json();
}

/**
 * Get preview statistics for an export operation
 */
export async function getExportPreview(
  datasetId: string,
  episodeIndices: number[],
  removedFrames?: number[]
): Promise<ExportPreviewStats> {
  const params = new URLSearchParams();
  params.set('episode_indices', episodeIndices.join(','));
  if (removedFrames?.length) {
    params.set('removed_frames', removedFrames.join(','));
  }
  const response = await fetch(
    `${DATASETS_API}/${datasetId}/export/preview?${params.toString()}`
  );
  if (!response.ok) {
    throw new Error(`Preview failed: ${response.statusText}`);
  }
  return response.json();
}

/**
 * Start a streaming export with SSE progress updates
 * Returns a cleanup function to close the connection
 */
export function createExportStream(
  datasetId: string,
  request: ExportRequestWithEdits,
  onProgress: (progress: ExportProgress) => void,
  onComplete: (result: ExportResult) => void,
  onError: (error: string) => void
): () => void {
  // Using fetch with ReadableStream for SSE with POST body
  const url = `${DATASETS_API}/${datasetId}/export/stream`;

  const abortController = new AbortController();

  async function startStream() {
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'text/event-stream',
        },
        body: JSON.stringify(request),
        signal: abortController.signal,
      });

      if (!response.ok) {
        throw new Error(`Export failed: ${response.statusText}`);
      }

      const reader = response.body?.getReader();
      if (!reader) {
        throw new Error('No response body');
      }

      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() ?? '';

        let currentEventType = 'message';
        for (const line of lines) {
          if (line.startsWith('event: ')) {
            currentEventType = line.slice(7).trim();
            continue;
          }
          if (line.startsWith('data: ')) {
            const data = line.slice(6);
            try {
              const parsed = JSON.parse(data);
              if (currentEventType === 'error') {
                onError(parsed.message ?? 'Export failed');
              } else if ('percentage' in parsed) {
                onProgress(parsed as ExportProgress);
              } else if ('success' in parsed) {
                onComplete(parsed as ExportResult);
              }
            } catch {
              // Skip malformed JSON
            }
          }
        }
      }
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        return;
      }
      onError(error instanceof Error ? error.message : 'Export failed');
    }
  }

  startStream();

  return () => {
    abortController.abort();
  };
}

