"""Conversion pipeline configuration with YAML loader."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path

import yaml

logger = logging.getLogger(__name__)


@dataclass
class BlobStorageConfig:
    account_url: str = ""
    container: str = "rosbag-recordings"
    rosbag_prefix: str = "recordings/ur10e/"
    lerobot_prefix: str = "lerobot/"


@dataclass
class DatasetConfig:
    repo_id: str = "hve-robo/ur10e-rosbag-converted"
    robot_type: str = "ur10e"
    fps: int = 30
    task_description: str = "UR10e manipulation task"
    vcodec: str = "libsvtav1"


@dataclass
class TopicsConfig:
    joint_states: str = "/joint_states"
    camera: str = "/camera/color/image_raw"


@dataclass
class ConventionsConfig:
    apply_joint_sign: bool = True
    joint_sign: list[float] = field(default_factory=lambda: [1.0, -1.0, -1.0, 1.0, 1.0, 1.0])
    wrap_angles: bool = True
    image_resize: list[int] = field(default_factory=lambda: [480, 848])


@dataclass
class RosConfig:
    distro: str = "ROS2_HUMBLE"


@dataclass
class ProcessingConfig:
    temp_dir: str | None = None
    cleanup_temp: bool = True
    episode_gap_threshold_s: float = 2.0
    split_episodes: bool = False


@dataclass
class ConvertConfig:
    blob_storage: BlobStorageConfig = field(default_factory=BlobStorageConfig)
    dataset: DatasetConfig = field(default_factory=DatasetConfig)
    topics: TopicsConfig = field(default_factory=TopicsConfig)
    conventions: ConventionsConfig = field(default_factory=ConventionsConfig)
    ros: RosConfig = field(default_factory=RosConfig)
    processing: ProcessingConfig = field(default_factory=ProcessingConfig)


_SECTION_MAP: dict[str, str] = {
    "blob_storage": "blob_storage",
    "dataset": "dataset",
    "topics": "topics",
    "conventions": "conventions",
    "ros": "ros",
    "processing": "processing",
}


def load_config(path: str | Path | None = None) -> ConvertConfig:
    """Load conversion config from a YAML file, falling back to defaults."""
    if path is None:
        return ConvertConfig()

    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")

    with open(path) as f:
        raw = yaml.safe_load(f)

    if raw is None:
        return ConvertConfig()

    cfg = ConvertConfig()

    for section_key, attr_name in _SECTION_MAP.items():
        if section_key in raw:
            sub = getattr(cfg, attr_name)
            for k, v in raw[section_key].items():
                if hasattr(sub, k):
                    setattr(sub, k, v)
                else:
                    logger.warning("Unknown key '%s' in section '%s', ignoring", k, section_key)

    unknown_sections = set(raw.keys()) - set(_SECTION_MAP.keys())
    for s in sorted(unknown_sections):
        logger.warning("Unknown config section '%s', ignoring", s)

    return cfg
