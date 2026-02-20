"""Offline inference evaluation for the UR10e ACT policy.

Loads a pretrained ACT checkpoint, replays episode data from a LeRobot
v3 dataset, and logs predicted actions alongside ground-truth joint
positions into a parquet dataset for analysis.

The policy uses normalization statistics embedded in model.safetensors
(training-checkpoint format) — no separate preprocessor files needed.

Usage
-----
    python -m ur10e_deploy.offline_eval \
        --checkpoint outputs/train-houston-ur10e/checkpoints/050000/pretrained_model \
        --dataset tmp/houston_lerobot_fixed \
        --episode 0 \
        --device mps \
        --output tmp/inference_results

    # Multiple episodes
    python -m ur10e_deploy.offline_eval \
        --checkpoint outputs/train-houston-ur10e/checkpoints/050000/pretrained_model \
        --dataset tmp/houston_lerobot_fixed \
        --episode 0 1 2 3 \
        --device mps
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

import av
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq
import torch

from .config import PolicyConfig
from .policy_runner import PolicyRunner

logger = logging.getLogger(__name__)

JOINT_NAMES = [
    "shoulder_pan",
    "shoulder_lift",
    "elbow",
    "wrist_1",
    "wrist_2",
    "wrist_3",
]
FPS = 30


# ------------------------------------------------------------------
# Data loading (pyarrow-native, no pandas dependency)
# ------------------------------------------------------------------


def load_episode_data(
    dataset_dir: Path, episode_index: int
) -> dict[str, np.ndarray]:
    """Load observation states and ground-truth actions for one episode.

    Returns dict with keys: states (N, 6), actions (N, 6), timestamps (N,).
    """
    chunk_dir = dataset_dir / "data" / f"chunk-{episode_index:03d}"
    parquet_path = chunk_dir / f"file-{episode_index:03d}.parquet"

    if not parquet_path.exists():
        parquet_path = _find_episode_parquet(
            dataset_dir / "data", episode_index
        )

    table = pq.read_table(parquet_path)

    ep_col = table.column("episode_index")
    frame_col = table.column("frame_index")
    state_col = table.column("observation.state")
    action_col = table.column("action")
    ts_col = table.column("timestamp")

    indices = [
        i for i in range(len(ep_col)) if ep_col[i].as_py() == episode_index
    ]
    if not indices:
        raise ValueError(
            f"Episode {episode_index} not found in {parquet_path}"
        )

    frame_order = sorted(indices, key=lambda i: frame_col[i].as_py())

    states = np.array(
        [state_col[i].as_py() for i in frame_order], dtype=np.float32
    )
    actions = np.array(
        [action_col[i].as_py() for i in frame_order], dtype=np.float32
    )
    timestamps = np.array(
        [ts_col[i].as_py() for i in frame_order], dtype=np.float64
    )

    logger.info(
        "Episode %d: %d frames, state shape %s",
        episode_index,
        len(states),
        states.shape,
    )
    return {"states": states, "actions": actions, "timestamps": timestamps}


def _find_episode_parquet(data_dir: Path, episode_index: int) -> Path:
    """Scan data directory for a parquet containing the target episode."""
    for pf in sorted(data_dir.rglob("*.parquet")):
        table = pq.read_table(pf, columns=["episode_index"])
        eps = {row.as_py() for row in table.column("episode_index")}
        if episode_index in eps:
            return pf
    raise FileNotFoundError(
        f"No parquet file found for episode {episode_index} in {data_dir}"
    )


def load_video_frames(
    dataset_dir: Path, episode_index: int, n_frames: int
) -> list[np.ndarray]:
    """Decode video frames for an episode from the dataset MP4 file.

    Returns list of (H, W, 3) uint8 numpy arrays.
    """
    video_path = (
        dataset_dir
        / "videos"
        / "observation.images.color"
        / f"chunk-{episode_index:03d}"
        / f"file-{episode_index:03d}.mp4"
    )
    if not video_path.exists():
        raise FileNotFoundError(f"Video not found: {video_path}")

    frames = []
    container = av.open(str(video_path))
    for frame in container.decode(video=0):
        frames.append(frame.to_ndarray(format="rgb24"))
        if len(frames) >= n_frames:
            break
    container.close()

    if len(frames) < n_frames:
        logger.warning(
            "Video has %d frames, expected %d — padding with last frame",
            len(frames),
            n_frames,
        )
        while len(frames) < n_frames:
            frames.append(frames[-1])

    return frames


# ------------------------------------------------------------------
# Inference loop
# ------------------------------------------------------------------


def run_episode_inference(
    policy: PolicyRunner,
    states: np.ndarray,
    actions: np.ndarray,
    frames: list[np.ndarray],
    start_frame: int = 0,
    num_steps: int | None = None,
) -> list[dict]:
    """Run step-by-step inference and collect per-step records.

    At each step, the policy receives the ground-truth observation state
    and video frame (teacher-forcing), then predicts the next action
    delta. The initial joint state comes from the episode data.

    Returns a list of per-step dicts ready for parquet serialization.
    """
    n_total = len(states)
    end_frame = min(n_total, start_frame + (num_steps or n_total))
    n_steps = end_frame - start_frame - 1

    policy.reset()

    logger.info(
        "Running inference: frames %d–%d (%d steps)",
        start_frame,
        end_frame - 1,
        n_steps,
    )

    records: list[dict] = []

    for step in range(n_steps):
        frame_idx = start_frame + step
        state = states[frame_idx]
        image = frames[frame_idx]

        t0 = time.monotonic()
        predicted_action = policy.predict(state, image)
        dt = time.monotonic() - t0

        gt_action = actions[frame_idx]

        records.append({
            "step": step,
            "frame_index": frame_idx,
            "timestamp": frame_idx / FPS,
            "inference_time_s": dt,
            **{
                f"joint_position_{JOINT_NAMES[j]}": float(state[j])
                for j in range(6)
            },
            **{
                f"predicted_action_{JOINT_NAMES[j]}": float(predicted_action[j])
                for j in range(6)
            },
            **{
                f"gt_action_{JOINT_NAMES[j]}": float(gt_action[j])
                for j in range(6)
            },
            **{
                f"abs_error_{JOINT_NAMES[j]}": float(
                    abs(predicted_action[j] - gt_action[j])
                )
                for j in range(6)
            },
        })

        if (step + 1) % 100 == 0 or step == 0:
            logger.info(
                "  Step %d/%d — inference %.1f ms",
                step + 1,
                n_steps,
                dt * 1000,
            )

    return records


# ------------------------------------------------------------------
# Parquet output
# ------------------------------------------------------------------


def records_to_table(records: list[dict], episode_index: int) -> pa.Table:
    """Convert per-step records to a pyarrow Table with episode metadata."""
    for rec in records:
        rec["episode_index"] = episode_index

    columns = list(records[0].keys())
    arrays = {col: pa.array([r[col] for r in records]) for col in columns}
    return pa.table(arrays)


def write_parquet(table: pa.Table, output_path: Path) -> None:
    """Write a pyarrow Table to a parquet file."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    pq.write_table(table, output_path)
    logger.info("Results written to %s (%d rows)", output_path, table.num_rows)


def print_summary(records: list[dict], episode_index: int) -> None:
    """Print per-joint MAE and latency summary to the logger."""
    n = len(records)
    if n == 0:
        return

    per_joint_mae = {}
    for j_name in JOINT_NAMES:
        errors = [r[f"abs_error_{j_name}"] for r in records]
        per_joint_mae[j_name] = np.mean(errors)

    overall_mae = np.mean(list(per_joint_mae.values()))
    latencies = [r["inference_time_s"] * 1000 for r in records]
    mean_latency = np.mean(latencies)

    logger.info("--- Episode %d Summary ---", episode_index)
    logger.info("  Steps evaluated: %d", n)
    logger.info("  Overall MAE: %.6f rad", overall_mae)
    for j_name, mae_val in per_joint_mae.items():
        logger.info("    %-15s MAE: %.6f rad", j_name, mae_val)
    logger.info("  Mean inference latency: %.1f ms", mean_latency)
    logger.info(
        "  Realtime capable (<%d ms): %s",
        int(1000 / FPS),
        "yes" if mean_latency < 1000 / FPS else "no",
    )


# ------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Offline UR10e ACT policy evaluation with parquet logging"
    )
    p.add_argument(
        "--checkpoint",
        type=str,
        required=True,
        help="Path to pretrained_model directory",
    )
    p.add_argument(
        "--dataset",
        type=str,
        required=True,
        help="Path to LeRobot v3 dataset root (e.g. tmp/houston_lerobot_fixed)",
    )
    p.add_argument(
        "--episode",
        type=int,
        nargs="+",
        default=[0],
        help="Episode index(es) to evaluate (default: 0)",
    )
    p.add_argument(
        "--start-frame",
        type=int,
        default=0,
        help="Starting frame index within each episode (default: 0)",
    )
    p.add_argument(
        "--num-steps",
        type=int,
        default=None,
        help="Max inference steps per episode (default: all frames)",
    )
    p.add_argument(
        "--device",
        type=str,
        default="mps",
        help="Torch device: cuda, cpu, or mps (default: mps)",
    )
    p.add_argument(
        "--output",
        type=str,
        default="tmp/inference_results",
        help="Output directory for parquet files (default: tmp/inference_results)",
    )
    return p.parse_args()


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    args = parse_args()

    checkpoint_dir = Path(args.checkpoint).resolve()
    dataset_dir = Path(args.dataset).resolve()
    output_dir = Path(args.output)

    if not checkpoint_dir.exists():
        logger.error("Checkpoint not found: %s", checkpoint_dir)
        sys.exit(1)
    if not dataset_dir.exists():
        logger.error("Dataset not found: %s", dataset_dir)
        sys.exit(1)

    # Load policy once — reuse across episodes
    policy_cfg = PolicyConfig(
        checkpoint_dir=str(checkpoint_dir),
        device=args.device,
        temporal_ensemble_coeff=None,
    )
    policy = PolicyRunner(policy_cfg)
    policy.load()

    all_tables: list[pa.Table] = []

    for ep_idx in args.episode:
        logger.info("=" * 60)
        logger.info("Episode %d", ep_idx)
        logger.info("=" * 60)

        # Load episode data
        ep_data = load_episode_data(dataset_dir, ep_idx)
        initial_state = ep_data["states"][args.start_frame]
        logger.info(
            "Initial joint state (episode %d, frame %d): %s",
            ep_idx,
            args.start_frame,
            initial_state,
        )

        # Load video frames
        n_frames = len(ep_data["states"])
        if args.num_steps is not None:
            n_frames = min(n_frames, args.start_frame + args.num_steps + 1)
        video_frames = load_video_frames(dataset_dir, ep_idx, n_frames)

        # Run inference
        records = run_episode_inference(
            policy,
            ep_data["states"],
            ep_data["actions"],
            video_frames,
            start_frame=args.start_frame,
            num_steps=args.num_steps,
        )

        # Print summary
        print_summary(records, ep_idx)

        # Convert to table
        table = records_to_table(records, ep_idx)
        all_tables.append(table)

        # Write per-episode parquet
        ep_path = output_dir / f"episode_{ep_idx:03d}.parquet"
        write_parquet(table, ep_path)

    # Write combined parquet if multiple episodes
    if len(all_tables) > 1:
        combined = pa.concat_tables(all_tables)
        combined_path = output_dir / "all_episodes.parquet"
        write_parquet(combined, combined_path)

    logger.info("Inference complete — results in %s", output_dir)


if __name__ == "__main__":
    main()
