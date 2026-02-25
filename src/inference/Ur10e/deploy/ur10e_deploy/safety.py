"""Software safety layer — clamps actions before they reach the robot.

This is the first line of defense. The UR controller has its own
hardware safety limits, but catching violations early avoids
protective stops and keeps the control loop running smoothly.
"""

from __future__ import annotations

import logging

import numpy as np

from .config import RobotConfig

logger = logging.getLogger(__name__)


class SafetyGuard:
    """Clamp and validate joint commands before sending to the robot.

    Safety checks (in order):
    1. **Delta clamp** — limit per-step joint displacement.
    2. **Position clamp** — keep target within joint limits.
    3. **Velocity check** — verify implied velocity is within bounds.
    """

    def __init__(self, config: RobotConfig) -> None:
        self.cfg = config
        self._violations: int = 0

    def clamp_action(
        self,
        target: np.ndarray,
        current: np.ndarray,
        dt: float,
    ) -> np.ndarray:
        """Apply all safety transforms and return the safe target.

        Parameters
        ----------
        target : np.ndarray
            Desired joint positions (6,) in radians.
        current : np.ndarray
            Current joint positions (6,) in radians.
        dt : float
            Time step (seconds).

        Returns
        -------
        np.ndarray
            Clamped target joint positions (6,).
        """
        safe = target.copy()

        # 1. Delta clamp
        delta = safe - current
        max_delta = self.cfg.max_delta_rad
        clamped_delta = np.clip(delta, -max_delta, max_delta)
        if not np.allclose(delta, clamped_delta):
            self._violations += 1
            logger.warning(
                "Delta clamped: max |delta|=%.4f rad (limit %.4f)",
                np.max(np.abs(delta)),
                max_delta,
            )
        safe = current + clamped_delta

        # 2. Position clamp
        lower = np.array(self.cfg.joint_lower)
        upper = np.array(self.cfg.joint_upper)
        clamped_pos = np.clip(safe, lower, upper)
        if not np.allclose(safe, clamped_pos):
            self._violations += 1
            logger.warning("Position clamped to joint limits")
        safe = clamped_pos

        # 3. Velocity check
        if dt > 0:
            implied_vel = np.abs(safe - current) / dt
            max_vel = self.cfg.max_joint_vel
            if np.any(implied_vel > max_vel):
                scale = min(1.0, max_vel / np.max(implied_vel))
                safe = current + (safe - current) * scale
                self._violations += 1
                logger.warning(
                    "Velocity scaled by %.2f (max %.2f rad/s)",
                    scale,
                    np.max(implied_vel),
                )

        return safe

    @property
    def violation_count(self) -> int:
        """Total number of safety violations clamped so far."""
        return self._violations

    def reset(self) -> None:
        """Reset violation counter (call at episode start)."""
        self._violations = 0
