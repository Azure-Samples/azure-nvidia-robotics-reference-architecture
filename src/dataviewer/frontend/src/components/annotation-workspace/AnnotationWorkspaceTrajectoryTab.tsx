import type { ReactNode } from 'react'

import { TrajectoryPlot } from '@/components/episode-viewer'
import { SubtaskTimelineTrack, SubtaskToolbar } from '@/components/subtask-timeline'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { TabsContent } from '@/components/ui/tabs'

interface AnnotationWorkspaceTrajectoryTabProps {
  playbackCard: ReactNode
  subtaskListCard: ReactNode
  selectedRange: [number, number] | null
  selectedSubtaskId: string | null
  onClearPlaybackSelection: () => void
  onDraftRangeChange: (range: [number, number] | null) => void
  onCreateSubtaskFromRange: (range: [number, number]) => void
  onGraphSeek: (frame: number) => void
  onSelectionStart: () => void
  onSelectionComplete: (range: [number, number]) => void
  totalFrames: number
  onSubtaskSelectionChange: (id: string | null) => void
}

export function AnnotationWorkspaceTrajectoryTab({
  playbackCard,
  subtaskListCard,
  selectedRange,
  selectedSubtaskId,
  onClearPlaybackSelection,
  onDraftRangeChange,
  onCreateSubtaskFromRange,
  onGraphSeek,
  onSelectionStart,
  onSelectionComplete,
  totalFrames,
  onSubtaskSelectionChange,
}: AnnotationWorkspaceTrajectoryTabProps) {
  return (
    <TabsContent value="trajectory" className="mt-2.5 flex-1 min-h-0">
      <div className="grid h-full grid-cols-1 gap-4 xl:grid-cols-[minmax(320px,420px)_minmax(0,1fr)]">
        <div className="flex min-h-[320px] flex-col gap-4 xl:min-h-0">
          {playbackCard}
          {subtaskListCard}
        </div>
        <Card className="min-h-[340px] xl:min-h-0">
          <CardContent className="flex h-full min-h-0 flex-col gap-3 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h3 className="text-sm font-medium">Trajectory Graph</h3>
                <p className="text-xs text-muted-foreground">
                  Review joint motion, filters, and subtask boundaries alongside a compact episode player.
                </p>
              </div>
              {(selectedRange || selectedSubtaskId) && (
                <Button size="sm" variant="outline" onClick={onClearPlaybackSelection}>
                  Clear Selection
                </Button>
              )}
            </div>
            <TrajectoryPlot
              className="flex-1 min-h-[280px]"
              selectedRange={selectedRange}
              onSelectedRangeChange={onDraftRangeChange}
              onCreateSubtaskFromRange={onCreateSubtaskFromRange}
              onSeekFrame={onGraphSeek}
              onSelectionStart={onSelectionStart}
              onSelectionComplete={onSelectionComplete}
            />
            <div className="rounded-lg border bg-muted/20 p-3">
              <div className="mb-2 flex items-center justify-between gap-3">
                <div>
                  <h4 className="text-sm font-medium">Subtask Timeline</h4>
                  <p className="text-xs text-muted-foreground">
                    Compare subtask ranges directly against trajectory changes on the same frame timeline.
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <SubtaskToolbar
                  selectedSegmentId={selectedSubtaskId}
                  onSelectionChange={onSubtaskSelectionChange}
                />
              </div>
              <SubtaskTimelineTrack
                totalFrames={totalFrames}
                editable
                selectedSegmentId={selectedSubtaskId}
                draftRange={selectedRange}
                onSegmentClick={(segment) => onSubtaskSelectionChange(segment.id)}
              />
            </div>
          </CardContent>
        </Card>
      </div>
    </TabsContent>
  )
}
