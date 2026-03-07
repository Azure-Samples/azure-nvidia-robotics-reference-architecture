import { QueryClientProvider } from '@tanstack/react-query';
import { Check, ChevronsUpDown } from 'lucide-react';
import { memo, useCallback, useEffect, useRef, useState } from 'react';

import { LabelFilter } from '@/components/annotation-panel';
import { AnnotationWorkspace } from '@/components/annotation-workspace/AnnotationWorkspace';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from '@/components/ui/command';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { TooltipProvider } from '@/components/ui/tooltip';
import { useCapabilities,useDatasets, useEpisode, useEpisodes } from '@/hooks/use-datasets';
import { useJointConfig } from '@/hooks/use-joint-config';
import { useDatasetLabels } from '@/hooks/use-labels';
import { queryClient } from '@/lib/query-client';
import { useDatasetStore,useEpisodeStore } from '@/stores';
import { useLabelStore } from '@/stores/label-store';
import type { DatasetInfo, EpisodeMeta } from '@/types';

/**
 * Memoized episode list item to prevent re-renders on sibling selection changes.
 */
const EpisodeListItem = memo(function EpisodeListItem({
  episode,
  isSelected,
  onSelect,
  labels,
}: {
  episode: EpisodeMeta;
  isSelected: boolean;
  onSelect: (index: number) => void;
  labels: string[];
}) {
  const handleClick = useCallback(() => {
    onSelect(episode.index);
  }, [onSelect, episode.index]);

  return (
    <li>
      <button
        onClick={handleClick}
        className={`w-full text-left px-4 py-3 hover:bg-accent transition-colors ${isSelected ? 'bg-accent' : ''
          }`}
      >
        <div className="font-medium">Episode {episode.index}</div>
        <div className="text-sm text-muted-foreground">
          {episode.length} frames • Task {episode.taskIndex}
          {episode.hasAnnotations && (
            <span className="ml-2 text-green-600">✓ Annotated</span>
          )}
        </div>
        {labels.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-1">
            {labels.map((label) => (
              <span
                key={label}
                className="inline-flex items-center rounded-full bg-primary/10 text-primary text-[10px] px-1.5 py-0 font-medium"
              >
                {label}
              </span>
            ))}
          </div>
        )}
      </button>
    </li>
  );
});

function EpisodeList({
  datasetId,
  onSelectEpisode,
  selectedIndex,
}: {
  datasetId: string;
  onSelectEpisode: (index: number) => void;
  selectedIndex: number;
}) {
  const { data: episodes, isLoading, error } = useEpisodes(datasetId, { limit: 100 });
  const episodeLabels = useLabelStore((state) => state.episodeLabels);
  const filterLabels = useLabelStore((state) => state.filterLabels);

  if (isLoading) {
    return <div className="p-4 text-muted-foreground">Loading episodes...</div>;
  }

  if (error) {
    return <div className="p-4 text-red-500">Error: {error.message}</div>;
  }

  if (!episodes || episodes.length === 0) {
    return <div className="p-4 text-muted-foreground">No episodes found</div>;
  }

  const filteredEpisodes = filterLabels.length > 0
    ? episodes.filter((ep: EpisodeMeta) => {
      const epLabels = episodeLabels[ep.index] || [];
      return filterLabels.some((fl) => epLabels.includes(fl));
    })
    : episodes;

  return (
    <div className="overflow-y-auto h-full flex flex-col">
      <LabelFilter />
      <div className="p-2 text-sm font-medium text-muted-foreground border-b">
        {filteredEpisodes.length}{filterLabels.length > 0 ? ` / ${episodes.length}` : ''} Episodes
      </div>
      <ul className="divide-y flex-1 overflow-y-auto">
        {filteredEpisodes.map((episode: EpisodeMeta) => (
          <EpisodeListItem
            key={episode.index}
            episode={episode}
            isSelected={selectedIndex === episode.index}
            onSelect={onSelectEpisode}
            labels={episodeLabels[episode.index] || []}
          />
        ))}
      </ul>
    </div>
  );
}

function EpisodeViewer({ datasetId, episodeIndex }: { datasetId: string; episodeIndex: number }) {
  const { data: episode, isLoading, error } = useEpisode(datasetId, episodeIndex);
  const setCurrentEpisode = useEpisodeStore((state) => state.setCurrentEpisode);
  const setDatasets = useDatasetStore((state) => state.setDatasets);
  const selectDataset = useDatasetStore((state) => state.selectDataset);

  // Sync dataset and episode to stores for AnnotationWorkspace
  useEffect(() => {
    // Create a minimal dataset info object for the store
    setDatasets([{
      id: datasetId,
      name: datasetId,
      totalEpisodes: 0,
      fps: 15,
      features: {},
      tasks: []
    }]);
    selectDataset(datasetId);
  }, [datasetId, setDatasets, selectDataset]);

  useEffect(() => {
    if (episode) {
      setCurrentEpisode(episode);
    }
  }, [episode, setCurrentEpisode]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-muted-foreground">Loading episode {episodeIndex}...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-red-500">Error loading episode: {error.message}</div>
      </div>
    );
  }

  if (!episode) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-muted-foreground">No episode data</div>
      </div>
    );
  }

  // Render the new AnnotationWorkspace with all features
  return <AnnotationWorkspace />;
}

function DatasetSelector({
  datasetId,
  datasets,
  onSelectDataset,
}: {
  datasetId: string;
  datasets: DatasetInfo[];
  onSelectDataset: (datasetId: string) => void;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const [filterText, setFilterText] = useState('');
  const filterInputRef = useRef<HTMLInputElement>(null);

  const selectedDataset = datasets.find((dataset) => dataset.id === datasetId) ?? null;
  const normalizedFilter = filterText.trim().toLowerCase();
  const filteredDatasets = normalizedFilter
    ? datasets.filter((dataset) => {
      const searchableText = `${dataset.id} ${dataset.name}`.toLowerCase();
      return searchableText.includes(normalizedFilter);
    })
    : datasets;

  const handleOpenChange = (open: boolean) => {
    setIsOpen(open);

    if (!open) {
      setFilterText('');
    }
  };

  useEffect(() => {
    if (isOpen) {
      filterInputRef.current?.focus();
    }
  }, [isOpen]);

  return (
    <Popover open={isOpen} onOpenChange={handleOpenChange}>
      <PopoverTrigger asChild>
        <Button
          id="dataset-selector"
          type="button"
          variant="outline"
          role="combobox"
          aria-label="Dataset"
          aria-expanded={isOpen}
          aria-controls="dataset-selector-listbox"
          className="w-72 justify-between font-normal"
        >
          <span className="truncate text-left">{selectedDataset?.id || 'Select a dataset'}</span>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-72 p-2" align="end">
        <Command shouldFilter={false}>
          <CommandInput
            ref={filterInputRef}
            value={filterText}
            onValueChange={setFilterText}
            placeholder="Filter datasets"
            aria-label="Filter datasets"
          />
          <CommandList
            id="dataset-selector-listbox"
            role="listbox"
            aria-label="Available datasets"
            className="max-h-60"
          >
            <CommandEmpty>No datasets match the current filter.</CommandEmpty>
            <CommandGroup>
              {filteredDatasets.map((dataset) => {
                const isSelected = dataset.id === datasetId;

                return (
                  <CommandItem
                    key={dataset.id}
                    value={dataset.id}
                    keywords={[dataset.name]}
                    role="option"
                    aria-selected={isSelected}
                    onSelect={() => {
                      onSelectDataset(dataset.id);
                      setIsOpen(false);
                      setFilterText('');
                    }}
                    className="items-start justify-between gap-2 px-3 py-2 text-left"
                  >
                    <span className="min-w-0">
                      <span className="block truncate font-medium">{dataset.id}</span>
                      {dataset.name !== dataset.id && (
                        <span className="block truncate text-xs text-muted-foreground">
                          {dataset.name}
                        </span>
                      )}
                    </span>
                    <Check
                      className={isSelected ? 'ml-2 mt-0.5 h-4 w-4 shrink-0 opacity-100' : 'ml-2 mt-0.5 h-4 w-4 shrink-0 opacity-0'}
                    />
                  </CommandItem>
                );
              })}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}

export function AppContent() {
  const [datasetId, setDatasetId] = useState('');
  const [selectedEpisode, setSelectedEpisode] = useState<number>(0);
  const { data: datasets } = useDatasets();
  const { data: capabilities } = useCapabilities(datasetId || undefined);

  // Load labels for the selected dataset
  useDatasetLabels();

  // Load joint configuration for the selected dataset
  useJointConfig();

  // Keep the active dataset aligned with the latest dataset list.
  useEffect(() => {
    if (!datasets || datasets.length === 0) {
      if (datasetId) {
        setDatasetId('');
        setSelectedEpisode(0);
      }
      return;
    }

    const hasSelectedDataset = datasets.some((dataset) => dataset.id === datasetId);

    if (!datasetId || !hasSelectedDataset) {
      setDatasetId(datasets[0].id);
      setSelectedEpisode(0);
    }
  }, [datasets, datasetId]);

  return (
    <div className="flex flex-col h-screen">
      {/* Header */}
      <header className="bg-card border-b px-6 py-4 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Robotic Training Data Analysis</h1>
          <p className="text-sm text-muted-foreground">
            Episode annotation system for robot demonstration datasets
          </p>
        </div>
        <div className="flex items-center gap-2">
          <label htmlFor="dataset-selector" className="text-sm">Dataset:</label>
          <DatasetSelector
            datasetId={datasetId}
            datasets={datasets ?? []}
            onSelectDataset={(nextDatasetId) => {
              setDatasetId(nextDatasetId);
              setSelectedEpisode(0);
            }}
          />
          {capabilities?.isLerobotDataset && (
            <Badge variant="secondary">LeRobot</Badge>
          )}
          {capabilities?.hasHdf5Files && !capabilities?.isLerobotDataset && (
            <Badge variant="outline">HDF5</Badge>
          )}
        </div>
      </header>

      {/* Main Content */}
      <div className="flex flex-1 min-h-0">
        {/* Episode List Sidebar */}
        <aside className="w-64 border-r bg-card overflow-hidden flex flex-col">
          <EpisodeList
            datasetId={datasetId}
            onSelectEpisode={setSelectedEpisode}
            selectedIndex={selectedEpisode}
          />
        </aside>

        {/* Episode Viewer */}
        <main className="flex-1 overflow-hidden bg-background">
          <EpisodeViewer datasetId={datasetId} episodeIndex={selectedEpisode} />
        </main>
      </div>
    </div>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <AppContent />
      </TooltipProvider>
    </QueryClientProvider>
  );
}

export default App
