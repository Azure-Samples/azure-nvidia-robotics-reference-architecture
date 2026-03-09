import { Activity, Download, RotateCcw, Scan, SkipBack, SkipForward, Video } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { TabsList, TabsTrigger } from '@/components/ui/tabs'

interface AnnotationWorkspaceTopBarProps {
  episodeIndex: number
  canGoPreviousEpisode: boolean
  onPreviousEpisode?: () => void
  hasPendingEpisodeChanges: boolean
  onResetAllClick: () => void
  onOpenExportDialog: () => void
  canGoNextEpisode: boolean
  canSaveAndNextEpisode: boolean
  onSaveAndNextEpisode: () => void
  saveStatusMessage: string | null
}

export function AnnotationWorkspaceTopBar({
  episodeIndex,
  canGoPreviousEpisode,
  onPreviousEpisode,
  hasPendingEpisodeChanges,
  onResetAllClick,
  onOpenExportDialog,
  canGoNextEpisode,
  canSaveAndNextEpisode,
  onSaveAndNextEpisode,
  saveStatusMessage,
}: AnnotationWorkspaceTopBarProps) {
  return (
    <div className="flex items-center justify-between gap-3" data-testid="workspace-top-bar">
      <div className="flex min-w-0 items-center gap-3">
        <div className="flex min-w-0 items-center gap-2">
          <h2 className="text-lg font-semibold leading-none">Episode {episodeIndex}</h2>
        </div>
        <TabsList className="h-10 w-fit shrink-0">
          <TabsTrigger value="episode" className="gap-2">
            <Video className="h-4 w-4" />
            Episode Viewer
          </TabsTrigger>
          <TabsTrigger value="trajectory" className="gap-2">
            <Activity className="h-4 w-4" />
            Trajectory Viewer
          </TabsTrigger>
          <TabsTrigger value="detection" className="gap-2">
            <Scan className="h-4 w-4" />
            Object Detection
          </TabsTrigger>
        </TabsList>
      </div>
      <div className="flex shrink-0 flex-col items-end justify-center gap-1" data-testid="workspace-header-actions">
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="icon"
            onClick={onPreviousEpisode}
            disabled={!canGoPreviousEpisode || !onPreviousEpisode}
            aria-label="Previous Episode"
            title="Previous Episode"
          >
            <SkipBack className="h-4 w-4" />
          </Button>
          <Button variant="outline" onClick={onResetAllClick} disabled={!hasPendingEpisodeChanges}>
            <RotateCcw className="mr-2 h-4 w-4" />
            Reset All
          </Button>
          <Button variant="outline" onClick={onOpenExportDialog}>
            <Download className="mr-2 h-4 w-4" />
            Export
          </Button>
          <Button
            onClick={onSaveAndNextEpisode}
            disabled={!canGoNextEpisode || !canSaveAndNextEpisode}
          >
            <SkipForward className="mr-2 h-4 w-4" />
            Save & Next Episode
          </Button>
        </div>
        <div className="min-h-[1rem]" data-testid="workspace-save-status-slot">
          {saveStatusMessage && (
            <p data-testid="workspace-save-status" className="text-xs text-muted-foreground">
              {saveStatusMessage}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
