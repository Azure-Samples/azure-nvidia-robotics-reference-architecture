"""Flask-based replay dashboard for visualizing LeRobot episodes.

Serves a web UI for browsing episodes, viewing joint trajectories,
and monitoring the robot's current position during replay.
"""

from __future__ import annotations

import json
import logging
import socket
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
from flask import Flask, Response, jsonify, request, send_from_directory

from .dataset_reader import LeRobotDatasetReader

logger = logging.getLogger(__name__)

STATIC_DIR = Path(__file__).parent / "static"

# Joint sign mask — training convention ↔ RTDE (self-inverse)
SIGN_MASK = np.array([1.0, -1.0, -1.0, 1.0, 1.0, 1.0], dtype=np.float32)
JOINT_NAMES = ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"]


@dataclass
class ReplayState:
    """Thread-safe state for tracking replay progress."""

    lock: threading.Lock = field(default_factory=threading.Lock)

    # Replay status
    is_playing: bool = False
    is_connected: bool = False
    enable_control: bool = False
    current_frame: int = 0
    total_frames: int = 0
    current_episode: int = -1
    speed_factor: float = 1.0

    # Robot state (updated during replay)
    robot_q: list[float] = field(default_factory=lambda: [0.0] * 6)
    target_q: list[float] = field(default_factory=lambda: [0.0] * 6)
    safety_violations: int = 0
    drift_triggered: bool = False
    loop_dt_ms: float = 0.0

    # Message log
    messages: list[str] = field(default_factory=list)

    def update(self, **kwargs: Any) -> None:
        with self.lock:
            for k, v in kwargs.items():
                if hasattr(self, k):
                    setattr(self, k, v)

    def add_message(self, msg: str) -> None:
        with self.lock:
            self.messages.append(msg)
            if len(self.messages) > 50:
                self.messages = self.messages[-50:]

    def get_status(self) -> dict[str, Any]:
        with self.lock:
            return {
                "is_playing": self.is_playing,
                "is_connected": self.is_connected,
                "enable_control": self.enable_control,
                "current_frame": self.current_frame,
                "total_frames": self.total_frames,
                "current_episode": self.current_episode,
                "speed_factor": self.speed_factor,
                "robot_q": list(self.robot_q),
                "target_q": list(self.target_q),
                "safety_violations": self.safety_violations,
                "drift_triggered": self.drift_triggered,
                "loop_dt_ms": self.loop_dt_ms,
                "messages": list(self.messages[-10:]),
            }


def create_replay_app(
    dataset: LeRobotDatasetReader,
    replay_state: ReplayState,
) -> Flask:
    """Create the Flask replay dashboard application."""
    app = Flask(__name__, static_folder=str(STATIC_DIR))
    app.config["dataset"] = dataset
    app.config["replay_state"] = replay_state

    # Cache for loaded episode trajectories (training convention)
    _trajectory_cache: dict[int, np.ndarray] = {}

    wlog = logging.getLogger("werkzeug")
    wlog.setLevel(logging.WARNING)

    # ------------------------------------------------------------------
    # Page routes
    # ------------------------------------------------------------------

    @app.route("/")
    def index():
        return send_from_directory(str(STATIC_DIR), "replay.html")

    @app.route("/static/<path:filename>")
    def static_files(filename):
        return send_from_directory(str(STATIC_DIR), filename)

    # ------------------------------------------------------------------
    # Dataset API
    # ------------------------------------------------------------------

    @app.route("/api/dataset")
    def api_dataset():
        """Return dataset metadata and episode list."""
        ds: LeRobotDatasetReader = app.config["dataset"]
        info = ds.info
        episodes = []
        for ep in ds.episodes:
            duration = ep.length / info.fps
            episodes.append({
                "index": ep.index,
                "length": ep.length,
                "duration": round(duration, 1),
                "task": ep.task,
            })
        return jsonify({
            "robot_type": info.robot_type,
            "fps": info.fps,
            "total_episodes": info.total_episodes,
            "total_frames": info.total_frames,
            "episodes": episodes,
        })

    @app.route("/api/episode/<int:ep_id>/trajectory")
    def api_episode_trajectory(ep_id: int):
        """Return the full joint trajectory for an episode.

        Returns positions in RTDE convention (what the robot sees)
        and also in training convention (what's stored in the dataset).
        """
        ds: LeRobotDatasetReader = app.config["dataset"]

        # Cache trajectories to avoid re-reading parquet every time
        if ep_id not in _trajectory_cache:
            try:
                frames = ds.get_episode_frames(ep_id)
                _trajectory_cache[ep_id] = frames
            except ValueError as e:
                return jsonify({"error": str(e)}), 404

        frames_train = _trajectory_cache[ep_id]
        frames_rtde = frames_train * SIGN_MASK
        num_frames = len(frames_train)
        fps = ds.info.fps

        # Build per-joint arrays
        timestamps = [round(i / fps, 4) for i in range(num_frames)]
        training = {name: frames_train[:, j].tolist() for j, name in enumerate(JOINT_NAMES)}
        rtde = {name: frames_rtde[:, j].tolist() for j, name in enumerate(JOINT_NAMES)}

        # Compute per-frame deltas (degrees) for the delta chart
        deltas_rad = np.diff(frames_rtde, axis=0, prepend=frames_rtde[:1])
        deltas = {name: np.degrees(deltas_rad[:, j]).tolist() for j, name in enumerate(JOINT_NAMES)}

        return jsonify({
            "episode_index": ep_id,
            "num_frames": num_frames,
            "fps": fps,
            "duration": round(num_frames / fps, 1),
            "timestamps": timestamps,
            "rtde": rtde,
            "training": training,
            "deltas_deg": deltas,
        })

    # ------------------------------------------------------------------
    # Replay status API
    # ------------------------------------------------------------------

    @app.route("/api/replay/status")
    def api_replay_status():
        """Return current replay state."""
        state: ReplayState = app.config["replay_state"]
        return jsonify(state.get_status())

    @app.route("/api/replay/stream")
    def api_replay_stream():
        """SSE stream pushing replay status at ~10 Hz."""
        state: ReplayState = app.config["replay_state"]

        def generate():
            while True:
                try:
                    data = state.get_status()
                    yield f"data: {json.dumps(data)}\n\n"
                except Exception as exc:
                    logger.error("SSE error: %s", exc)
                    yield f"data: {{}}\n\n"
                time.sleep(0.1)

        return Response(
            generate(),
            mimetype="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
            },
        )

    return app


# ---------------------------------------------------------------------------
# Background server launcher
# ---------------------------------------------------------------------------


def _check_port(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        try:
            s.bind((host if host != "0.0.0.0" else "", port))
            return True
        except OSError:
            return False


def start_replay_dashboard(
    dataset: LeRobotDatasetReader,
    replay_state: ReplayState,
    host: str = "0.0.0.0",
    port: int = 5001,
) -> threading.Thread:
    """Start the replay dashboard in a background daemon thread.

    Parameters
    ----------
    dataset : LeRobotDatasetReader
        Dataset to browse.
    replay_state : ReplayState
        Shared replay state for live position tracking.
    host : str
        Bind address.
    port : int
        HTTP port (default 5001 to avoid conflict with deploy dashboard).

    Returns
    -------
    threading.Thread
        The running server thread (daemon).
    """
    if not _check_port(host, port):
        raise OSError(f"Port {port} already in use")

    app = create_replay_app(dataset, replay_state)
    ready = threading.Event()

    def _run():
        logger.info("Replay dashboard starting on http://%s:%d", host, port)
        ready.set()
        app.run(host=host, port=port, threaded=True, use_reloader=False)

    thread = threading.Thread(target=_run, name="replay-dashboard", daemon=True)
    thread.start()
    ready.wait(timeout=5)
    return thread
