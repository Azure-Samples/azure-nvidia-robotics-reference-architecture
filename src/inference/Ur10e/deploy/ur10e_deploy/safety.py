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
    4. **Drift watchdog** — freeze if any joint drifts too far from start.
    """

    def __init__(self, config: RobotConfig) -> None:
        self.cfg = config
        self._violations: int = 0
        self._initial_q: np.ndarray | None = None
        self._drift_triggered: bool = False
        self._drift_watchdog_enabled: bool = True

    def set_initial_q(self, q: np.ndarray) -> None:
        """Record the starting joint positions for drift monitoring."""
        self._initial_q = q.copy()

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
        # 4. Drift watchdog — if already triggered, freeze in place
        if self._drift_triggered:
            return current.copy()

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

        # 4. Drift watchdog — check cumulative displacement from start
        if self._drift_watchdog_enabled and self._initial_q is not None:
            drift = np.abs(safe - self._initial_q)
            max_drift = getattr(self.cfg, "max_drift_rad", 0.5)
            if np.any(drift > max_drift):
                worst_joint = int(np.argmax(drift))
                joint_names = ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"]
                logger.error(
                    "DRIFT WATCHDOG: %s drifted %.3f rad (limit %.3f) — freezing robot",
                    joint_names[worst_joint],
                    drift[worst_joint],
                    max_drift,
                )
                self._drift_triggered = True
                self._violations += 1
                return current.copy()

        return safe

    @property
    def violation_count(self) -> int:
        """Total number of safety violations clamped so far."""
        return self._violations

    def reset(self) -> None:
        """Reset violation counter and drift watchdog (call at episode start)."""
        self._violations = 0
        self._initial_q = None
        self._drift_triggered = False

    def set_drift_watchdog_enabled(self, enabled: bool) -> None:
        """Enable or disable the drift watchdog.

        Disable for trajectory replay where total joint displacement may
        exceed the drift limit but the trajectory itself is known-good.
        Delta clamping, position limits, and velocity limits remain active.
        """
        self._drift_watchdog_enabled = enabled
        if not enabled:
            logger.info("Drift watchdog DISABLED")

    @property
    def drift_triggered(self) -> bool:
        """Whether the drift watchdog has frozen the robot."""
        return self._drift_triggered
