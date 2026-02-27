/**
 * Anomaly list component displaying detected anomalies.
 */

import { Trash2, CheckCircle, Zap, AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import type { Anomaly } from '@/types';

interface AnomalyListProps {
  /** List of anomalies */
  anomalies: Anomaly[];
  /** Callback to remove an anomaly */
  onRemove: (id: string) => void;
  /** Callback to toggle verified status */
  onToggleVerified: (id: string) => void;
  /** Callback when clicking an anomaly to seek */
  onSeek?: (frame: number) => void;
}

/**
 * Displays a list of anomalies with severity and verification status.
 *
 * @example
 * ```tsx
 * <AnomalyList
 *   anomalies={annotation.anomalies}
 *   onRemove={handleRemove}
 *   onToggleVerified={handleVerify}
 *   onSeek={seekToFrame}
 * />
 * ```
 */
export function AnomalyList({
  anomalies,
  onRemove,
  onToggleVerified,
  onSeek,
}: AnomalyListProps) {
  if (anomalies.length === 0) {
    return (
      <p className="text-sm text-muted-foreground text-center py-4">
        No anomalies detected
      </p>
    );
  }

  const severityColors = {
    low: 'border-yellow-200 bg-yellow-50',
    medium: 'border-orange-200 bg-orange-50',
    high: 'border-red-200 bg-red-50',
  };

  const severityBadgeColors = {
    low: 'bg-yellow-200 text-yellow-800',
    medium: 'bg-orange-200 text-orange-800',
    high: 'bg-red-200 text-red-800',
  };

  return (
    <div className="space-y-2 max-h-48 overflow-y-auto">
      {anomalies.map((anomaly) => (
        <div
          key={anomaly.id}
          className={cn(
            'flex items-start gap-2 p-2 rounded-md border',
            severityColors[anomaly.severity]
          )}
        >
          <AlertTriangle
            className={cn(
              'h-4 w-4 shrink-0 mt-0.5',
              anomaly.severity === 'high' && 'text-red-500',
              anomaly.severity === 'medium' && 'text-orange-500',
              anomaly.severity === 'low' && 'text-yellow-500'
            )}
          />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-sm font-medium capitalize">
                {anomaly.type.replace(/_/g, ' ')}
              </span>
              <span
                className={cn(
                  'text-xs px-1.5 rounded',
                  severityBadgeColors[anomaly.severity]
                )}
              >
                {anomaly.severity}
              </span>
              {anomaly.autoDetected && (
                <span className="text-xs px-1.5 rounded bg-blue-100 text-blue-700 flex items-center gap-0.5">
                  <Zap className="h-3 w-3" />
                  auto
                </span>
              )}
              {anomaly.verified && (
                <span className="text-xs px-1.5 rounded bg-green-100 text-green-700 flex items-center gap-0.5">
                  <CheckCircle className="h-3 w-3" />
                  verified
                </span>
              )}
            </div>
            <p className="text-xs text-muted-foreground mt-0.5 truncate">
              {anomaly.description}
            </p>
            <button
              onClick={() => onSeek?.(anomaly.frameRange[0])}
              className="text-xs text-primary hover:underline mt-0.5"
            >
              Frames {anomaly.frameRange[0]}-{anomaly.frameRange[1]}
            </button>
          </div>
          <div className="flex gap-1 shrink-0">
            {anomaly.autoDetected && (
              <Button
                variant="ghost"
                size="icon"
                className="h-6 w-6"
                onClick={() => onToggleVerified(anomaly.id)}
                title={anomaly.verified ? 'Mark unverified' : 'Mark verified'}
              >
                <CheckCircle
                  className={cn(
                    'h-3 w-3',
                    anomaly.verified ? 'text-green-500' : 'text-muted-foreground'
                  )}
                />
              </Button>
            )}
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={() => onRemove(anomaly.id)}
            >
              <Trash2 className="h-3 w-3" />
            </Button>
          </div>
        </div>
      ))}
    </div>
  );
}
