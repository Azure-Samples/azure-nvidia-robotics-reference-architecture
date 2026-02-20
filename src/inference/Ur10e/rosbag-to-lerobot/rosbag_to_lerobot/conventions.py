"""Joint coordinate conventions and image preprocessing."""

from __future__ import annotations

import cv2
import numpy as np


def apply_joint_sign(positions: np.ndarray, sign_mask: list[float]) -> np.ndarray:
    """Apply sign convention mask to joint positions.

    The UR10e RTDE reports shoulder and elbow with opposite sign
    compared to the training dataset convention. This function
    negates the specified joints.

    Args:
        positions: Joint positions array, shape (6,) or (N, 6).
        sign_mask: Per-joint sign multipliers, e.g. [1, -1, -1, 1, 1, 1].

    Returns:
        Converted positions with same shape as input.
    """
    return positions * np.asarray(sign_mask, dtype=np.float32)


def wrap_to_pi(angles: np.ndarray) -> np.ndarray:
    """Wrap angles to the range (-pi, pi].

    Uses np.arctan2(np.sin(a), np.cos(a)).

    Args:
        angles: Angle array in radians, any shape.

    Returns:
        Wrapped angles in (-pi, pi] with same shape.
    """
    return np.arctan2(np.sin(angles), np.cos(angles))


def convert_joint_positions(
    positions: np.ndarray,
    sign_mask: list[float] | None = None,
    wrap: bool = True,
) -> np.ndarray:
    """Full convention conversion pipeline.

    Applies sign flip (if sign_mask provided) then angle wrapping (if wrap=True).

    Args:
        positions: Joint positions, shape (6,) or (N, 6).
        sign_mask: Optional per-joint sign mask. None skips sign conversion.
        wrap: Whether to wrap angles to (-pi, pi].

    Returns:
        Converted positions as float32.
    """
    result = np.asarray(positions, dtype=np.float32)
    if sign_mask is not None:
        result = apply_joint_sign(result, sign_mask)
    if wrap:
        result = wrap_to_pi(result)
    return result


def resize_image(image: np.ndarray, target_hw: tuple[int, int]) -> np.ndarray:
    """Resize image to target height x width using OpenCV.

    Args:
        image: Input image, shape (H, W, 3) uint8 BGR or RGB.
        target_hw: Target (height, width).

    Returns:
        Resized image, shape (target_h, target_w, 3) uint8.
    """
    h, w = target_hw
    return cv2.resize(image, (w, h), interpolation=cv2.INTER_LINEAR)
