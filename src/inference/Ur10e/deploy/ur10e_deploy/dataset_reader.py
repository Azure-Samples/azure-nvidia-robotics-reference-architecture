"""LeRobot v3.0 dataset reader for episode replay.

Reads parquet data and metadata from a LeRobot dataset directory,
providing episode listing and frame-by-frame joint position access.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from pathlib import Path

import numpy as np

logger = logging.getLogger(__name__)

try:
    import pyarrow.parquet as pq

    PYARROW_AVAILABLE = True
except ImportError:
    PYARROW_AVAILABLE = False
    logger.warning("pyarrow not installed — dataset reading disabled. pip install pyarrow")


@dataclass
class EpisodeInfo:
    """Metadata for a single episode."""

    index: int
    length: int  # number of frames
    task: str


@dataclass
class DatasetInfo:
    """Top-level dataset metadata."""

    robot_type: str
    total_episodes: int
    total_frames: int
    fps: int
    features: dict
    data_path_template: str


class LeRobotDatasetReader:
    """Read episodes from a LeRobot v3.0 dataset on disk.

    Parameters
    ----------
    dataset_dir : str | Path
        Root directory of the LeRobot dataset (contains ``data/``,
        ``meta/``, and optionally ``videos/``).
    """

    def __init__(self, dataset_dir: str | Path) -> None:
        if not PYARROW_AVAILABLE:
            raise RuntimeError("pyarrow is required. Install with: pip install pyarrow")

        self.root = Path(dataset_dir).resolve()
        if not self.root.exists():
            raise FileNotFoundError(f"Dataset directory not found: {self.root}")

        self._info: DatasetInfo | None = None
        self._episodes: list[EpisodeInfo] = []
        self._load_metadata()

    # ------------------------------------------------------------------
    # Metadata loading
    # ------------------------------------------------------------------

    def _load_metadata(self) -> None:
        """Parse info.json and episode metadata."""
        meta_dir = self.root / "meta"
        info_path = meta_dir / "info.json"
        if not info_path.exists():
            raise FileNotFoundError(f"info.json not found at {info_path}")

        with open(info_path) as f:
            raw = json.load(f)

        self._info = DatasetInfo(
            robot_type=raw.get("robot_type", "unknown"),
            total_episodes=raw.get("total_episodes", 0),
            total_frames=raw.get("total_frames", 0),
            fps=raw.get("fps", 30),
            features=raw.get("features", {}),
            data_path_template=raw.get(
                "data_path", "data/chunk-{chunk_index:03d}/file-{file_index:03d}.parquet"
            ),
        )

        # Load task descriptions
        tasks_map: dict[int, str] = {}
        tasks_parquet = meta_dir / "tasks.parquet"
        tasks_json = meta_dir / "tasks.json"
        tasks_jsonl = meta_dir / "tasks.jsonl"

        if tasks_parquet.exists():
            table = pq.read_table(tasks_parquet)
            df = table.to_pandas()
            for _, row in df.iterrows():
                tasks_map[int(row.get("task_index", 0))] = str(
                    row.get("task", "unknown task")
                )
        elif tasks_json.exists():
            with open(tasks_json) as f:
                raw_tasks = json.load(f)
            if isinstance(raw_tasks, list):
                for i, t in enumerate(raw_tasks):
                    if isinstance(t, dict):
                        tasks_map[t.get("task_index", i)] = t.get("task", "unknown task")
                    else:
                        tasks_map[i] = str(t)
            elif isinstance(raw_tasks, dict):
                for k, v in raw_tasks.items():
                    tasks_map[int(k)] = str(v)
        elif tasks_jsonl.exists():
            with open(tasks_jsonl) as f:
                for line in f:
                    line = line.strip()
                    if line:
                        obj = json.loads(line)
                        tasks_map[obj.get("task_index", 0)] = obj.get("task", "unknown task")

        # Load episode metadata (parquet or jsonl)
        episodes_dir = meta_dir / "episodes"
        if episodes_dir.exists():
            self._load_episodes_from_dir(episodes_dir, tasks_map)
        else:
            # Fall back: scan data files to discover episodes
            self._load_episodes_from_data(tasks_map)

        logger.info(
            "Dataset loaded: %d episodes, %d total frames, %d fps",
            len(self._episodes),
            self._info.total_frames,
            self._info.fps,
        )

    def _load_episodes_from_dir(
        self, episodes_dir: Path, tasks_map: dict[int, str]
    ) -> None:
        """Load episode info from meta/episodes/ parquet files."""
        ep_files = sorted(episodes_dir.rglob("*.parquet"))
        for ep_file in ep_files:
            table = pq.read_table(ep_file)
            df = table.to_pandas()
            for _, row in df.iterrows():
                ep_idx = int(row.get("episode_index", 0))
                length = int(row.get("length", 0))
                task_idx = int(row.get("task_index", 0))
                self._episodes.append(
                    EpisodeInfo(
                        index=ep_idx,
                        length=length,
                        task=tasks_map.get(task_idx, "unknown task"),
                    )
                )
        self._episodes.sort(key=lambda e: e.index)

    def _load_episodes_from_data(self, tasks_map: dict[int, str]) -> None:
        """Fall back: scan data parquet files to discover episodes."""
        data_dir = self.root / "data"
        if not data_dir.exists():
            logger.warning("No data/ directory found in dataset")
            return

        parquet_files = sorted(data_dir.rglob("*.parquet"))
        episode_frames: dict[int, int] = {}
        episode_tasks: dict[int, int] = {}

        for pf in parquet_files:
            table = pq.read_table(pf, columns=["episode_index", "task_index"])
            df = table.to_pandas()
            for ep_idx in df["episode_index"].unique():
                ep_idx = int(ep_idx)
                count = int((df["episode_index"] == ep_idx).sum())
                episode_frames[ep_idx] = episode_frames.get(ep_idx, 0) + count
                if "task_index" in df.columns:
                    task_vals = df.loc[df["episode_index"] == ep_idx, "task_index"]
                    episode_tasks[ep_idx] = int(task_vals.iloc[0])

        for ep_idx in sorted(episode_frames.keys()):
            task_idx = episode_tasks.get(ep_idx, 0)
            self._episodes.append(
                EpisodeInfo(
                    index=ep_idx,
                    length=episode_frames[ep_idx],
                    task=tasks_map.get(task_idx, "unknown task"),
                )
            )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    @property
    def info(self) -> DatasetInfo:
        """Return dataset-level metadata."""
        if self._info is None:
            raise RuntimeError("Dataset not loaded")
        return self._info

    @property
    def episodes(self) -> list[EpisodeInfo]:
        """Return list of available episodes."""
        return list(self._episodes)

    def get_episode_frames(self, episode_index: int) -> np.ndarray:
        """Load all joint positions for a given episode.

        Parameters
        ----------
        episode_index : int
            The episode to load.

        Returns
        -------
        np.ndarray
            Joint positions array, shape ``(num_frames, 6)``, in the
            dataset's training convention.

        Raises
        ------
        ValueError
            If the episode index is not found.
        """
        if not any(e.index == episode_index for e in self._episodes):
            available = [e.index for e in self._episodes]
            raise ValueError(
                f"Episode {episode_index} not found. Available: {available}"
            )

        # Collect frames from data parquet files
        data_dir = self.root / "data"
        parquet_files = sorted(data_dir.rglob("*.parquet"))

        all_frames: list[tuple[int, np.ndarray]] = []

        for pf in parquet_files:
            table = pq.read_table(pf)
            df = table.to_pandas()
            ep_mask = df["episode_index"] == episode_index
            if not ep_mask.any():
                continue

            ep_df = df[ep_mask].sort_values("frame_index")

            for _, row in ep_df.iterrows():
                frame_idx = int(row["frame_index"])
                state = np.array(row["observation.state"], dtype=np.float32)
                all_frames.append((frame_idx, state))

        if not all_frames:
            raise ValueError(f"No data found for episode {episode_index}")

        # Sort by frame index and stack
        all_frames.sort(key=lambda x: x[0])
        positions = np.stack([f[1] for f in all_frames], axis=0)

        logger.info(
            "Loaded episode %d: %d frames, shape %s",
            episode_index,
            len(positions),
            positions.shape,
        )
        return positions

    def get_episode_timestamps(self, episode_index: int) -> np.ndarray:
        """Load timestamps for a given episode.

        Parameters
        ----------
        episode_index : int
            The episode to load.

        Returns
        -------
        np.ndarray
            Timestamps array, shape ``(num_frames,)``, in seconds.
        """
        data_dir = self.root / "data"
        parquet_files = sorted(data_dir.rglob("*.parquet"))

        all_ts: list[tuple[int, float]] = []

        for pf in parquet_files:
            table = pq.read_table(pf)
            df = table.to_pandas()
            ep_mask = df["episode_index"] == episode_index
            if not ep_mask.any():
                continue

            ep_df = df[ep_mask].sort_values("frame_index")
            for _, row in ep_df.iterrows():
                all_ts.append((int(row["frame_index"]), float(row["timestamp"])))

        if not all_ts:
            raise ValueError(f"No timestamps found for episode {episode_index}")

        all_ts.sort(key=lambda x: x[0])
        return np.array([t[1] for t in all_ts], dtype=np.float64)
