"""Temporal synchronization and episode boundary detection."""

from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np

from .rosbag_reader import ImageSample, JointSample

logger = logging.getLogger(__name__)


@dataclass
class SyncedFrame:
    """A single synchronized frame with aligned joint state and image."""

    timestamp_ns: int
    frame_index: int
    joint_position: np.ndarray  # Shape (6,) float64
    joint_velocity: np.ndarray | None
    image: np.ndarray  # Shape (H, W, 3) uint8
    joint_time_offset_ms: float
    image_time_offset_ms: float


@dataclass
class SyncedEpisode:
    """A synchronized episode ready for conversion."""

    frames: list[SyncedFrame]
    duration_s: float
    frame_count: int
    max_joint_offset_ms: float
    max_image_offset_ms: float


def _nearest_index(ts_array: np.ndarray, target: int) -> int:
    """Return the index of the nearest timestamp in a sorted array.

    Uses binary search for O(log n) lookup.

    Args:
        ts_array: Sorted 1-D array of timestamps (nanoseconds).
        target: Target timestamp to match against.

    Returns:
        Index of the closest element in ``ts_array``.
    """
    idx = int(np.searchsorted(ts_array, target))
    idx_right = min(idx, len(ts_array) - 1)
    idx_left = max(idx - 1, 0)

    if abs(ts_array[idx_right] - target) <= abs(ts_array[idx_left] - target):
        return idx_right
    return idx_left


def synchronize(
    joint_samples: list[JointSample],
    image_samples: list[ImageSample],
    fps: int = 30,
    max_offset_ms: float = 50.0,
) -> SyncedEpisode:
    """Synchronize joint states and images at a target FPS.

    Generates uniform timestamps at the requested frame rate and matches each
    to the nearest joint and image sample via binary search.  Frames whose
    nearest-neighbor offset exceeds ``max_offset_ms`` are dropped.

    Args:
        joint_samples: Sorted list of joint-state samples.
        image_samples: Sorted list of image samples.
        fps: Target output frame rate (Hz).
        max_offset_ms: Maximum allowable temporal offset (ms) before a frame
            is discarded.

    Returns:
        A ``SyncedEpisode`` containing the aligned frames.
    """
    joint_ts = np.array([s.timestamp_ns for s in joint_samples], dtype=np.int64)
    image_ts = np.array([s.timestamp_ns for s in image_samples], dtype=np.int64)

    t_start = max(int(joint_ts[0]), int(image_ts[0]))
    t_end = min(int(joint_ts[-1]), int(image_ts[-1]))

    interval_ns = int(1e9 / fps)
    target_timestamps = np.arange(t_start, t_end, interval_ns, dtype=np.int64)

    frames: list[SyncedFrame] = []
    total_targets = len(target_timestamps)
    dropped = 0
    max_j_off = 0.0
    max_i_off = 0.0

    for frame_idx, target in enumerate(target_timestamps):
        j_idx = _nearest_index(joint_ts, target)
        i_idx = _nearest_index(image_ts, target)

        j_offset_ms = abs(int(joint_ts[j_idx]) - int(target)) / 1e6
        i_offset_ms = abs(int(image_ts[i_idx]) - int(target)) / 1e6

        if j_offset_ms > max_offset_ms or i_offset_ms > max_offset_ms:
            logger.warning(
                "Dropping frame %d: joint offset %.1f ms, image offset %.1f ms",
                frame_idx,
                j_offset_ms,
                i_offset_ms,
            )
            dropped += 1
            continue

        max_j_off = max(max_j_off, j_offset_ms)
        max_i_off = max(max_i_off, i_offset_ms)

        js = joint_samples[j_idx]
        ims = image_samples[i_idx]

        frames.append(
            SyncedFrame(
                timestamp_ns=int(target),
                frame_index=len(frames),
                joint_position=np.array(js.position, dtype=np.float64),
                joint_velocity=(
                    np.array(js.velocity, dtype=np.float64) if js.velocity is not None else None
                ),
                image=ims.image,
                joint_time_offset_ms=j_offset_ms,
                image_time_offset_ms=i_offset_ms,
            )
        )

    logger.info(
        "Synced %d frames at %d Hz, max joint offset %.1f ms, max image offset %.1f ms",
        len(frames),
        fps,
        max_j_off,
        max_i_off,
    )

    if total_targets > 0 and dropped / total_targets > 0.05:
        logger.warning(
            "Dropped %d / %d frames (%.1f%%) — exceeds 5%% threshold",
            dropped,
            total_targets,
            100.0 * dropped / total_targets,
        )

    duration_s = (frames[-1].timestamp_ns - frames[0].timestamp_ns) / 1e9 if frames else 0.0

    return SyncedEpisode(
        frames=frames,
        duration_s=duration_s,
        frame_count=len(frames),
        max_joint_offset_ms=max_j_off,
        max_image_offset_ms=max_i_off,
    )


def detect_episodes(
    joint_samples: list[JointSample],
    gap_threshold_s: float = 2.0,
) -> list[tuple[int, int]]:
    """Detect episode boundaries within a sequence of joint samples.

    Consecutive samples whose timestamp gap exceeds ``gap_threshold_s`` are
    treated as belonging to different episodes.

    Args:
        joint_samples: Sorted list of joint-state samples.
        gap_threshold_s: Minimum gap (seconds) to trigger an episode split.

    Returns:
        List of ``(start_index, end_index)`` tuples (inclusive) identifying
        each episode within ``joint_samples``.
    """
    if not joint_samples:
        return []

    gap_threshold_ns = int(gap_threshold_s * 1e9)
    boundaries: list[tuple[int, int]] = []
    start = 0

    for i in range(1, len(joint_samples)):
        gap = joint_samples[i].timestamp_ns - joint_samples[i - 1].timestamp_ns
        if gap > gap_threshold_ns:
            boundaries.append((start, i - 1))
            start = i

    boundaries.append((start, len(joint_samples) - 1))
    return boundaries


def split_by_episodes(
    joint_samples: list[JointSample],
    image_samples: list[ImageSample],
    boundaries: list[tuple[int, int]],
) -> list[tuple[list[JointSample], list[ImageSample]]]:
    """Split joint and image samples according to episode boundaries.

    For each boundary range the corresponding joint samples are sliced
    directly, while image samples are filtered to those whose timestamp falls
    within the joint-sample time range of that episode.

    Args:
        joint_samples: Full sorted list of joint-state samples.
        image_samples: Full sorted list of image samples.
        boundaries: Episode boundaries as returned by ``detect_episodes``.

    Returns:
        List of ``(joint_slice, image_slice)`` tuples, one per valid episode.
        Episodes with fewer than 2 joint frames are discarded with a warning.
    """
    episodes: list[tuple[list[JointSample], list[ImageSample]]] = []

    for start_idx, end_idx in boundaries:
        ep_joints = joint_samples[start_idx : end_idx + 1]

        if len(ep_joints) < 2:
            logger.warning(
                "Discarding episode [%d:%d] — only %d frame(s)",
                start_idx,
                end_idx,
                len(ep_joints),
            )
            continue

        t_lo = ep_joints[0].timestamp_ns
        t_hi = ep_joints[-1].timestamp_ns

        ep_images = [s for s in image_samples if t_lo <= s.timestamp_ns <= t_hi]

        episodes.append((ep_joints, ep_images))

    return episodes
