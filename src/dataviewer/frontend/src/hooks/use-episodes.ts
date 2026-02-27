/**
 * TanStack Query hooks for episode data fetching with store sync.
 */

import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { fetchEpisodes, fetchEpisode } from '@/lib/api-client';
import { useEpisodeStore, useDatasetStore } from '@/stores';

/**
 * Query key factory for episodes.
 */
export const episodeKeys = {
  all: ['episodes'] as const,
  lists: () => [...episodeKeys.all, 'list'] as const,
  list: (datasetId: string, filters?: Record<string, unknown>) =>
    [...episodeKeys.lists(), datasetId, filters] as const,
  details: () => [...episodeKeys.all, 'detail'] as const,
  detail: (datasetId: string, index: number) =>
    [...episodeKeys.details(), datasetId, index] as const,
};

/**
 * Hook to fetch and sync episodes with the episode store.
 *
 * Automatically fetches episodes when a dataset is selected and
 * syncs the data with the Zustand episode store.
 *
 * @example
 * ```tsx
 * const { isLoading } = useEpisodeList();
 * const episodes = useEpisodeStore(state => state.episodes);
 * ```
 */
export function useEpisodeList(options?: {
  offset?: number;
  limit?: number;
  hasAnnotations?: boolean;
  taskIndex?: number;
}) {
  const currentDataset = useDatasetStore((state) => state.currentDataset);
  const setEpisodes = useEpisodeStore((state) => state.setEpisodes);
  const setLoading = useEpisodeStore((state) => state.setLoading);
  const setError = useEpisodeStore((state) => state.setError);

  const query = useQuery({
    queryKey: episodeKeys.list(currentDataset?.id ?? '', options),
    queryFn: () => fetchEpisodes(currentDataset!.id, options),
    enabled: !!currentDataset,
    staleTime: 1 * 60 * 1000,
  });

  // Sync with Zustand store
  useEffect(() => {
    setLoading(query.isLoading);
  }, [query.isLoading, setLoading]);

  useEffect(() => {
    if (query.data) {
      setEpisodes(query.data);
    }
  }, [query.data, setEpisodes]);

  useEffect(() => {
    if (query.error) {
      setError(query.error.message);
    }
  }, [query.error, setError]);

  return query;
}

/**
 * Hook to fetch and sync the current episode with the episode store.
 *
 * Automatically fetches episode data when navigating and syncs
 * with the Zustand store.
 *
 * @example
 * ```tsx
 * const { isLoading } = useCurrentEpisode();
 * const episode = useEpisodeStore(state => state.currentEpisode);
 * ```
 */
export function useCurrentEpisode() {
  const currentDataset = useDatasetStore((state) => state.currentDataset);
  const currentIndex = useEpisodeStore((state) => state.currentIndex);
  const setCurrentEpisode = useEpisodeStore((state) => state.setCurrentEpisode);
  const setLoading = useEpisodeStore((state) => state.setLoading);
  const setError = useEpisodeStore((state) => state.setError);

  const query = useQuery({
    queryKey: episodeKeys.detail(currentDataset?.id ?? '', currentIndex),
    queryFn: () => fetchEpisode(currentDataset!.id, currentIndex),
    enabled: !!currentDataset && currentIndex >= 0,
    staleTime: 30 * 1000,
  });

  // Sync with Zustand store
  useEffect(() => {
    setLoading(query.isLoading);
  }, [query.isLoading, setLoading]);

  useEffect(() => {
    if (query.data) {
      setCurrentEpisode(query.data);
    }
  }, [query.data, setCurrentEpisode]);

  useEffect(() => {
    if (query.error) {
      setError(query.error.message);
    }
  }, [query.error, setError]);

  return query;
}

/**
 * Hook providing episode navigation with prefetching.
 *
 * @example
 * ```tsx
 * const { goNext, goPrevious, goToEpisode, canGoNext, canGoPrevious } = useEpisodeNavigation();
 * ```
 */
export function useEpisodeNavigationWithPrefetch() {
  const { episodes, currentIndex, navigateToEpisode, nextEpisode, previousEpisode } =
    useEpisodeStore();

  const canGoNext = currentIndex < episodes.length - 1;
  const canGoPrevious = currentIndex > 0;

  return {
    goToEpisode: navigateToEpisode,
    goNext: nextEpisode,
    goPrevious: previousEpisode,
    canGoNext,
    canGoPrevious,
    currentIndex,
    totalEpisodes: episodes.length,
  };
}
