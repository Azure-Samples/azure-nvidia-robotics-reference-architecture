/**
 * Offline status indicator component.
 */

import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';
import { Progress } from '@/components/ui/progress';
import {
  Wifi,
  WifiOff,
  RefreshCw,
  Cloud,
  Check,
  AlertTriangle,
  Loader2,
} from 'lucide-react';
import { useOfflineAnnotations } from '@/hooks/use-offline-annotations';

export interface OfflineIndicatorProps {
  /** Additional class names */
  className?: string;
}

/**
 * Displays offline status and sync information.
 */
export function OfflineIndicator({ className }: OfflineIndicatorProps) {
  const {
    isOnline,
    pendingCount,
    isSyncing,
    lastSyncResult,
    sync,
  } = useOfflineAnnotations();

  const handleSync = async () => {
    await sync();
  };

  // Determine status
  const hasErrors = lastSyncResult?.failedCount && lastSyncResult.failedCount > 0;
  const hasPending = pendingCount > 0;

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className={cn('gap-2', className)}
        >
          {!isOnline ? (
            <>
              <WifiOff className="h-4 w-4 text-red-500" />
              <span className="text-red-500">Offline</span>
            </>
          ) : isSyncing ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin text-blue-500" />
              <span className="text-blue-500">Syncing...</span>
            </>
          ) : hasPending ? (
            <>
              <Cloud className="h-4 w-4 text-yellow-500" />
              <Badge variant="secondary" className="h-5 px-1.5">
                {pendingCount}
              </Badge>
            </>
          ) : hasErrors ? (
            <>
              <AlertTriangle className="h-4 w-4 text-orange-500" />
              <span className="text-orange-500">Sync errors</span>
            </>
          ) : (
            <>
              <Wifi className="h-4 w-4 text-green-500" />
              <Check className="h-3 w-3 text-green-500" />
            </>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-72">
        <div className="space-y-3">
          {/* Connection status */}
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium">Connection Status</span>
            <Badge variant={isOnline ? 'default' : 'destructive'}>
              {isOnline ? (
                <>
                  <Wifi className="h-3 w-3 mr-1" />
                  Online
                </>
              ) : (
                <>
                  <WifiOff className="h-3 w-3 mr-1" />
                  Offline
                </>
              )}
            </Badge>
          </div>

          {/* Pending changes */}
          <div className="space-y-1">
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">Pending changes</span>
              <span className="font-medium">{pendingCount}</span>
            </div>
            {hasPending && (
              <Progress value={0} className="h-1.5" />
            )}
          </div>

          {/* Last sync result */}
          {lastSyncResult && (
            <div className="text-xs text-muted-foreground space-y-1">
              <p>
                Last sync: {lastSyncResult.syncedCount} synced
                {lastSyncResult.failedCount > 0 && (
                  <span className="text-red-500">
                    , {lastSyncResult.failedCount} failed
                  </span>
                )}
              </p>
              {lastSyncResult.errors.length > 0 && (
                <div className="max-h-20 overflow-auto rounded bg-red-50 p-2">
                  {lastSyncResult.errors.slice(0, 3).map((err) => (
                    <p key={err.id} className="text-red-600 truncate">
                      {err.error}
                    </p>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Sync button */}
          <Button
            onClick={handleSync}
            disabled={!isOnline || isSyncing || pendingCount === 0}
            className="w-full"
            size="sm"
          >
            {isSyncing ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                Syncing...
              </>
            ) : (
              <>
                <RefreshCw className="h-4 w-4 mr-2" />
                Sync Now
              </>
            )}
          </Button>

          {/* Offline mode info */}
          {!isOnline && (
            <p className="text-xs text-muted-foreground">
              Changes are saved locally and will sync when you're back online.
            </p>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}
