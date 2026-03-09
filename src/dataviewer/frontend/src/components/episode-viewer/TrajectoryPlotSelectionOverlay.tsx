import { Button } from '@/components/ui/button'

interface TrajectoryPlotSelectionOverlayProps {
  selectedRange: [number, number] | null
  selectionHighlight: { left: string; width: string } | null
  contextMenuPosition: { x: number; y: number } | null
  onSelectionContextMenu: (event: React.MouseEvent<HTMLDivElement>) => void
  onSelectionPointerDown: (event: React.PointerEvent<HTMLDivElement>) => void
  onSelectionPointerMove: (event: React.PointerEvent<HTMLDivElement>) => void
  onSelectionPointerUp: (event: React.PointerEvent<HTMLDivElement>) => void
  onCreateSubtaskFromRange?: (range: [number, number]) => void
  onDismissContextMenu: () => void
  selectionSurfaceRef: React.RefObject<HTMLDivElement>
}

export function TrajectoryPlotSelectionOverlay({
  selectedRange,
  selectionHighlight,
  contextMenuPosition,
  onSelectionContextMenu,
  onSelectionPointerDown,
  onSelectionPointerMove,
  onSelectionPointerUp,
  onCreateSubtaskFromRange,
  onDismissContextMenu,
  selectionSurfaceRef,
}: TrajectoryPlotSelectionOverlayProps) {
  return (
    <div
      ref={selectionSurfaceRef}
      data-testid="trajectory-selection-surface"
      data-keep-playback-selection="true"
      className="absolute inset-0 z-10 cursor-crosshair"
      onContextMenu={onSelectionContextMenu}
      onPointerDown={onSelectionPointerDown}
      onPointerMove={onSelectionPointerMove}
      onPointerUp={onSelectionPointerUp}
    >
      {selectionHighlight && (
        <div
          className="absolute bottom-2 top-2 rounded-md border border-primary/60 bg-primary/10"
          style={selectionHighlight}
        />
      )}
      {contextMenuPosition && selectedRange && (
        <div
          data-keep-playback-selection="true"
          className="absolute z-20 rounded-md border bg-popover p-1 shadow-md"
          style={{ left: contextMenuPosition.x, top: contextMenuPosition.y }}
          onContextMenu={(event) => event.preventDefault()}
          onPointerDown={(event) => event.stopPropagation()}
          onPointerUp={(event) => event.stopPropagation()}
        >
          <Button
            type="button"
            size="sm"
            variant="ghost"
            onClick={(event) => {
              event.stopPropagation()
              onCreateSubtaskFromRange?.(selectedRange)
              onDismissContextMenu()
            }}
          >
            Create Subtask
          </Button>
        </div>
      )}
    </div>
  )
}
