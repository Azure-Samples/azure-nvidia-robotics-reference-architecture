#!/usr/bin/env python3
"""Offline inference evaluation for LeRobot ACT policies.

Loads a pretrained ACT checkpoint and replays episode data from a LeRobot
v3 dataset, comparing predicted actions against ground-truth action deltas.
Outputs an .npz file and optional trajectory plots for visual inspection
prior to physical deployment.

Usage:
    python scripts/test-lerobot-inference.py \
        --checkpoint-dir outputs/train-houston-ur10e/checkpoints/050000/pretrained_model \
        --dataset-dir tmp/houston_lerobot_fixed \
        --episode 0 \
        --device mps \
        --output tmp/trajectory_plots/ep000_predictions.npz \
        --plot
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from pathlib import Path

import av
import matplotlib.pyplot as plt
import numpy as np
import torch

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("test-inference")

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
# Data loading
# ------------------------------------------------------------------


def load_episode_data(
    dataset_dir: Path, episode_index: int
) -> dict[str, np.ndarray]:
    """Load observation states and ground-truth actions for one episode.

    Reads parquet files directly via pyarrow (no pandas dependency).

    Returns dict with keys: states (N, 6), actions (N, 6), timestamps (N,).
    """
    import pyarrow.parquet as pq

    data_dir = dataset_dir / "data"
    chunk_dir = data_dir / f"chunk-{episode_index:03d}"
    parquet_path = chunk_dir / f"file-{episode_index:03d}.parquet"

    if not parquet_path.exists():
        # Fall back to scanning all parquet files
        parquet_path = _find_episode_parquet(data_dir, episode_index)

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

    # Sort by frame_index
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


def _find_episode_parquet(
    data_dir: Path, episode_index: int
) -> Path:
    """Scan data directory for a parquet containing the target episode."""
    import pyarrow.parquet as pq

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
# Policy loading
# ------------------------------------------------------------------


def load_policy(
    checkpoint_dir: Path,
    dataset_dir: Path | None,
    device: str,
) -> torch.nn.Module:
    """Load ACT policy from checkpoint with normalization stats.

    If the checkpoint directory lacks preprocessor/postprocessor files,
    normalization stats are injected from the dataset's stats.json.
    """
    from lerobot.policies.act.modeling_act import ACTPolicy

    logger.info("Loading ACT policy from %s", checkpoint_dir)

    has_preprocessor = (
        checkpoint_dir / "policy_preprocessor_step_3_normalizer_processor.safetensors"
    ).exists()

    policy = ACTPolicy.from_pretrained(str(checkpoint_dir))

    if not has_preprocessor and dataset_dir is not None:
        logger.info(
            "Preprocessor files not found in checkpoint — "
            "injecting normalization stats from dataset stats.json"
        )
        _inject_norm_stats(policy, dataset_dir)
    elif not has_preprocessor:
        logger.warning(
            "No preprocessor files and no dataset dir — "
            "normalization may be incorrect"
        )

    policy.to(device)
    policy.eval()

    n_params = sum(p.numel() for p in policy.parameters())
    logger.info("Policy loaded — %.1fM parameters on %s", n_params / 1e6, device)
    return policy


def _inject_norm_stats(
    policy: torch.nn.Module, dataset_dir: Path
) -> None:
    """Inject normalization mean/std from dataset stats.json into the policy."""
    stats_path = dataset_dir / "meta" / "stats.json"
    if not stats_path.exists():
        logger.warning("stats.json not found at %s", stats_path)
        return

    with open(stats_path) as f:
        stats = json.load(f)

    def _set_buffer(module, buf_name: str, stat_name: str, value):
        if hasattr(module, buf_name):
            param_dict = getattr(module, buf_name)
            if stat_name in param_dict:
                tensor = torch.tensor(value, dtype=torch.float32)
                param_dict[stat_name].data.copy_(tensor)
                logger.debug("Set %s.%s", buf_name, stat_name)

    # Normalize inputs — observation.state
    if "observation.state" in stats:
        s = stats["observation.state"]
        _set_buffer(
            policy.normalize_inputs,
            "buffer_observation_state",
            "mean",
            s["mean"],
        )
        _set_buffer(
            policy.normalize_inputs,
            "buffer_observation_state",
            "std",
            s["std"],
        )
        # Also set normalize_targets (used during training)
        _set_buffer(
            policy.normalize_targets,
            "buffer_observation_state",
            "mean",
            s["mean"],
        )
        _set_buffer(
            policy.normalize_targets,
            "buffer_observation_state",
            "std",
            s["std"],
        )

    # Normalize inputs — observation.images.color (ImageNet stats)
    if "observation.images.color" in stats:
        s = stats["observation.images.color"]
        _set_buffer(
            policy.normalize_inputs,
            "buffer_observation_images_color",
            "mean",
            s["mean"],
        )
        _set_buffer(
            policy.normalize_inputs,
            "buffer_observation_images_color",
            "std",
            s["std"],
        )

    # Unnormalize outputs — action
    if "action" in stats:
        s = stats["action"]
        _set_buffer(
            policy.unnormalize_outputs,
            "buffer_action",
            "mean",
            s["mean"],
        )
        _set_buffer(
            policy.unnormalize_outputs,
            "buffer_action",
            "std",
            s["std"],
        )
        # normalize_targets for action
        _set_buffer(
            policy.normalize_targets,
            "buffer_action",
            "mean",
            s["mean"],
        )
        _set_buffer(
            policy.normalize_targets,
            "buffer_action",
            "std",
            s["std"],
        )

    logger.info("Normalization stats injected from %s", stats_path)


# ------------------------------------------------------------------
# Inference loop
# ------------------------------------------------------------------


def run_inference(
    policy: torch.nn.Module,
    states: np.ndarray,
    actions: np.ndarray,
    frames: list[np.ndarray],
    device: str,
    start_frame: int = 0,
    num_steps: int | None = None,
) -> dict[str, np.ndarray]:
    """Run step-by-step inference and collect predictions.

    At each step the policy receives the ground-truth observation state
    and the corresponding video frame, then predicts the next action.
    The initial joint state comes from the episode data at start_frame.

    Returns dict with predicted (N,6), ground_truth (N,6), inference_times (N,).
    """
    n_total = len(states)
    end_frame = min(n_total, start_frame + (num_steps or n_total))
    # Last frame has no ground-truth action delta
    n_steps = end_frame - start_frame - 1

    predicted_actions = []
    gt_actions = []
    inference_times = []

    policy.reset()

    logger.info(
        "Running inference: frames %d–%d (%d steps)",
        start_frame,
        end_frame - 1,
        n_steps,
    )

    for step in range(n_steps):
        frame_idx = start_frame + step
        state = states[frame_idx]
        image = frames[frame_idx]

        # Build observation batch
        state_tensor = (
            torch.from_numpy(state).float().unsqueeze(0).to(device)
        )
        img_tensor = (
            torch.from_numpy(image).float().permute(2, 0, 1) / 255.0
        ).unsqueeze(0).to(device)

        obs = {
            "observation.state": state_tensor,
            "observation.images.color": img_tensor,
        }

        t0 = time.monotonic()
        with torch.inference_mode():
            action = policy.select_action(obs)
        dt = time.monotonic() - t0

        action_np = action.cpu().numpy()
        if action_np.ndim == 2:
            action_np = action_np[0]

        predicted_actions.append(action_np)
        gt_actions.append(actions[frame_idx])
        inference_times.append(dt)

        if (step + 1) % 100 == 0 or step == 0:
            logger.info(
                "  Step %d/%d — inference %.1f ms",
                step + 1,
                n_steps,
                dt * 1000,
            )

    result = {
        "predicted": np.array(predicted_actions, dtype=np.float32),
        "ground_truth": np.array(gt_actions, dtype=np.float32),
        "inference_times": np.array(inference_times, dtype=np.float64),
    }

    # Summary statistics
    error = np.abs(result["predicted"] - result["ground_truth"])
    mae = np.mean(error)
    per_joint_mae = np.mean(error, axis=0)
    mean_latency_ms = np.mean(result["inference_times"]) * 1000

    logger.info("Steps evaluated: %d", n_steps)
    logger.info("Overall MAE: %.6f rad", mae)
    logger.info(
        "Per-joint MAE: %s",
        ", ".join(
            f"{name}={v:.6f}"
            for name, v in zip(JOINT_NAMES, per_joint_mae)
        ),
    )
    logger.info("Mean inference latency: %.1f ms", mean_latency_ms)
    logger.info(
        "Realtime capable (<%d ms): %s",
        int(1000 / FPS),
        "yes" if mean_latency_ms < 1000 / FPS else "no",
    )

    return result


# ------------------------------------------------------------------
# Plotting (matches tmp/plot_trajectories.py and batch_inference_plot.py)
# ------------------------------------------------------------------


def plot_action_deltas(
    predicted: np.ndarray,
    ground_truth: np.ndarray,
    out_dir: Path,
    episode: int,
) -> None:
    """Per-joint action deltas: predicted vs ground truth."""
    n_steps, n_joints = predicted.shape
    t = np.arange(n_steps) / FPS

    fig, axes = plt.subplots(
        n_joints, 1, figsize=(14, 2.5 * n_joints), sharex=True
    )
    fig.suptitle(
        f"Episode {episode} — Action Deltas: Predicted vs Ground Truth",
        fontsize=14,
        fontweight="bold",
    )
    for j, ax in enumerate(axes):
        ax.plot(
            t, ground_truth[:, j],
            color="#2196F3", alpha=0.8, linewidth=1.2, label="Ground Truth",
        )
        ax.plot(
            t, predicted[:, j],
            color="#FF5722", alpha=0.8, linewidth=1.2, label="Predicted",
        )
        ax.fill_between(
            t, ground_truth[:, j], predicted[:, j],
            alpha=0.15, color="#9C27B0",
        )
        ax.set_ylabel(f"{JOINT_NAMES[j]}\n(rad)", fontsize=9)
        ax.grid(True, alpha=0.3)
        ax.tick_params(labelsize=8)
        if j == 0:
            ax.legend(loc="upper right", fontsize=8)
    axes[-1].set_xlabel("Time (s)", fontsize=10)
    fig.tight_layout()
    fig.savefig(out_dir / "action_deltas.png", dpi=150, bbox_inches="tight")
    plt.close(fig)


def plot_cumulative_positions(
    predicted: np.ndarray,
    ground_truth: np.ndarray,
    out_dir: Path,
    episode: int,
    initial_state: np.ndarray | None = None,
) -> None:
    """Reconstruct absolute joint positions from cumulative deltas."""
    pred_pos = np.cumsum(predicted, axis=0)
    gt_pos = np.cumsum(ground_truth, axis=0)
    if initial_state is not None:
        pred_pos += initial_state
        gt_pos += initial_state

    n_steps, n_joints = predicted.shape
    t = np.arange(n_steps) / FPS

    fig, axes = plt.subplots(
        n_joints, 1, figsize=(14, 2.5 * n_joints), sharex=True
    )
    fig.suptitle(
        f"Episode {episode} — Reconstructed Joint Positions",
        fontsize=14,
        fontweight="bold",
    )
    for j, ax in enumerate(axes):
        ax.plot(
            t, gt_pos[:, j],
            color="#2196F3", alpha=0.8, linewidth=1.2, label="Ground Truth",
        )
        ax.plot(
            t, pred_pos[:, j],
            color="#FF5722", alpha=0.8, linewidth=1.2, label="Predicted",
        )
        ax.fill_between(
            t, gt_pos[:, j], pred_pos[:, j], alpha=0.15, color="#9C27B0",
        )
        ax.set_ylabel(f"{JOINT_NAMES[j]}\n(rad)", fontsize=9)
        ax.grid(True, alpha=0.3)
        ax.tick_params(labelsize=8)
        if j == 0:
            ax.legend(loc="upper right", fontsize=8)
    axes[-1].set_xlabel("Time (s)", fontsize=10)
    fig.tight_layout()
    fig.savefig(
        out_dir / "cumulative_positions.png", dpi=150, bbox_inches="tight"
    )
    plt.close(fig)


def plot_error_heatmap(
    predicted: np.ndarray,
    ground_truth: np.ndarray,
    out_dir: Path,
    episode: int,
) -> None:
    """Absolute error heatmap across joints and time."""
    error = np.abs(predicted - ground_truth)
    n_steps = error.shape[0]
    t = np.arange(n_steps) / FPS

    fig, ax = plt.subplots(figsize=(14, 3))
    im = ax.imshow(
        error.T,
        aspect="auto",
        cmap="hot",
        interpolation="nearest",
        extent=[t[0], t[-1], len(JOINT_NAMES) - 0.5, -0.5],
    )
    ax.set_yticks(range(len(JOINT_NAMES)))
    ax.set_yticklabels(JOINT_NAMES, fontsize=9)
    ax.set_xlabel("Time (s)", fontsize=10)
    ax.set_title(
        f"Episode {episode} — Absolute Error Heatmap",
        fontsize=12,
        fontweight="bold",
    )
    fig.colorbar(im, ax=ax, label="Error (rad)")
    fig.tight_layout()
    fig.savefig(out_dir / "error_heatmap.png", dpi=150, bbox_inches="tight")
    plt.close(fig)


def plot_summary_panel(
    predicted: np.ndarray,
    ground_truth: np.ndarray,
    inference_times: np.ndarray,
    out_dir: Path,
    episode: int,
) -> None:
    """2x2 summary: joint overlay, error boxplot, latency, per-joint MAE."""
    error = np.abs(predicted - ground_truth)
    n_steps, n_joints = predicted.shape
    t = np.arange(n_steps) / FPS
    colors = plt.cm.tab10(np.linspace(0, 1, n_joints))

    fig, axes = plt.subplots(2, 2, figsize=(14, 8))
    fig.suptitle(
        f"Episode {episode} — Inference Summary",
        fontsize=14,
        fontweight="bold",
    )

    # Top-left: all joints overlaid
    ax = axes[0, 0]
    for j in range(n_joints):
        ax.plot(t, ground_truth[:, j], color=colors[j], alpha=0.6, linewidth=1.0)
        ax.plot(
            t, predicted[:, j],
            color=colors[j], alpha=0.6, linewidth=1.0, linestyle="--",
        )
    ax.set_xlabel("Time (s)", fontsize=9)
    ax.set_ylabel("Action delta (rad)", fontsize=9)
    ax.set_title("All Joints (solid=GT, dashed=pred)", fontsize=10)
    ax.grid(True, alpha=0.3)

    # Top-right: error distribution per joint
    ax = axes[0, 1]
    bp = ax.boxplot(
        [error[:, j] for j in range(n_joints)],
        tick_labels=JOINT_NAMES,
        patch_artist=True,
    )
    for patch, color in zip(bp["boxes"], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.5)
    ax.set_ylabel("Absolute Error (rad)", fontsize=9)
    ax.set_title("Error Distribution per Joint", fontsize=10)
    ax.tick_params(axis="x", rotation=30, labelsize=8)
    ax.grid(True, alpha=0.3, axis="y")

    # Bottom-left: inference timing
    ax = axes[1, 0]
    inf_ms = inference_times * 1000
    ax.plot(inf_ms, color="#4CAF50", alpha=0.7, linewidth=0.8)
    ax.axhline(
        y=1000 / FPS,
        color="#F44336",
        linestyle="--",
        alpha=0.7,
        label=f"Realtime ({1000/FPS:.1f}ms)",
    )
    ax.set_xlabel("Step", fontsize=9)
    ax.set_ylabel("Inference time (ms)", fontsize=9)
    ax.set_title("Inference Latency", fontsize=10)
    ax.legend(fontsize=8)
    ax.grid(True, alpha=0.3)
    ax.set_ylim(0, min(np.percentile(inf_ms, 99) * 2, inf_ms.max() * 1.1))

    # Bottom-right: per-joint MAE bar chart
    ax = axes[1, 1]
    per_joint_mae = np.mean(error, axis=0)
    bars = ax.bar(
        JOINT_NAMES, per_joint_mae, color=colors[:n_joints], alpha=0.7
    )
    ax.set_ylabel("MAE (rad)", fontsize=9)
    ax.set_title("Per-Joint Mean Absolute Error", fontsize=10)
    ax.tick_params(axis="x", rotation=30, labelsize=8)
    ax.grid(True, alpha=0.3, axis="y")
    for bar, val in zip(bars, per_joint_mae):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height(),
            f"{val:.4f}",
            ha="center",
            va="bottom",
            fontsize=7,
        )

    fig.tight_layout()
    fig.savefig(out_dir / "summary_panel.png", dpi=150, bbox_inches="tight")
    plt.close(fig)


def generate_plots(
    result: dict[str, np.ndarray],
    out_dir: Path,
    episode: int,
    initial_state: np.ndarray | None = None,
) -> None:
    """Generate all 4 trajectory comparison plots."""
    out_dir.mkdir(parents=True, exist_ok=True)

    pred = result["predicted"]
    gt = result["ground_truth"]
    inf_times = result["inference_times"]

    plot_action_deltas(pred, gt, out_dir, episode)
    plot_cumulative_positions(pred, gt, out_dir, episode, initial_state)
    plot_error_heatmap(pred, gt, out_dir, episode)
    plot_summary_panel(pred, gt, inf_times, out_dir, episode)

    logger.info("Plots saved to %s", out_dir)


# ------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Offline ACT policy inference evaluation"
    )
    p.add_argument(
        "--checkpoint-dir",
        type=str,
        required=True,
        help="Path to pretrained_model directory",
    )
    p.add_argument(
        "--dataset-dir",
        type=str,
        required=True,
        help="Path to LeRobot v3 dataset root",
    )
    p.add_argument(
        "--episode",
        type=int,
        default=0,
        help="Episode index to evaluate (default: 0)",
    )
    p.add_argument(
        "--start-frame",
        type=int,
        default=0,
        help="Starting frame index within the episode (default: 0)",
    )
    p.add_argument(
        "--num-steps",
        type=int,
        default=None,
        help="Max inference steps (default: all frames in episode)",
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
        default=None,
        help="Path to save predictions .npz (default: auto-generated)",
    )
    p.add_argument(
        "--plot",
        action="store_true",
        help="Generate trajectory comparison plots",
    )
    p.add_argument(
        "--plot-dir",
        type=str,
        default=None,
        help="Directory for plot output (default: alongside .npz)",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()

    checkpoint_dir = Path(args.checkpoint_dir).resolve()
    dataset_dir = Path(args.dataset_dir).resolve()

    if not checkpoint_dir.exists():
        logger.error("Checkpoint not found: %s", checkpoint_dir)
        sys.exit(1)
    if not dataset_dir.exists():
        logger.error("Dataset not found: %s", dataset_dir)
        sys.exit(1)

    # Load episode data
    ep_data = load_episode_data(dataset_dir, args.episode)
    initial_state = ep_data["states"][args.start_frame]
    logger.info(
        "Initial joint state (episode %d, frame %d): %s",
        args.episode,
        args.start_frame,
        initial_state,
    )

    # Load video frames
    n_frames_needed = len(ep_data["states"])
    if args.num_steps is not None:
        n_frames_needed = min(
            n_frames_needed, args.start_frame + args.num_steps + 1
        )
    frames = load_video_frames(dataset_dir, args.episode, n_frames_needed)

    # Load policy
    policy = load_policy(checkpoint_dir, dataset_dir, args.device)

    # Run inference
    result = run_inference(
        policy,
        ep_data["states"],
        ep_data["actions"],
        frames,
        args.device,
        start_frame=args.start_frame,
        num_steps=args.num_steps,
    )

    # Save predictions
    if args.output:
        out_path = Path(args.output)
    else:
        out_path = Path(f"tmp/trajectory_plots/ep{args.episode:03d}_predictions.npz")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    np.savez(
        out_path,
        predicted=result["predicted"],
        ground_truth=result["ground_truth"],
        inference_times=result["inference_times"],
    )
    logger.info("Predictions saved to %s", out_path)

    # Generate plots
    if args.plot:
        if args.plot_dir:
            plot_dir = Path(args.plot_dir)
        else:
            plot_dir = out_path.parent / f"episode_{args.episode:03d}"
        generate_plots(result, plot_dir, args.episode, initial_state)


if __name__ == "__main__":
    main()
