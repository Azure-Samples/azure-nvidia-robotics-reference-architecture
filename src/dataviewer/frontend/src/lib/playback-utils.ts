/**
 * Playback synchronization utilities.
 *
 * Pure functions for frame↔time conversion and playback seek logic,
 * extracted from AnnotationWorkspace for testability.
 */

/**
 * Derive effective fps from the video element's actual duration.
 *
 * When the video duration is available, uses `totalFrames / videoDuration`
 * to handle mismatches between dataset metadata fps and video encoding fps.
 * Falls back to the dataset metadata fps when duration is unavailable.
 */
export function computeEffectiveFps(
  totalFrames: number,
  videoDuration: number,
  datasetFps: number,
): number {
  return videoDuration > 0 && totalFrames > 0
    ? totalFrames / videoDuration
    : datasetFps;
}

/**
 * Determine the seek target and action when playback is toggled on.
 *
 * Returns the target time in seconds and whether the video should restart
 * from the beginning (when at the last frame).
 */
export function computePlaybackTarget(
  currentFrame: number,
  totalFrames: number,
  originalFrameIndex: number | null,
  fps: number,
): { targetTime: number; shouldRestart: boolean } {
  if (currentFrame >= totalFrames - 1) {
    return { targetTime: 0, shouldRestart: true };
  }

  const frameForTime = originalFrameIndex ?? currentFrame;
  return { targetTime: frameForTime / fps, shouldRestart: false };
}

/**
 * Determine if the video element needs a seek before playback.
 *
 * Returns true when the video's current position differs from the
 * target by more than half a frame duration.
 */
export function needsSeekBeforePlay(
  videoCurrentTime: number,
  targetTime: number,
  fps: number,
): boolean {
  return Math.abs(videoCurrentTime - targetTime) > 0.5 / fps;
}
