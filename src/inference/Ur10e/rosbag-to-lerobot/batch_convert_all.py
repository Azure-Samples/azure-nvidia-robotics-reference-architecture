"""Batch-convert all rosbags into a single LeRobot v3 dataset.

Stream pattern: download each bag, convert, upload to blob storage, then
delete local files before proceeding to the next bag.  Keeps disk usage
under ~500 MB at any time.

Output structure (uploaded to blob storage):
    data/chunk-NNN/file-NNN.parquet
    videos/observation.images.color/chunk-NNN/file-NNN.mp4
    meta/info.json
    meta/stats.json
    meta/tasks.parquet
    meta/episodes/chunk-000/file-000.parquet

Usage:
    python batch_convert_all.py                        # all bags
    python batch_convert_all.py --max-bags 5           # first 5
    python batch_convert_all.py --resume               # resume interrupted run
    python batch_convert_all.py --skip-upload          # local only (needs disk)
"""

from __future__ import annotations

import argparse
import json
import logging
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq

# -- local imports -----------------------------------------------------------
sys.path.insert(0, str(Path(__file__).resolve().parent))

from rosbag_to_lerobot.blob_storage import BlobStorageClient
from rosbag_to_lerobot.config import load_config
from rosbag_to_lerobot.conventions import convert_joint_positions, resize_image
from rosbag_to_lerobot.rosbag_reader import extract_from_bag
from rosbag_to_lerobot.sync import synchronize

# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger("batch_convert")

# Suppress noisy Azure HTTP logging.
for _azlog in (
    "azure.core.pipeline.policies.http_logging_policy",
    "azure.identity",
    "azure.core",
):
    logging.getLogger(_azlog).setLevel(logging.WARNING)

# -- constants matching template -------------------------------------------
JOINT_NAMES = ["joint_0", "joint_1", "joint_2", "joint_3", "joint_4", "joint_5"]
FPS = 30
VIDEO_CODEC = "h264"
VIDEO_PIX_FMT = "yuv420p"
IMAGE_SHAPE = (480, 848, 3)
TASK_DESCRIPTION = "UR10e manipulation demonstration"


# -- running stats accumulator ---------------------------------------------
@dataclass
class RunningStats:
    """Welford-style running mean/std/min/max for a 6-DoF vector."""

    n: int = 0
    mean: np.ndarray = field(default_factory=lambda: np.zeros(6, dtype=np.float64))
    m2: np.ndarray = field(default_factory=lambda: np.zeros(6, dtype=np.float64))
    vmin: np.ndarray = field(default_factory=lambda: np.full(6, np.inf, dtype=np.float64))
    vmax: np.ndarray = field(default_factory=lambda: np.full(6, -np.inf, dtype=np.float64))

    def update_batch(self, data: np.ndarray) -> None:
        """Update with an (N, 6) array of samples."""
        for row in data:
            self.n += 1
            delta = row - self.mean
            self.mean += delta / self.n
            delta2 = row - self.mean
            self.m2 += delta * delta2
            self.vmin = np.minimum(self.vmin, row)
            self.vmax = np.maximum(self.vmax, row)

    @property
    def std(self) -> np.ndarray:
        if self.n < 2:
            return np.zeros(6, dtype=np.float64)
        return np.sqrt(self.m2 / self.n)

    def to_dict(self) -> dict:
        return {
            "mean": self.mean.tolist(),
            "std": self.std.tolist(),
            "min": self.vmin.tolist(),
            "max": self.vmax.tolist(),
        }

    def state_dict(self) -> dict:
        """Serialise for checkpoint."""
        return {
            "n": self.n,
            "mean": self.mean.tolist(),
            "m2": self.m2.tolist(),
            "vmin": self.vmin.tolist(),
            "vmax": self.vmax.tolist(),
        }

    @classmethod
    def from_state_dict(cls, d: dict) -> RunningStats:
        return cls(
            n=d["n"],
            mean=np.array(d["mean"], dtype=np.float64),
            m2=np.array(d["m2"], dtype=np.float64),
            vmin=np.array(d["vmin"], dtype=np.float64),
            vmax=np.array(d["vmax"], dtype=np.float64),
        )


# -- lightweight episode summary (no raw data) -----------------------------
@dataclass
class EpisodeSummary:
    """Minimal episode info kept in memory / checkpoint."""

    episode_index: int
    bag_name: str
    frame_count: int
    duration_s: float


# -- helpers ----------------------------------------------------------------

def _compute_action_deltas(states: list[np.ndarray]) -> list[np.ndarray]:
    """action[t] = state[t+1] - state[t]; action[-1] = zeros."""
    deltas: list[np.ndarray] = []
    for i in range(len(states) - 1):
        deltas.append((states[i + 1] - states[i]).astype(np.float32))
    deltas.append(np.zeros(6, dtype=np.float32))
    return deltas


def _write_data_parquet(
    episode_index: int,
    global_start_index: int,
    states: list[np.ndarray],
    actions: list[np.ndarray],
    timestamps_s: list[float],
    out_dir: Path,
) -> Path:
    """Write data/chunk-NNN/file-NNN.parquet and return the file path."""
    chunk_dir = out_dir / "data" / f"chunk-{episode_index:03d}"
    chunk_dir.mkdir(parents=True, exist_ok=True)
    parquet_path = chunk_dir / f"file-{episode_index:03d}.parquet"

    n = len(states)
    table = pa.table(
        {
            "timestamp": pa.array(timestamps_s, type=pa.float64()),
            "frame_index": pa.array(list(range(n)), type=pa.int64()),
            "episode_index": pa.array([episode_index] * n, type=pa.int64()),
            "index": pa.array(
                list(range(global_start_index, global_start_index + n)), type=pa.int64()
            ),
            "task_index": pa.array([0] * n, type=pa.int64()),
            "observation.state": pa.array(
                [s.tolist() for s in states], type=pa.list_(pa.float64())
            ),
            "action": pa.array(
                [a.tolist() for a in actions], type=pa.list_(pa.float64())
            ),
        }
    )
    pq.write_table(table, parquet_path)
    return parquet_path


def _get_ffmpeg_path() -> str:
    """Resolve ffmpeg binary — prefer imageio-ffmpeg bundled binary."""
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return "ffmpeg"


def _encode_video(
    episode_index: int,
    images: list[np.ndarray],
    out_dir: Path,
) -> Path:
    """Encode images to h264 mp4 and return the file path."""
    video_dir = (
        out_dir / "videos" / "observation.images.color" / f"chunk-{episode_index:03d}"
    )
    video_dir.mkdir(parents=True, exist_ok=True)
    video_path = video_dir / f"file-{episode_index:03d}.mp4"

    ffmpeg = _get_ffmpeg_path()

    with tempfile.TemporaryDirectory(prefix="frames_") as tmp:
        tmp_path = Path(tmp)
        from PIL import Image as PILImage

        for i, img in enumerate(images):
            if (img.shape[0], img.shape[1]) != (IMAGE_SHAPE[0], IMAGE_SHAPE[1]):
                img = resize_image(img, (IMAGE_SHAPE[0], IMAGE_SHAPE[1]))
            PILImage.fromarray(img).save(tmp_path / f"frame_{i:06d}.png")

        cmd = [
            ffmpeg,
            "-y",
            "-framerate",
            str(FPS),
            "-i",
            str(tmp_path / "frame_%06d.png"),
            "-c:v",
            "libx264",
            "-pix_fmt",
            VIDEO_PIX_FMT,
            "-preset",
            "fast",
            "-crf",
            "23",
            str(video_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if result.returncode != 0:
            logger.error(
                "ffmpeg failed for episode %d: %s", episode_index, result.stderr[-500:]
            )
            raise RuntimeError(f"ffmpeg failed for episode {episode_index}")

    return video_path


def _upload_and_delete(
    client: BlobStorageClient,
    upload_prefix: str,
    local_file: Path,
    rel_path: str,
    root_dir: Path | None = None,
) -> None:
    """Upload a single file to blob storage and delete the local copy.

    Parameters
    ----------
    root_dir
        If provided, empty-parent cleanup stops at (and never removes)
        this directory so the output root is preserved for checkpoints.
    """
    blob_name = f"{upload_prefix}/{rel_path}"
    blob_client = client._container.get_blob_client(blob_name)
    with open(local_file, "rb") as data:
        blob_client.upload_blob(data, overwrite=True, max_concurrency=4)
    local_file.unlink()
    # Remove empty parent directories up to (but not including) root_dir.
    stop = root_dir.resolve() if root_dir else None
    for parent in local_file.parents:
        if stop and parent.resolve() == stop:
            break
        try:
            parent.rmdir()
        except OSError:
            break


def _write_and_upload_meta(
    episodes: list[EpisodeSummary],
    state_stats: RunningStats,
    action_stats: RunningStats,
    total_frames: int,
    client: BlobStorageClient | None,
    upload_prefix: str,
    out_dir: Path,
) -> None:
    """Write all meta files, optionally upload, then delete local copies."""
    meta_dir = out_dir / "meta"
    meta_dir.mkdir(parents=True, exist_ok=True)

    total_episodes = len(episodes)

    # -- info.json --
    info = {
        "codebase_version": "v3.0",
        "robot_type": "ur10e",
        "total_episodes": total_episodes,
        "total_frames": total_frames,
        "total_tasks": 1,
        "total_chunks": total_episodes,
        "chunks_size": 1000,
        "fps": FPS,
        "splits": {"train": f"0:{total_episodes}"},
        "data_path": "data/chunk-{chunk_index:03d}/file-{file_index:03d}.parquet",
        "video_path": (
            "videos/{video_key}/chunk-{chunk_index:03d}/file-{file_index:03d}.mp4"
        ),
        "features": {
            "timestamp": {"dtype": "float64", "shape": [1]},
            "frame_index": {"dtype": "int64", "shape": [1]},
            "episode_index": {"dtype": "int64", "shape": [1]},
            "index": {"dtype": "int64", "shape": [1]},
            "task_index": {"dtype": "int64", "shape": [1]},
            "observation.state": {
                "dtype": "float32",
                "shape": [6],
                "names": JOINT_NAMES,
            },
            "action": {
                "dtype": "float32",
                "shape": [6],
                "names": JOINT_NAMES,
            },
            "observation.images.color": {
                "dtype": "video",
                "shape": list(IMAGE_SHAPE),
                "names": ["height", "width", "channels"],
                "info": {
                    "video.fps": FPS,
                    "video.codec": VIDEO_CODEC,
                    "video.pix_fmt": VIDEO_PIX_FMT,
                },
            },
        },
    }
    info_path = meta_dir / "info.json"
    with open(info_path, "w") as f:
        json.dump(info, f, indent=2)
    logger.info("Wrote meta/info.json")

    # -- stats.json --
    stats = {
        "observation.state": state_stats.to_dict(),
        "action": action_stats.to_dict(),
    }
    stats_path = meta_dir / "stats.json"
    with open(stats_path, "w") as f:
        json.dump(stats, f, indent=2)
    logger.info("Wrote meta/stats.json")

    # -- tasks.parquet --
    tasks_path = meta_dir / "tasks.parquet"
    pq.write_table(
        pa.table(
            {
                "task_index": pa.array([0], type=pa.int64()),
                "task": pa.array([TASK_DESCRIPTION], type=pa.string()),
            }
        ),
        tasks_path,
    )
    logger.info("Wrote meta/tasks.parquet")

    # -- episodes parquet --
    ep_meta_dir = meta_dir / "episodes" / "chunk-000"
    ep_meta_dir.mkdir(parents=True, exist_ok=True)

    global_idx = 0
    cumulative_ts = 0.0
    ep_rows: list[dict] = []
    for ep in episodes:
        ep_rows.append(
            {
                "episode_index": ep.episode_index,
                "task_index": 0,
                "length": ep.frame_count,
                "dataset_from_index": global_idx,
                "dataset_to_index": global_idx + ep.frame_count,
                "data/chunk_index": ep.episode_index,
                "data/file_index": ep.episode_index,
                "videos/observation.images.color/chunk_index": ep.episode_index,
                "videos/observation.images.color/file_index": ep.episode_index,
                "videos/observation.images.color/from_timestamp": cumulative_ts,
                "videos/observation.images.color/to_timestamp": cumulative_ts
                + ep.duration_s,
            }
        )
        global_idx += ep.frame_count
        cumulative_ts += ep.duration_s

    ep_path = ep_meta_dir / "file-000.parquet"
    pq.write_table(
        pa.table(
            {
                "episode_index": pa.array(
                    [r["episode_index"] for r in ep_rows], type=pa.int64()
                ),
                "task_index": pa.array(
                    [r["task_index"] for r in ep_rows], type=pa.int64()
                ),
                "length": pa.array(
                    [r["length"] for r in ep_rows], type=pa.int64()
                ),
                "dataset_from_index": pa.array(
                    [r["dataset_from_index"] for r in ep_rows], type=pa.int64()
                ),
                "dataset_to_index": pa.array(
                    [r["dataset_to_index"] for r in ep_rows], type=pa.int64()
                ),
                "data/chunk_index": pa.array(
                    [r["data/chunk_index"] for r in ep_rows], type=pa.int64()
                ),
                "data/file_index": pa.array(
                    [r["data/file_index"] for r in ep_rows], type=pa.int64()
                ),
                "videos/observation.images.color/chunk_index": pa.array(
                    [r["videos/observation.images.color/chunk_index"] for r in ep_rows],
                    type=pa.int64(),
                ),
                "videos/observation.images.color/file_index": pa.array(
                    [r["videos/observation.images.color/file_index"] for r in ep_rows],
                    type=pa.int64(),
                ),
                "videos/observation.images.color/from_timestamp": pa.array(
                    [
                        r["videos/observation.images.color/from_timestamp"]
                        for r in ep_rows
                    ],
                    type=pa.float64(),
                ),
                "videos/observation.images.color/to_timestamp": pa.array(
                    [
                        r["videos/observation.images.color/to_timestamp"]
                        for r in ep_rows
                    ],
                    type=pa.float64(),
                ),
            }
        ),
        ep_path,
    )
    logger.info("Wrote meta/episodes with %d episodes", total_episodes)

    # Upload meta files.
    if client is not None:
        meta_files = [
            (info_path, "meta/info.json"),
            (stats_path, "meta/stats.json"),
            (tasks_path, "meta/tasks.parquet"),
            (ep_path, "meta/episodes/chunk-000/file-000.parquet"),
        ]
        for local, rel in meta_files:
            _upload_and_delete(client, upload_prefix, local, rel, root_dir=out_dir)
        logger.info("Uploaded meta files to blob storage")


# -- checkpoint persistence -------------------------------------------------


def _save_checkpoint(
    checkpoint_path: Path,
    episodes: list[EpisodeSummary],
    completed_bags: set[str],
    global_frame_index: int,
    state_stats: RunningStats,
    action_stats: RunningStats,
) -> None:
    """Persist lightweight checkpoint to disk."""
    data = {
        "completed_bags": sorted(completed_bags),
        "global_frame_index": global_frame_index,
        "episodes": [
            {
                "episode_index": e.episode_index,
                "bag_name": e.bag_name,
                "frame_count": e.frame_count,
                "duration_s": e.duration_s,
            }
            for e in episodes
        ],
        "state_stats": state_stats.state_dict(),
        "action_stats": action_stats.state_dict(),
    }
    checkpoint_path.parent.mkdir(parents=True, exist_ok=True)
    with open(checkpoint_path, "w") as f:
        json.dump(data, f)


def _load_checkpoint(
    checkpoint_path: Path,
) -> tuple[set[str], int, list[EpisodeSummary], RunningStats, RunningStats]:
    """Load checkpoint."""
    with open(checkpoint_path) as f:
        data = json.load(f)
    completed_bags = set(data["completed_bags"])
    global_frame_index = data["global_frame_index"]
    episodes = [
        EpisodeSummary(
            episode_index=e["episode_index"],
            bag_name=e["bag_name"],
            frame_count=e["frame_count"],
            duration_s=e["duration_s"],
        )
        for e in data["episodes"]
    ]
    state_stats = RunningStats.from_state_dict(data["state_stats"])
    action_stats = RunningStats.from_state_dict(data["action_stats"])
    return completed_bags, global_frame_index, episodes, state_stats, action_stats


# -- core pipeline ----------------------------------------------------------


def _convert_single_bag(
    bag_path: Path,
    episode_index: int,
    joint_topic: str,
    image_topic: str,
    ros_distro: str,
    sign_mask: list[float] | None,
    wrap_angles: bool,
    target_hw: tuple[int, int] | None,
) -> (
    tuple[list[np.ndarray], list[np.ndarray], list[float], list[np.ndarray]] | None
):
    """Extract and convert one bag.

    Returns (states, actions, timestamps_s, images) or None.
    """
    logger.info("  Extracting %s ...", bag_path.name)

    contents = extract_from_bag(bag_path, joint_topic, image_topic, ros_distro)
    if not contents.joint_samples or not contents.image_samples:
        logger.warning("  No joint/image data — skipping")
        return None

    synced = synchronize(contents.joint_samples, contents.image_samples, fps=FPS)
    if synced.frame_count == 0:
        logger.warning("  0 synced frames — skipping")
        return None

    t0 = synced.frames[0].timestamp_ns
    timestamps_s = [(f.timestamp_ns - t0) / 1e9 for f in synced.frames]

    states: list[np.ndarray] = []
    images: list[np.ndarray] = []
    for frame in synced.frames:
        state = convert_joint_positions(
            frame.joint_position, sign_mask=sign_mask, wrap=wrap_angles
        )
        states.append(state)
        img = frame.image
        if target_hw and (img.shape[0], img.shape[1]) != target_hw:
            img = resize_image(img, target_hw)
        images.append(img)

    actions = _compute_action_deltas(states)
    logger.info(
        "  %d frames, %.1f s",
        len(states),
        timestamps_s[-1] if timestamps_s else 0,
    )
    return states, actions, timestamps_s, images


def batch_convert(
    config_path: Path,
    output_dir: Path,
    max_bags: int | None = None,
    skip_upload: bool = False,
    resume: bool = False,
) -> None:
    """Stream-convert all rosbags: download -> convert -> upload -> delete."""
    cfg = load_config(config_path)
    checkpoint_path = output_dir / ".checkpoint.json"

    upload_prefix = cfg.blob_storage.lerobot_prefix.rstrip("/")

    # Blob client for both discovery and upload.
    client: BlobStorageClient | None = None
    if not skip_upload:
        client = BlobStorageClient(
            account_url=cfg.blob_storage.account_url,
            container_name=cfg.blob_storage.container,
        )

    # Resume or fresh start.
    if resume and checkpoint_path.exists():
        (
            completed_bags,
            global_frame_index,
            episodes,
            state_stats,
            action_stats,
        ) = _load_checkpoint(checkpoint_path)
        logger.info(
            "Resuming: %d episodes, %d frames, %d bags done",
            len(episodes),
            global_frame_index,
            len(completed_bags),
        )
    else:
        if output_dir.exists():
            shutil.rmtree(output_dir)
        output_dir.mkdir(parents=True)
        completed_bags: set[str] = set()
        global_frame_index: int = 0
        episodes: list[EpisodeSummary] = []
        state_stats = RunningStats()
        action_stats = RunningStats()

    # Discover bags.
    discover_client = client or BlobStorageClient(
        account_url=cfg.blob_storage.account_url,
        container_name=cfg.blob_storage.container,
    )
    bag_prefixes = discover_client.discover_bags(cfg.blob_storage.rosbag_prefix)
    bag_prefixes.sort()

    if max_bags is not None:
        bag_prefixes = bag_prefixes[:max_bags]

    total_bags = len(bag_prefixes)
    logger.info(
        "Found %d bag(s), %d already done", total_bags, len(completed_bags)
    )

    # Convention settings.
    sign_mask = (
        cfg.conventions.joint_sign if cfg.conventions.apply_joint_sign else None
    )
    wrap_angles = cfg.conventions.wrap_angles
    target_hw = (
        tuple(cfg.conventions.image_resize) if cfg.conventions.image_resize else None
    )

    skipped = 0

    for bag_idx, prefix in enumerate(bag_prefixes):
        bag_name = prefix.rstrip("/").rsplit("/", 1)[-1]
        if bag_name in completed_bags:
            continue

        episode_index = len(episodes)
        logger.info(
            "=== [%d/%d] ep %d: %s ===",
            bag_idx + 1,
            total_bags,
            episode_index,
            bag_name,
        )

        tmp_dir = Path(tempfile.mkdtemp(prefix=f"bag_{bag_name}_"))
        try:
            # 1. Download.
            discover_client.download_directory(prefix, tmp_dir)

            db3_files = list(tmp_dir.rglob("*.db3"))
            if not db3_files:
                logger.warning("  No .db3 — skipping")
                skipped += 1
                completed_bags.add(bag_name)
                continue

            bag_path = db3_files[0].parent

            # 2. Convert.
            result = _convert_single_bag(
                bag_path,
                episode_index,
                cfg.topics.joint_states,
                cfg.topics.camera,
                cfg.ros.distro,
                sign_mask,
                wrap_angles,
                target_hw,
            )

            if result is None:
                skipped += 1
                completed_bags.add(bag_name)
                continue

            states, actions, timestamps_s, images = result
            n_frames = len(states)

        finally:
            # Delete downloaded bag immediately to free space.
            shutil.rmtree(tmp_dir, ignore_errors=True)

        # 3. Write parquet.
        parquet_path = _write_data_parquet(
            episode_index,
            global_frame_index,
            states,
            actions,
            timestamps_s,
            output_dir,
        )
        logger.info("  Wrote parquet: %d rows", n_frames)

        # 4. Encode video.
        video_path = _encode_video(episode_index, images, output_dir)
        logger.info("  Encoded video: %d frames", n_frames)

        # Free images immediately.
        del images

        # 5. Upload and delete local files.
        if client is not None:
            pr = f"data/chunk-{episode_index:03d}/file-{episode_index:03d}.parquet"
            vr = (
                f"videos/observation.images.color/"
                f"chunk-{episode_index:03d}/file-{episode_index:03d}.mp4"
            )
            _upload_and_delete(client, upload_prefix, parquet_path, pr, root_dir=output_dir)
            _upload_and_delete(client, upload_prefix, video_path, vr, root_dir=output_dir)
            logger.info("  Uploaded & cleaned episode %d", episode_index)

        # 6. Update running stats.
        state_arr = np.stack(states)
        action_arr = np.stack(actions)
        state_stats.update_batch(state_arr)
        action_stats.update_batch(action_arr)

        duration_s = timestamps_s[-1] if timestamps_s else 0.0
        global_frame_index += n_frames
        episodes.append(
            EpisodeSummary(episode_index, bag_name, n_frames, duration_s)
        )
        completed_bags.add(bag_name)

        # 7. Checkpoint.
        _save_checkpoint(
            checkpoint_path,
            episodes,
            completed_bags,
            global_frame_index,
            state_stats,
            action_stats,
        )

        logger.info(
            "  Progress: %d/%d bags, %d episodes, %d frames",
            len(completed_bags),
            total_bags,
            len(episodes),
            global_frame_index,
        )

    # 8. Write and upload meta.
    if not episodes:
        logger.error("No episodes converted")
        return

    _write_and_upload_meta(
        episodes,
        state_stats,
        action_stats,
        global_frame_index,
        client,
        upload_prefix,
        output_dir,
    )

    # Clean up checkpoint.
    if checkpoint_path.exists():
        checkpoint_path.unlink()

    logger.info(
        "Complete: %d episodes, %d frames, %d skipped",
        len(episodes),
        global_frame_index,
        skipped,
    )


# -- CLI --------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Stream-convert rosbags to a single LeRobot v3 dataset.",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).parent / "config.yaml",
        help="Path to config.yaml",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("C:/Data/houston-lerobot"),
        help="Local working directory (transient when uploading)",
    )
    parser.add_argument(
        "--max-bags",
        type=int,
        default=None,
        help="Limit to first N bags",
    )
    parser.add_argument(
        "--skip-upload",
        action="store_true",
        help="Keep files locally instead of uploading",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume an interrupted conversion",
    )

    args = parser.parse_args()

    t0 = time.time()
    batch_convert(
        config_path=args.config,
        output_dir=args.output,
        max_bags=args.max_bags,
        skip_upload=args.skip_upload,
        resume=args.resume,
    )
    elapsed = time.time() - t0
    logger.info("Total time: %.0f s (%.1f min)", elapsed, elapsed / 60)


if __name__ == "__main__":
    main()
