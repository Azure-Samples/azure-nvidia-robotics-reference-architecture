/**
 * Custom playback controls for the video player.
 */

import { usePlaybackControls } from '@/stores';
import { Button } from '@/components/ui/button';
import {
  Pause,
  Play,
  SkipBack,
  SkipForward,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';

interface PlaybackControlsProps {
  /** Current frame number */
  currentFrame: number;
  /** Total frames in the video */
  totalFrames: number;
  /** Duration in seconds */
  duration: number;
  /** Frames per second */
  fps: number;
}

/**
 * Playback control bar with play/pause, frame stepping, and speed control.
 */
export function PlaybackControls({
  currentFrame,
  totalFrames,
  duration,
  fps,
}: PlaybackControlsProps) {
  const {
    isPlaying,
    playbackSpeed,
    setCurrentFrame,
    togglePlayback,
    setPlaybackSpeed,
  } = usePlaybackControls();

  // Format time as mm:ss
  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const currentTime = currentFrame / fps;
  const speedOptions = [0.25, 0.5, 1, 1.5, 2];

  return (
    <div className="flex items-center gap-4 p-2 bg-muted rounded-lg">
      {/* Frame navigation */}
      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          onClick={() => setCurrentFrame(0)}
          title="Go to start"
        >
          <SkipBack className="h-4 w-4" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          onClick={() => setCurrentFrame(Math.max(0, currentFrame - 1))}
          title="Previous frame (←)"
        >
          <ChevronLeft className="h-4 w-4" />
        </Button>
      </div>

      {/* Play/Pause */}
      <Button
        variant="default"
        size="icon"
        onClick={togglePlayback}
        title={isPlaying ? 'Pause (Space)' : 'Play (Space)'}
      >
        {isPlaying ? (
          <Pause className="h-4 w-4" />
        ) : (
          <Play className="h-4 w-4" />
        )}
      </Button>

      {/* Forward navigation */}
      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          onClick={() => setCurrentFrame(currentFrame + 1)}
          title="Next frame (→)"
        >
          <ChevronRight className="h-4 w-4" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          onClick={() => setCurrentFrame(totalFrames - 1)}
          title="Go to end"
        >
          <SkipForward className="h-4 w-4" />
        </Button>
      </div>

      {/* Separator */}
      <div className="h-6 w-px bg-border" />

      {/* Time display */}
      <div className="text-sm font-mono min-w-[100px]">
        {formatTime(currentTime)} / {formatTime(duration)}
      </div>

      {/* Spacer */}
      <div className="flex-1" />

      {/* Speed control */}
      <div className="flex items-center gap-2">
        <span className="text-sm text-muted-foreground">Speed:</span>
        <div className="flex gap-1">
          {speedOptions.map((speed) => (
            <Button
              key={speed}
              variant={playbackSpeed === speed ? 'default' : 'ghost'}
              size="sm"
              onClick={() => setPlaybackSpeed(speed)}
              className="px-2 h-7 text-xs"
            >
              {speed}x
            </Button>
          ))}
        </div>
      </div>
    </div>
  );
}
