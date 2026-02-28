/**
 * Dialog for adding a new anomaly.
 */

import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { X, MapPin } from 'lucide-react';
import type { Anomaly, AnomalyType, AnomalySeverity } from '@/types';

interface AddAnomalyDialogProps {
  /** Whether the dialog is open */
  open: boolean;
  /** Callback to close the dialog */
  onClose: () => void;
  /** Callback when anomaly is added */
  onAdd: (anomaly: Omit<Anomaly, 'id'>) => void;
  /** Current frame for default frame range */
  currentFrame: number;
}

/**
 * Modal dialog for adding a new anomaly with frame range selection.
 *
 * @example
 * ```tsx
 * <AddAnomalyDialog
 *   open={dialogOpen}
 *   onClose={() => setDialogOpen(false)}
 *   onAdd={handleAddAnomaly}
 *   currentFrame={42}
 * />
 * ```
 */
export function AddAnomalyDialog({
  open,
  onClose,
  onAdd,
  currentFrame,
}: AddAnomalyDialogProps) {
  const [type, setType] = useState<AnomalyType>('unexpected-stop');
  const [severity, setSeverity] = useState<AnomalySeverity>('medium');
  const [description, setDescription] = useState('');
  const [frameStart, setFrameStart] = useState(currentFrame);
  const [frameEnd, setFrameEnd] = useState(currentFrame + 10);

  // Assume 30fps for timestamp calculation
  const FPS = 30;

  // Update frame start when current frame changes
  useEffect(() => {
    if (open) {
      setFrameStart(currentFrame);
      setFrameEnd(currentFrame + 10);
    }
  }, [open, currentFrame]);

  const anomalyTypes: AnomalyType[] = [
    'unexpected-stop',
    'trajectory-deviation',
    'force-spike',
    'velocity-spike',
    'object-slip',
    'gripper-failure',
    'collision',
    'other',
  ];

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onAdd({
      type,
      severity,
      description: description || `${type.replace(/-/g, ' ')} detected`,
      frameRange: [frameStart, frameEnd],
      timestamp: [frameStart / FPS, frameEnd / FPS],
      verified: true, // Manual additions are verified
      autoDetected: false,
    });
    // Reset form
    setType('unexpected-stop');
    setSeverity('medium');
    setDescription('');
    onClose();
  };

  const setCurrentAsStart = () => {
    setFrameStart(currentFrame);
    if (frameEnd < currentFrame) {
      setFrameEnd(currentFrame + 10);
    }
  };

  const setCurrentAsEnd = () => {
    setFrameEnd(currentFrame);
    if (frameStart > currentFrame) {
      setFrameStart(Math.max(0, currentFrame - 10));
    }
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <Card className="w-full max-w-md">
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-base">Add Anomaly</CardTitle>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Anomaly type */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Anomaly Type</label>
              <select
                value={type}
                onChange={(e) => setType(e.target.value as AnomalyType)}
                className="w-full p-2 text-sm border rounded-md bg-background"
              >
                {anomalyTypes.map((t) => (
                  <option key={t} value={t}>
                    {t.replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())}
                  </option>
                ))}
              </select>
            </div>

            {/* Severity */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Severity</label>
              <div className="flex gap-2">
                {(['low', 'medium', 'high'] as const).map((s) => (
                  <Button
                    key={s}
                    type="button"
                    variant={severity === s ? 'default' : 'outline'}
                    size="sm"
                    onClick={() => setSeverity(s)}
                    className="flex-1 capitalize"
                  >
                    {s}
                  </Button>
                ))}
              </div>
            </div>

            {/* Frame range */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Frame Range</label>
              <div className="flex gap-2 items-center">
                <div className="flex-1 flex gap-1">
                  <input
                    type="number"
                    value={frameStart}
                    onChange={(e) => setFrameStart(parseInt(e.target.value) || 0)}
                    min={0}
                    className="flex-1 p-2 text-sm border rounded-md bg-background"
                  />
                  <Button
                    type="button"
                    variant="outline"
                    size="icon"
                    onClick={setCurrentAsStart}
                    title="Use current frame as start"
                    className="shrink-0"
                  >
                    <MapPin className="h-4 w-4" />
                  </Button>
                </div>
                <span className="text-muted-foreground">to</span>
                <div className="flex-1 flex gap-1">
                  <input
                    type="number"
                    value={frameEnd}
                    onChange={(e) => setFrameEnd(parseInt(e.target.value) || 0)}
                    min={0}
                    className="flex-1 p-2 text-sm border rounded-md bg-background"
                  />
                  <Button
                    type="button"
                    variant="outline"
                    size="icon"
                    onClick={setCurrentAsEnd}
                    title="Use current frame as end"
                    className="shrink-0"
                  >
                    <MapPin className="h-4 w-4" />
                  </Button>
                </div>
              </div>
              <p className="text-xs text-muted-foreground">
                Current frame: {currentFrame}. Click pin icons to set from video position.
              </p>
            </div>

            {/* Description */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Description</label>
              <textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Describe the anomaly..."
                className="w-full p-2 text-sm border rounded-md bg-background min-h-[60px] resize-none"
              />
            </div>

            {/* Actions */}
            <div className="flex gap-2 pt-2">
              <Button type="button" variant="outline" onClick={onClose} className="flex-1">
                Cancel
              </Button>
              <Button type="submit" className="flex-1">
                Add Anomaly
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
