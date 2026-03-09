import { RotateCcw } from 'lucide-react'

import { LabelPanel } from '@/components/annotation-panel'
import {
  ColorAdjustmentControls,
  FrameInsertionToolbar,
  FrameRemovalToolbar,
  TrajectoryEditor,
  TransformControls,
} from '@/components/frame-editor'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Separator } from '@/components/ui/separator'

interface AnnotationWorkspaceEditToolsPanelProps {
  episodeIndex: number
  onClearTransforms: () => void
  canResetTransforms: boolean
}

export function AnnotationWorkspaceEditToolsPanel({
  episodeIndex,
  onClearTransforms,
  canResetTransforms,
}: AnnotationWorkspaceEditToolsPanelProps) {
  return (
    <div className="flex flex-col min-h-0 overflow-y-auto">
      <Card>
        <CardHeader className="px-4 py-3">
          <CardTitle className="text-sm">Edit Tools</CardTitle>
        </CardHeader>
        <CardContent className="space-y-6 p-4 pt-0">
          <LabelPanel episodeIndex={episodeIndex} />

          <Separator />
          <FrameRemovalToolbar />

          <Separator />
          <FrameInsertionToolbar />

          <Separator />
          <div>
            <h3 className="mb-3 text-sm font-medium">Image Transform</h3>
            <TransformControls />
          </div>

          <Separator />
          <ColorAdjustmentControls />

          <Separator />
          <div>
            <h3 className="mb-3 text-sm font-medium">Trajectory Adjustment</h3>
            <TrajectoryEditor />
          </div>

          <Separator />
          <Button
            variant="outline"
            size="sm"
            onClick={onClearTransforms}
            disabled={!canResetTransforms}
            className="w-full"
          >
            <RotateCcw className="mr-2 h-4 w-4" />
            Reset All Image Transforms
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
