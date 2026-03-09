import { Activity,Check, ChevronsUpDown } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';

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
import type { DatasetInfo } from '@/types';

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

interface DataviewerShellHeaderProps {
  datasetId: string;
  datasets: DatasetInfo[];
  diagnosticsVisible: boolean;
  onSelectDataset: (datasetId: string) => void;
  onToggleDiagnostics: () => void;
  capabilities?: {
    isLerobotDataset?: boolean;
    hasHdf5Files?: boolean;
  };
}

export function DataviewerShellHeader({
  datasetId,
  datasets,
  diagnosticsVisible,
  onSelectDataset,
  onToggleDiagnostics,
  capabilities,
}: DataviewerShellHeaderProps) {
  return (
    <header className="bg-card border-b px-4 py-2.5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0 flex items-baseline gap-2">
          <h1 className="truncate text-xl font-semibold leading-none">Robotic Training Data Analysis</h1>
          <p className="hidden text-sm text-muted-foreground lg:block">
            Episode annotation system for robot demonstration datasets
          </p>
        </div>
        <div className="flex flex-wrap items-center justify-end gap-2">
          <label htmlFor="dataset-selector" className="text-sm">Dataset:</label>
          <DatasetSelector
            datasetId={datasetId}
            datasets={datasets}
            onSelectDataset={onSelectDataset}
          />
          <Button
            variant={diagnosticsVisible ? 'default' : 'outline'}
            size="sm"
            onClick={onToggleDiagnostics}
            aria-label="Toggle Diagnostics"
            title={diagnosticsVisible ? 'Diagnostics on (click to hide)' : 'Diagnostics off (click to show)'}
          >
            <Activity className="mr-1.5 h-3.5 w-3.5" />
            Diagnostics
          </Button>
          {capabilities?.isLerobotDataset && (
            <Badge variant="secondary">LeRobot</Badge>
          )}
          {capabilities?.hasHdf5Files && !capabilities?.isLerobotDataset && (
            <Badge variant="outline">HDF5</Badge>
          )}
        </div>
      </div>
    </header>
  );
}
