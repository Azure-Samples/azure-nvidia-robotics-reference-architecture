"""Deployment configuration for UR10e ACT policy inference.

All safety limits, robot parameters, and inference settings live here.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

import yaml


# ---------------------------------------------------------------------------
# UR10e joint limits (radians) — from Universal Robots datasheet
# Joints: base, shoulder, elbow, wrist1, wrist2, wrist3
# ---------------------------------------------------------------------------
UR10E_JOINT_LOWER = [-2 * math.pi] * 6
UR10E_JOINT_UPPER = [2 * math.pi] * 6

# Conservative operating limits (narrower than physical limits)
UR10E_SAFE_JOINT_LOWER = [
    math.radians(-350),
    math.radians(-190),
    math.radians(-160),
    math.radians(-350),
    math.radians(-350),
    math.radians(-350),
]
UR10E_SAFE_JOINT_UPPER = [
    math.radians(350),
    math.radians(10),
    math.radians(160),
    math.radians(350),
    math.radians(350),
    math.radians(350),
]


@dataclass
class RobotConfig:
    """UR10e connection and safety parameters."""

    ip: str = "192.168.2.102"
    rtde_frequency: float = 500.0  # RTDE native frequency (Hz)

    # Safety limits
    max_delta_rad: float = 0.05  # Max per-step joint delta (radians) (~2.86 deg)
    max_joint_vel: float = 1.0  # Max joint velocity (rad/s)
    max_drift_rad: float = 0.5  # Max cumulative drift from start per joint (~28.6 deg)
    joint_lower: list[float] = field(default_factory=lambda: list(UR10E_SAFE_JOINT_LOWER))
    joint_upper: list[float] = field(default_factory=lambda: list(UR10E_SAFE_JOINT_UPPER))

    # servoJ parameters
    servo_lookahead: float = 0.1  # seconds — smoothing lookahead
    servo_gain: int = 300  # proportional gain (100-2000)


@dataclass
class CameraConfig:
    """Camera capture parameters."""

    backend: Literal["opencv", "realsense"] = "opencv"
    device_id: int = 0
    capture_width: int | None = None   # Native sensor resolution (None = same as width)
    capture_height: int | None = None  # Native sensor resolution (None = same as height)
    width: int = 848                   # Policy input resolution
    height: int = 480
    fps: int = 30


@dataclass
class PolicyConfig:
    """ACT policy inference parameters."""

    checkpoint_dir: str = "../hve-robo-act-train"
    device: str = "cuda"
    action_mode: Literal["delta", "absolute"] = "delta"
    chunk_size: int = 100
    n_action_steps: int = 100
    temporal_ensemble_coeff: float | None = 0.01  # None = disabled


@dataclass
class DeployConfig:
    """Top-level deployment configuration."""

    robot: RobotConfig = field(default_factory=RobotConfig)
    camera: CameraConfig = field(default_factory=CameraConfig)
    policy: PolicyConfig = field(default_factory=PolicyConfig)
    control_hz: float = 30.0
    enable_control: bool = False  # Start in dry-run mode by default
    log_dir: str = "./logs"
    max_episode_steps: int = 3000  # ~100 s at 30 Hz


def load_config(path: Path | str | None = None) -> DeployConfig:
    """Load configuration from YAML file, falling back to defaults."""
    if path is None:
        return DeployConfig()
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")
    with open(path) as f:
        raw = yaml.safe_load(f)
    cfg = DeployConfig()
    if "robot" in raw:
        for k, v in raw["robot"].items():
            setattr(cfg.robot, k, v)
    if "camera" in raw:
        for k, v in raw["camera"].items():
            setattr(cfg.camera, k, v)
    if "policy" in raw:
        for k, v in raw["policy"].items():
            setattr(cfg.policy, k, v)
    for k in ("control_hz", "enable_control", "log_dir", "max_episode_steps"):
        if k in raw:
            setattr(cfg, k, raw[k])
    return cfg
