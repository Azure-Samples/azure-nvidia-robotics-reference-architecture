"""Thread-safe telemetry data store for real-time dashboard streaming.

Captures control-loop data (joints, actions, camera frames, safety)
in a ring buffer and exposes it for the dashboard server via SSE.
"""

from __future__ import annotations

import base64
import threading
import time
from collections import deque
from dataclasses import asdict, dataclass, field
from typing import Any

import cv2
import numpy as np

# Joint labels matching UR10e convention
JOINT_NAMES = ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"]


@dataclass
class StepRecord:
    """Single control-loop snapshot."""

    step: int = 0
    timestamp: float = 0.0

    # Joint state
    current_q: list[float] = field(default_factory=lambda: [0.0] * 6)
    target_q: list[float] = field(default_factory=lambda: [0.0] * 6)

    # Policy output (raw delta or absolute)
    raw_action: list[float] = field(default_factory=lambda: [0.0] * 6)

    # Safety
    was_clamped: bool = False
    pre_clamp_target: list[float] = field(default_factory=lambda: [0.0] * 6)

    # Timing
    loop_dt_ms: float = 0.0
    inference_dt_ms: float = 0.0

    # Buffer depth
    buffer_depth: int = 0

    def to_dict(self) -> dict:
        return asdict(self)


class TelemetryStore:
    """Thread-safe ring buffer of control-loop telemetry.

    The control loop writes snapshots; the dashboard reads them.
    """

    def __init__(self, max_history: int = 6000) -> None:
        self._lock = threading.Lock()
        self._history: deque[StepRecord] = deque(maxlen=max_history)
        self._latest: StepRecord | None = None
        self._latest_image: np.ndarray | None = None
        self._latest_image_jpeg: bytes | None = None
        self._episode_active = False
        self._episode_start_time: float = 0.0
        self._cumulative_delta: np.ndarray = np.zeros(6)
        self._total_safety_violations: int = 0
        self._control_enabled: bool = False
        self._policy_loaded: bool = False
        self._robot_connected: bool = False
        self._camera_connected: bool = False
        self._initial_q: np.ndarray | None = None

        # Camera image tracking
        self._has_image: bool = False
        self._image_timestamp: float = 0.0

        # Normalization diagnostics
        self._norm_input_state: list[float] | None = None
        self._norm_output_action: list[float] | None = None

    # ------------------------------------------------------------------
    # Writer API (called from control loop thread)
    # ------------------------------------------------------------------

    def record_step(self, record: StepRecord) -> None:
        """Append a step record to the ring buffer."""
        with self._lock:
            self._history.append(record)
            self._latest = record
            # Track cumulative drift from initial position
            if self._initial_q is not None:
                current = np.array(record.current_q)
                self._cumulative_delta = current - self._initial_q
            if record.was_clamped:
                self._total_safety_violations += 1

    def record_image(self, image: np.ndarray) -> None:
        """Store the latest camera frame (what the policy sees)."""
        with self._lock:
            self._latest_image = image
            # Encode to JPEG for efficient streaming
            _, buf = cv2.imencode(".jpg", cv2.cvtColor(image, cv2.COLOR_RGB2BGR),
                                  [cv2.IMWRITE_JPEG_QUALITY, 70])
            self._latest_image_jpeg = buf.tobytes()
            self._has_image = True
            self._image_timestamp = time.monotonic()

    def set_episode_active(self, active: bool) -> None:
        with self._lock:
            self._episode_active = active
            if active:
                self._episode_start_time = time.monotonic()
                self._cumulative_delta = np.zeros(6)
                self._total_safety_violations = 0

    def set_initial_q(self, q: np.ndarray) -> None:
        with self._lock:
            self._initial_q = q.copy()

    def set_status(
        self,
        *,
        control_enabled: bool | None = None,
        policy_loaded: bool | None = None,
        robot_connected: bool | None = None,
        camera_connected: bool | None = None,
    ) -> None:
        with self._lock:
            if control_enabled is not None:
                self._control_enabled = control_enabled
            if policy_loaded is not None:
                self._policy_loaded = policy_loaded
            if robot_connected is not None:
                self._robot_connected = robot_connected
            if camera_connected is not None:
                self._camera_connected = camera_connected

    def record_norm_diagnostics(
        self,
        input_state: list[float] | None = None,
        output_action: list[float] | None = None,
    ) -> None:
        """Store normalized input/output values for diagnostics."""
        with self._lock:
            if input_state is not None:
                self._norm_input_state = input_state
            if output_action is not None:
                self._norm_output_action = output_action

    # ------------------------------------------------------------------
    # Reader API (called from dashboard server thread)
    # ------------------------------------------------------------------

    def get_latest(self) -> dict[str, Any]:
        """Return the most recent step record plus status info."""
        with self._lock:
            result: dict[str, Any] = {}
            if self._latest is not None:
                result["step"] = self._latest.to_dict()
            else:
                result["step"] = None

            result["status"] = {
                "episode_active": self._episode_active,
                "control_enabled": self._control_enabled,
                "policy_loaded": self._policy_loaded,
                "robot_connected": self._robot_connected,
                "camera_connected": self._camera_connected,
                "has_image": self._has_image,
                "total_safety_violations": self._total_safety_violations,
                "cumulative_delta": self._cumulative_delta.tolist(),
            }

            if self._initial_q is not None:
                result["initial_q"] = self._initial_q.tolist()

            if self._norm_input_state is not None:
                result["norm_input_state"] = self._norm_input_state
            if self._norm_output_action is not None:
                result["norm_output_action"] = self._norm_output_action

            return result

    def get_history(self, last_n: int = 300) -> list[dict]:
        """Return the most recent *last_n* step records."""
        with self._lock:
            items = list(self._history)[-last_n:]
            return [r.to_dict() for r in items]

    def get_image_jpeg(self) -> bytes | None:
        """Return the latest camera JPEG bytes."""
        with self._lock:
            return self._latest_image_jpeg

    def get_joint_trajectories(self, last_n: int = 300) -> dict:
        """Return per-joint arrays suitable for plotting."""
        with self._lock:
            items = list(self._history)[-last_n:]

        if not items:
            return {"timestamps": [], "joints": {n: [] for n in JOINT_NAMES}}

        timestamps = [r.timestamp for r in items]
        current = {n: [] for n in JOINT_NAMES}
        target = {n: [] for n in JOINT_NAMES}
        raw_delta = {n: [] for n in JOINT_NAMES}

        for r in items:
            for i, name in enumerate(JOINT_NAMES):
                current[name].append(r.current_q[i])
                target[name].append(r.target_q[i])
                raw_delta[name].append(r.raw_action[i])

        return {
            "timestamps": timestamps,
            "current": current,
            "target": target,
            "raw_delta": raw_delta,
        }
