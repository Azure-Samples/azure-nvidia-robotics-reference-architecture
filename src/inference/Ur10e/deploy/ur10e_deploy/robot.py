"""UR10e RTDE interface — read joint state, send servo commands.

Uses the ``ur_rtde`` library for real-time communication with the UR
controller over the Real-Time Data Exchange (RTDE) protocol.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass

import numpy as np

from .config import RobotConfig

logger = logging.getLogger(__name__)

try:
    import rtde_control  # ur_rtde
    import rtde_receive  # ur_rtde

    RTDE_AVAILABLE = True
except ImportError:
    RTDE_AVAILABLE = False
    logger.warning(
        "ur_rtde not installed — robot connection disabled. "
        "Install with: pip install ur-rtde"
    )


@dataclass
class JointState:
    """Snapshot of the robot joint state."""

    positions: np.ndarray  # (6,) radians
    velocities: np.ndarray  # (6,) rad/s
    timestamp: float  # time.monotonic()


class UR10eRTDE:
    """Thin wrapper around ur_rtde for UR10e joint-level control.

    Parameters
    ----------
    config : RobotConfig
        Connection and safety parameters.
    """

    def __init__(self, config: RobotConfig) -> None:
        self.cfg = config
        self._ctrl: rtde_control.RTDEControlInterface | None = None
        self._recv: rtde_receive.RTDEReceiveInterface | None = None
        self._connected = False

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def connect(self) -> None:
        """Establish RTDE connections to the robot controller."""
        if not RTDE_AVAILABLE:
            raise RuntimeError(
                "ur_rtde library is not installed. Run: pip install ur-rtde"
            )
        logger.info("Connecting to UR10e at %s ...", self.cfg.ip)
        self._recv = rtde_receive.RTDEReceiveInterface(self.cfg.ip)
        self._ctrl = rtde_control.RTDEControlInterface(self.cfg.ip)
        self._connected = True
        logger.info("Connected to UR10e at %s", self.cfg.ip)

    def disconnect(self) -> None:
        """Gracefully shut down RTDE connections."""
        if self._ctrl is not None:
            try:
                self._ctrl.servoStop()
            except Exception:
                pass
            try:
                self._ctrl.stopScript()
            except Exception:
                pass
            self._ctrl = None
        if self._recv is not None:
            self._recv = None
        self._connected = False
        logger.info("Disconnected from UR10e")

    @property
    def connected(self) -> bool:
        return self._connected

    # ------------------------------------------------------------------
    # Reading
    # ------------------------------------------------------------------

    def get_joint_state(self) -> JointState:
        """Return current joint positions and velocities."""
        if not self._connected or self._recv is None:
            raise RuntimeError("Not connected to robot")
        positions = np.array(self._recv.getActualQ(), dtype=np.float32)
        velocities = np.array(self._recv.getActualQd(), dtype=np.float32)
        return JointState(
            positions=positions,
            velocities=velocities,
            timestamp=time.monotonic(),
        )

    def get_joint_positions(self) -> np.ndarray:
        """Convenience: return (6,) array of joint positions in radians."""
        return self.get_joint_state().positions

    # ------------------------------------------------------------------
    # Commanding
    # ------------------------------------------------------------------

    def servo_joint(
        self,
        target_positions: np.ndarray,
        dt: float = 1.0 / 30.0,
    ) -> None:
        """Send a joint position command via servoJ.

        Parameters
        ----------
        target_positions : np.ndarray
            Target joint positions (6,) in radians.
        dt : float
            Time step for the servo command (seconds).
        """
        if not self._connected or self._ctrl is None:
            raise RuntimeError("Not connected to robot")
        self._ctrl.servoJ(
            target_positions.tolist(),
            0.0,  # velocity — not used in position mode
            0.0,  # acceleration — not used in position mode
            dt,
            self.cfg.servo_lookahead,
            self.cfg.servo_gain,
        )

    def move_to(self, target_positions: np.ndarray, speed: float = 0.5, acceleration: float = 0.3) -> None:
        """Move to a target joint position using moveJ (smooth, blocking).

        Parameters
        ----------
        target_positions : np.ndarray
            Target joint positions (6,) in radians.
        speed : float
            Joint speed in rad/s (default 0.5 — conservative).
        acceleration : float
            Joint acceleration in rad/s².
        """
        if not self._connected or self._ctrl is None:
            raise RuntimeError("Not connected to robot")
        logger.info(
            "moveJ to [%s] at %.2f rad/s ...",
            ", ".join(f"{v:+.3f}" for v in target_positions),
            speed,
        )
        self._ctrl.moveJ(target_positions.tolist(), speed, acceleration)
        logger.info("moveJ complete")

    def stop(self) -> None:
        """Immediately stop the robot motion."""
        if self._ctrl is not None:
            self._ctrl.servoStop()
            logger.info("Robot motion stopped")

    # ------------------------------------------------------------------
    # Safety queries
    # ------------------------------------------------------------------

    def is_protective_stopped(self) -> bool:
        """Check if the robot is in a protective stop."""
        if self._recv is None:
            return False
        return self._recv.isProtectiveStopped()

    def is_emergency_stopped(self) -> bool:
        """Check if the robot is in an emergency stop."""
        if self._recv is None:
            return False
        return self._recv.isEmergencyStopped()
