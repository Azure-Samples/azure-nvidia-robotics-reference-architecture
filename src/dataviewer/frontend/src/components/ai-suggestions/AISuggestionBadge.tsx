/**
 * Badge showing AI suggestion confidence level.
 */

import { cn } from '@/lib/utils';
import { Sparkles, Loader2 } from 'lucide-react';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';

export interface AISuggestionBadgeProps {
  /** Confidence level 0-1 */
  confidence?: number;
  /** Whether the suggestion is loading */
  isLoading?: boolean;
  /** Whether there's an error */
  hasError?: boolean;
  /** Whether the suggestion was accepted */
  isAccepted?: boolean;
  /** Additional class names */
  className?: string;
  /** Click handler */
  onClick?: () => void;
}

/**
 * Displays AI suggestion status with confidence indicator.
 */
export function AISuggestionBadge({
  confidence,
  isLoading = false,
  hasError = false,
  isAccepted = false,
  className,
  onClick,
}: AISuggestionBadgeProps) {
  // Determine color based on state and confidence
  const getColorClasses = () => {
    if (hasError) {
      return 'bg-red-100 text-red-700 border-red-200';
    }
    if (isAccepted) {
      return 'bg-green-100 text-green-700 border-green-200';
    }
    if (isLoading || confidence === undefined) {
      return 'bg-gray-100 text-gray-500 border-gray-200';
    }
    if (confidence >= 0.8) {
      return 'bg-blue-100 text-blue-700 border-blue-200';
    }
    if (confidence >= 0.5) {
      return 'bg-yellow-100 text-yellow-700 border-yellow-200';
    }
    return 'bg-orange-100 text-orange-700 border-orange-200';
  };

  const getConfidenceLabel = () => {
    if (hasError) return 'Error';
    if (isAccepted) return 'Applied';
    if (isLoading) return 'Analyzing...';
    if (confidence === undefined) return 'No data';
    if (confidence >= 0.8) return 'High confidence';
    if (confidence >= 0.5) return 'Medium confidence';
    return 'Low confidence';
  };

  const getTooltipContent = () => {
    if (hasError) return 'Failed to get AI suggestion';
    if (isAccepted) return 'AI suggestion was applied';
    if (isLoading) return 'AI is analyzing the trajectory...';
    if (confidence === undefined) return 'No trajectory data available';
    return `AI confidence: ${Math.round(confidence * 100)}%`;
  };

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <button
            type="button"
            onClick={onClick}
            disabled={isLoading || hasError}
            className={cn(
              'inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full border transition-colors',
              getColorClasses(),
              onClick && !isLoading && !hasError && 'hover:opacity-80 cursor-pointer',
              (isLoading || hasError) && 'cursor-default',
              className
            )}
          >
            {isLoading ? (
              <Loader2 className="h-3 w-3 animate-spin" />
            ) : (
              <Sparkles className="h-3 w-3" />
            )}
            <span>{getConfidenceLabel()}</span>
          </button>
        </TooltipTrigger>
        <TooltipContent side="bottom">
          <p>{getTooltipContent()}</p>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}
