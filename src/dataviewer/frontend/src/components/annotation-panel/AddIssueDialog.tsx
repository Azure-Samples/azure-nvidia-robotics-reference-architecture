/**
 * Dialog for adding a new data quality issue.
 */

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { X } from 'lucide-react';
import type { DataQualityIssue, DataQualityIssueType, IssueSeverity } from '@/types';

interface AddIssueDialogProps {
  /** Whether the dialog is open */
  open: boolean;
  /** Callback to close the dialog */
  onClose: () => void;
  /** Callback when issue is added */
  onAdd: (issue: DataQualityIssue) => void;
  /** Current frame for default frame range */
  currentFrame: number;
}

/**
 * Modal dialog for adding a new data quality issue.
 *
 * @example
 * ```tsx
 * <AddIssueDialog
 *   open={dialogOpen}
 *   onClose={() => setDialogOpen(false)}
 *   onAdd={handleAddIssue}
 *   currentFrame={42}
 * />
 * ```
 */
export function AddIssueDialog({
  open,
  onClose,
  onAdd,
  currentFrame,
}: AddIssueDialogProps) {
  const [type, setType] = useState<DataQualityIssueType>('frame-drop');
  const [severity, setSeverity] = useState<IssueSeverity>('minor');
  const [notes, setNotes] = useState('');
  const [frameStart, setFrameStart] = useState(currentFrame);
  const [frameEnd, setFrameEnd] = useState(currentFrame + 10);

  const issueTypes: DataQualityIssueType[] = [
    'frame-drop',
    'sync-issue',
    'occlusion',
    'lighting-issue',
    'sensor-noise',
    'calibration-drift',
    'encoding-artifact',
    'missing-data',
  ];

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onAdd({
      type,
      severity,
      notes: notes || undefined,
      affectedFrames: [frameStart, frameEnd],
    });
    // Reset form
    setType('frame-drop');
    setSeverity('minor');
    setNotes('');
    onClose();
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <Card className="w-full max-w-md">
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-base">Add Data Quality Issue</CardTitle>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Issue type */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Issue Type</label>
              <select
                value={type}
                onChange={(e) => setType(e.target.value as DataQualityIssueType)}
                className="w-full p-2 text-sm border rounded-md bg-background"
              >
                {issueTypes.map((t) => (
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
                {(['minor', 'major', 'critical'] as const).map((s) => (
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
              <label className="text-sm font-medium">Affected Frames</label>
              <div className="flex gap-2 items-center">
                <input
                  type="number"
                  value={frameStart}
                  onChange={(e) => setFrameStart(parseInt(e.target.value) || 0)}
                  min={0}
                  className="flex-1 p-2 text-sm border rounded-md bg-background"
                />
                <span className="text-muted-foreground">to</span>
                <input
                  type="number"
                  value={frameEnd}
                  onChange={(e) => setFrameEnd(parseInt(e.target.value) || 0)}
                  min={0}
                  className="flex-1 p-2 text-sm border rounded-md bg-background"
                />
              </div>
            </div>

            {/* Description */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Notes (optional)</label>
              <textarea
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="Describe the issue..."
                className="w-full p-2 text-sm border rounded-md bg-background min-h-[60px] resize-none"
              />
            </div>

            {/* Actions */}
            <div className="flex gap-2 pt-2">
              <Button type="button" variant="outline" onClick={onClose} className="flex-1">
                Cancel
              </Button>
              <Button type="submit" className="flex-1">
                Add Issue
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
