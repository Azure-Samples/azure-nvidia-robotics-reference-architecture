"""Train ACT policy directly from rosbag data.

Reads ROS2 bags, synchronises joint states and camera images at the
target FPS, builds a PyTorch Dataset, and trains a standalone ACT model.
No lerobot conversion or dependency required.

Usage:
    python train.py                   # uses default config.yaml
    python train.py --config my.yaml  # custom config
"""

from __future__ import annotations

import argparse
import io
import json
import logging
import math
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.distributed as dist
import torch.nn as nn
import yaml
from PIL import Image as PILImage
from rosbags.highlevel import AnyReader
from rosbags.typesys import Stores, get_typestore
from safetensors.torch import save_file
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import DataLoader, Dataset
from torch.utils.data.distributed import DistributedSampler
from torchvision import transforms
from tqdm import tqdm

from act_model import ACTModel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s  %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("train")


# -----------------------------------------------------------------------
# Distributed training helpers
# -----------------------------------------------------------------------

def _is_ddp() -> bool:
    """Return True when launched via torchrun / torch.distributed.launch."""
    return "RANK" in os.environ and "WORLD_SIZE" in os.environ


def _ddp_rank() -> int:
    return int(os.environ.get("RANK", 0))


def _ddp_local_rank() -> int:
    return int(os.environ.get("LOCAL_RANK", 0))


def _ddp_world_size() -> int:
    return int(os.environ.get("WORLD_SIZE", 1))


def _ddp_init() -> None:
    """Initialise the default process group for NCCL."""
    dist.init_process_group(backend="nccl")
    torch.cuda.set_device(_ddp_local_rank())
    logger.info(
        "DDP initialised — rank %d/%d  local_rank %d",
        _ddp_rank(), _ddp_world_size(), _ddp_local_rank(),
    )


def _ddp_cleanup() -> None:
    if dist.is_initialized():
        dist.destroy_process_group()


# -----------------------------------------------------------------------
# Wandb experiment tracking
# -----------------------------------------------------------------------

def _wandb_enabled(cfg: dict) -> bool:
    """Check if wandb logging is enabled via config."""
    return cfg.get("wandb", {}).get("enabled", False)


def _init_wandb(cfg: dict) -> None:
    """Initialise a wandb run from the config dict."""
    try:
        import wandb
    except ImportError:
        logger.warning("wandb not installed — skipping experiment tracking")
        return

    wcfg = cfg.get("wandb", {})
    wandb.init(
        project=wcfg.get("project", "ur10e-act-train"),
        name=wcfg.get("run_name", None),
        config=cfg,
        tags=wcfg.get("tags", []),
    )
    logger.info("Wandb run initialised: %s", wandb.run.name)


def _log_wandb(metrics: dict, step: int) -> None:
    """Log metrics to wandb if available."""
    try:
        import wandb
        if wandb.run is not None:
            wandb.log(metrics, step=step)
    except ImportError:
        pass


def _finish_wandb() -> None:
    """Finish the wandb run if active."""
    try:
        import wandb
        if wandb.run is not None:
            wandb.finish()
    except ImportError:
        pass


# -----------------------------------------------------------------------
# Learning rate scheduler
# -----------------------------------------------------------------------

def _build_scheduler(
    optimizer: torch.optim.Optimizer,
    tcfg: dict,
) -> torch.optim.lr_scheduler.LRScheduler | None:
    """Build LR scheduler from training config.

    Supports:
        "none"   — constant LR (default, backward compatible)
        "cosine" — linear warmup then cosine annealing to min_lr
    """
    sched_type = tcfg.get("scheduler", "none")
    if sched_type == "none":
        return None

    total_steps = tcfg["steps"]
    warmup_steps = tcfg.get("warmup_steps", 500)
    min_lr_ratio = tcfg.get("min_lr", 1e-7) / tcfg["lr"]

    def lr_lambda(current_step: int) -> float:
        if current_step < warmup_steps:
            return current_step / max(warmup_steps, 1)
        progress = (current_step - warmup_steps) / max(total_steps - warmup_steps, 1)
        return min_lr_ratio + 0.5 * (1.0 - min_lr_ratio) * (1.0 + math.cos(math.pi * progress))

    scheduler = torch.optim.lr_scheduler.LambdaLR(optimizer, lr_lambda)
    logger.info(
        "Scheduler: %s (warmup=%d steps, min_lr=%.1e)",
        sched_type, warmup_steps, tcfg.get("min_lr", 1e-7),
    )
    return scheduler


# UR10e standard joint order
STANDARD_JOINT_ORDER = [
    "shoulder_pan_joint",
    "shoulder_lift_joint",
    "elbow_joint",
    "wrist_1_joint",
    "wrist_2_joint",
    "wrist_3_joint",
]


# -----------------------------------------------------------------------
# Rosbag reading (inline — no external converter dependency)
# -----------------------------------------------------------------------

def _build_reorder_map(bag_names: list[str]) -> list[int] | None:
    if list(bag_names) == STANDARD_JOINT_ORDER:
        return None
    name_to_idx = {n: i for i, n in enumerate(bag_names)}
    return [name_to_idx[n] for n in STANDARD_JOINT_ORDER]


@dataclass
class _JointSample:
    ts: int            # nanoseconds
    position: np.ndarray  # (6,)


@dataclass
class _ImageSample:
    ts: int
    image: np.ndarray  # (H, W, 3) uint8 RGB


def _decode_image(msg, msgtype: str) -> np.ndarray | None:
    """Decode a ROS image message to (H, W, 3) uint8 RGB."""
    if "CompressedImage" in msgtype:
        buf = bytes(msg.data)
        pil = PILImage.open(io.BytesIO(buf)).convert("RGB")
        return np.asarray(pil)

    encoding = getattr(msg, "encoding", "rgb8")
    h, w = msg.height, msg.width
    data = np.frombuffer(bytes(msg.data), dtype=np.uint8 if "8" in encoding else None)

    if encoding in ("rgb8",):
        return data.reshape(h, w, 3)
    if encoding in ("bgr8",):
        return data.reshape(h, w, 3)[:, :, ::-1].copy()
    if encoding == "mono8":
        mono = data.reshape(h, w)
        return np.stack([mono] * 3, axis=-1)
    if encoding == "16UC1":
        raw = np.frombuffer(bytes(msg.data), dtype=np.uint16).reshape(h, w)
        valid = raw[raw > 0]
        if len(valid) == 0:
            return None
        lo, hi = np.percentile(valid, [1, 99])
        norm = np.clip((raw.astype(np.float32) - lo) / max(hi - lo, 1), 0, 1)
        gray = (norm * 255).astype(np.uint8)
        return np.stack([gray] * 3, axis=-1)
    if encoding == "32FC1":
        raw = np.frombuffer(bytes(msg.data), dtype=np.float32).reshape(h, w)
        finite = raw[np.isfinite(raw) & (raw > 0)]
        if len(finite) == 0:
            return None
        lo, hi = np.percentile(finite, [1, 99])
        norm = np.clip((raw - lo) / max(hi - lo, 1e-6), 0, 1)
        gray = (norm * 255).astype(np.uint8)
        return np.stack([gray] * 3, axis=-1)

    logger.warning("Unsupported image encoding: %s", encoding)
    return None


def extract_bag(
    bag_path: Path,
    joint_topic: str,
    image_topic: str,
    ros_distro: str = "ROS2_HUMBLE",
) -> tuple[list[_JointSample], list[_ImageSample]]:
    """Extract joint states and camera images from a ROS2 bag."""
    store = Stores[ros_distro]
    typestore = get_typestore(store)

    joints: list[_JointSample] = []
    images: list[_ImageSample] = []
    reorder: list[int] | None = None
    reorder_init = False

    with AnyReader([bag_path], default_typestore=typestore) as reader:
        conns = [c for c in reader.connections if c.topic in (joint_topic, image_topic)]
        for conn, ts, raw in reader.messages(connections=conns):
            msg = reader.deserialize(raw, conn.msgtype)
            if conn.topic == joint_topic:
                pos = np.array(msg.position, dtype=np.float64)
                if len(pos) != 6:
                    continue
                if not reorder_init:
                    reorder = _build_reorder_map(list(msg.name))
                    reorder_init = True
                if reorder is not None:
                    pos = pos[reorder]
                joints.append(_JointSample(ts=ts, position=pos))
            elif conn.topic == image_topic:
                arr = _decode_image(msg, conn.msgtype)
                if arr is not None:
                    images.append(_ImageSample(ts=ts, image=arr))

    joints.sort(key=lambda s: s.ts)
    images.sort(key=lambda s: s.ts)
    logger.info("Bag %s: %d joints, %d images", bag_path.name, len(joints), len(images))
    return joints, images


def synchronise(
    joints: list[_JointSample],
    images: list[_ImageSample],
    fps: int = 30,
    max_offset_ms: float = 50.0,
) -> tuple[np.ndarray, list[np.ndarray]]:
    """Synchronise joint states and images at target FPS.

    Returns:
        states: (N, 6) float64 array of joint positions.
        sync_images: list of N images as (H, W, 3) uint8 arrays.
    """
    j_ts = np.array([s.ts for s in joints], dtype=np.int64)
    i_ts = np.array([s.ts for s in images], dtype=np.int64)

    t0 = max(int(j_ts[0]), int(i_ts[0]))
    t1 = min(int(j_ts[-1]), int(i_ts[-1]))
    interval = int(1e9 / fps)
    targets = np.arange(t0, t1, interval, dtype=np.int64)

    states_list: list[np.ndarray] = []
    imgs_list: list[np.ndarray] = []

    for t in targets:
        ji = int(np.searchsorted(j_ts, t))
        ji = min(ji, len(j_ts) - 1)
        if ji > 0 and abs(int(j_ts[ji - 1]) - int(t)) < abs(int(j_ts[ji]) - int(t)):
            ji -= 1

        ii = int(np.searchsorted(i_ts, t))
        ii = min(ii, len(i_ts) - 1)
        if ii > 0 and abs(int(i_ts[ii - 1]) - int(t)) < abs(int(i_ts[ii]) - int(t)):
            ii -= 1

        j_off = abs(int(j_ts[ji]) - int(t)) / 1e6
        i_off = abs(int(i_ts[ii]) - int(t)) / 1e6
        if j_off > max_offset_ms or i_off > max_offset_ms:
            continue

        states_list.append(joints[ji].position)
        imgs_list.append(images[ii].image)

    states = np.stack(states_list) if states_list else np.empty((0, 6))
    logger.info("Synchronised %d frames at %d Hz", len(states), fps)
    return states, imgs_list


# -----------------------------------------------------------------------
# Convention conversion
# -----------------------------------------------------------------------

def apply_conventions(
    states: np.ndarray,
    joint_sign: list[float] | None,
    wrap: bool,
) -> np.ndarray:
    """Apply sign flip and angle wrapping to joint states."""
    out = states.astype(np.float32).copy()
    if joint_sign is not None:
        out *= np.array(joint_sign, dtype=np.float32)
    if wrap:
        out = np.arctan2(np.sin(out), np.cos(out)).astype(np.float32)
    return out


def resize_images(images: list[np.ndarray], target_hw: tuple[int, int]) -> list[np.ndarray]:
    h, w = target_hw
    return [cv2.resize(img, (w, h), interpolation=cv2.INTER_LINEAR) for img in images]


# -----------------------------------------------------------------------
# Dataset
# -----------------------------------------------------------------------

class RosbagACTDataset(Dataset):
    """PyTorch Dataset for ACT training from pre-loaded rosbag data.

    Each sample provides:
        state      (state_dim,)           — current joint position
        image      (3, H, W)             — camera frame (float32, normalised)
        action_chunk (chunk_size, action_dim) — future action deltas
    """

    def __init__(
        self,
        states: np.ndarray,
        images: list[np.ndarray],
        chunk_size: int,
        image_transform: transforms.Compose | None = None,
        state_mean: np.ndarray | None = None,
        state_std: np.ndarray | None = None,
        action_mean: np.ndarray | None = None,
        action_std: np.ndarray | None = None,
    ) -> None:
        assert len(states) == len(images)
        self.states = states            # (N, 6) float32
        self.images = images            # list of (H, W, 3) uint8
        self.chunk_size = chunk_size
        self.transform = image_transform

        # Compute action deltas: action[t] = state[t+1] - state[t]
        self.actions = np.diff(states, axis=0)
        self.actions = np.concatenate(
            [self.actions, np.zeros((1, states.shape[1]), dtype=np.float32)],
            axis=0,
        )

        # Valid indices: need chunk_size future actions from index t
        self.valid_len = max(len(states) - chunk_size, 1)

        # Normalisation stats
        self.state_mean = state_mean
        self.state_std = state_std
        self.action_mean = action_mean
        self.action_std = action_std

    def __len__(self) -> int:
        return self.valid_len

    def __getitem__(self, idx: int) -> dict:
        state = self.states[idx].copy()
        image = self.images[idx]  # (H, W, 3) uint8

        # Build action chunk
        end = min(idx + self.chunk_size, len(self.actions))
        chunk = self.actions[idx:end].copy()
        if len(chunk) < self.chunk_size:
            pad = np.zeros(
                (self.chunk_size - len(chunk), self.actions.shape[1]),
                dtype=np.float32,
            )
            chunk = np.concatenate([chunk, pad], axis=0)

        # Normalise state/action
        if self.state_mean is not None:
            state = (state - self.state_mean) / (self.state_std + 1e-8)
        if self.action_mean is not None:
            chunk = (chunk - self.action_mean) / (self.action_std + 1e-8)

        # Image → tensor (float32, 0-1 range, then per-channel normalisation)
        if self.transform is not None:
            image = self.transform(PILImage.fromarray(image))
        else:
            image = torch.from_numpy(image).permute(2, 0, 1).float() / 255.0

        return {
            "state": torch.from_numpy(state).float(),
            "image": image,
            "action_chunk": torch.from_numpy(chunk).float(),
        }


# -----------------------------------------------------------------------
# Config loading
# -----------------------------------------------------------------------

def load_config(path: str | Path) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


# -----------------------------------------------------------------------
# Data loading pipeline
# -----------------------------------------------------------------------

def discover_bags(bag_dir: Path) -> list[Path]:
    """Find all rosbag directories (containing metadata.yaml) under bag_dir."""
    bags = []
    for meta in sorted(bag_dir.rglob("metadata.yaml")):
        bags.append(meta.parent)
    if not bags:
        logger.warning("No rosbag directories found in %s", bag_dir)
    else:
        logger.info("Found %d bag(s) in %s", len(bags), bag_dir)
    return bags


def load_all_bags(cfg: dict) -> tuple[np.ndarray, list[np.ndarray]]:
    """Load and synchronise all rosbags from the configured directory.

    Returns combined states (N, 6) and images list.
    """
    data_cfg = cfg["data"]
    conv_cfg = cfg["conventions"]
    bag_dir = Path(data_cfg["bag_dir"])
    if not bag_dir.is_absolute():
        bag_dir = (Path(__file__).parent / bag_dir).resolve()

    bags = discover_bags(bag_dir)
    if not bags:
        raise FileNotFoundError(f"No rosbags found in {bag_dir}")

    all_states: list[np.ndarray] = []
    all_images: list[np.ndarray] = []

    for bag_path in bags:
        joints, images = extract_bag(
            bag_path,
            joint_topic=data_cfg["joint_topic"],
            image_topic=data_cfg["camera_topic"],
            ros_distro=data_cfg["ros_distro"],
        )
        if not joints or not images:
            logger.warning("Skipping empty bag: %s", bag_path)
            continue

        states, sync_imgs = synchronise(
            joints, images,
            fps=data_cfg["fps"],
            max_offset_ms=data_cfg["max_offset_ms"],
        )
        if len(states) < 2:
            continue

        # Convention conversion
        sign = conv_cfg["joint_sign"] if conv_cfg["apply_joint_sign"] else None
        states = apply_conventions(states, sign, conv_cfg["wrap_angles"])

        # Image resize
        target_hw = tuple(conv_cfg["image_resize"])
        if sync_imgs and (sync_imgs[0].shape[0], sync_imgs[0].shape[1]) != target_hw:
            sync_imgs = resize_images(sync_imgs, target_hw)

        all_states.append(states)
        all_images.extend(sync_imgs)

    if not all_states:
        raise RuntimeError("No valid data extracted from any rosbag")

    combined = np.concatenate(all_states, axis=0)
    logger.info("Total dataset: %d frames", len(combined))
    return combined, all_images


# -----------------------------------------------------------------------
# Checkpoint saving
# -----------------------------------------------------------------------

def save_checkpoint(
    model: ACTModel,
    output_dir: Path,
    step: int,
    cfg: dict,
    state_mean: np.ndarray,
    state_std: np.ndarray,
    action_mean: np.ndarray,
    action_std: np.ndarray,
    image_mean: np.ndarray,
    image_std: np.ndarray,
) -> None:
    """Save model checkpoint with normalisation stats.

    Creates:
        config.json                                          — model config
        model.safetensors                                    — model weights
        policy_preprocessor_step_3_normalizer_processor.safetensors  — input norm stats
        policy_postprocessor_step_0_unnormalizer_processor.safetensors — output denorm stats
        train_config.json                                    — full training config snapshot
    """
    ckpt_dir = output_dir / f"checkpoint_{step:06d}" / "pretrained_model"
    ckpt_dir.mkdir(parents=True, exist_ok=True)

    # Model weights
    state_dict = {k: v.contiguous() for k, v in model.state_dict().items()}
    save_file(state_dict, str(ckpt_dir / "model.safetensors"))

    # Model config (matches existing config.json format)
    model_cfg = cfg["model"]
    config = {
        "type": "act",
        "n_obs_steps": 1,
        "input_features": {
            "observation.state": {"type": "STATE", "shape": [model_cfg["state_dim"]]},
            "observation.images.color": {
                "type": "VISUAL",
                "shape": [3] + list(cfg["conventions"]["image_resize"]),
            },
        },
        "output_features": {
            "action": {"type": "ACTION", "shape": [model_cfg["action_dim"]]},
        },
        "device": cfg["training"]["device"],
        "use_amp": False,
        "chunk_size": model_cfg["chunk_size"],
        "n_action_steps": model_cfg["chunk_size"],
        "normalization_mapping": {
            "VISUAL": "MEAN_STD",
            "STATE": "MEAN_STD",
            "ACTION": "MEAN_STD",
        },
        "vision_backbone": model_cfg["vision_backbone"],
        "pretrained_backbone_weights": "ResNet18_Weights.IMAGENET1K_V1",
        "replace_final_stride_with_dilation": False,
        "pre_norm": False,
        "dim_model": model_cfg["dim_model"],
        "n_heads": model_cfg["n_heads"],
        "dim_feedforward": model_cfg["dim_feedforward"],
        "feedforward_activation": "relu",
        "n_encoder_layers": model_cfg["n_encoder_layers"],
        "n_decoder_layers": model_cfg["n_decoder_layers"],
        "use_vae": model_cfg["use_vae"],
        "latent_dim": model_cfg["latent_dim"],
        "n_vae_encoder_layers": model_cfg["n_vae_encoder_layers"],
        "temporal_ensemble_coeff": None,
        "dropout": model_cfg["dropout"],
        "kl_weight": cfg["training"]["kl_weight"],
        "optimizer_lr": cfg["training"]["lr"],
        "optimizer_weight_decay": cfg["training"]["weight_decay"],
        "optimizer_lr_backbone": cfg["training"]["lr_backbone"],
    }
    with open(ckpt_dir / "config.json", "w") as f:
        json.dump(config, f, indent=4)

    # Normalisation stats — preprocessor (observation normalisation)
    pre_stats = {
        "observation.state.mean": torch.from_numpy(state_mean).float(),
        "observation.state.std": torch.from_numpy(state_std).float(),
        "observation.images.color.mean": torch.from_numpy(image_mean).float(),
        "observation.images.color.std": torch.from_numpy(image_std).float(),
        "action.mean": torch.from_numpy(action_mean).float(),
        "action.std": torch.from_numpy(action_std).float(),
    }
    save_file(pre_stats, str(ckpt_dir / "policy_preprocessor_step_3_normalizer_processor.safetensors"))

    # Postprocessor (action denormalisation)
    post_stats = {
        "action.mean": torch.from_numpy(action_mean).float(),
        "action.std": torch.from_numpy(action_std).float(),
    }
    save_file(post_stats, str(ckpt_dir / "policy_postprocessor_step_0_unnormalizer_processor.safetensors"))

    # Preprocessor / postprocessor JSON metadata
    pre_json = {
        "name": "policy_preprocessor",
        "steps": [
            {"registry_name": "normalizer_processor", "config": {
                "eps": 1e-8,
                "features": config["input_features"] | config["output_features"],
                "norm_map": config["normalization_mapping"],
            }},
        ],
    }
    post_json = {
        "name": "policy_postprocessor",
        "steps": [
            {"registry_name": "unnormalizer_processor", "config": {
                "eps": 1e-8,
                "features": config["output_features"],
                "norm_map": {"ACTION": "MEAN_STD"},
            }},
        ],
    }
    with open(ckpt_dir / "policy_preprocessor.json", "w") as f:
        json.dump(pre_json, f, indent=2)
    with open(ckpt_dir / "policy_postprocessor.json", "w") as f:
        json.dump(post_json, f, indent=2)

    # Training config snapshot
    with open(ckpt_dir / "train_config.json", "w") as f:
        json.dump(cfg, f, indent=4)

    logger.info("Checkpoint saved → %s", ckpt_dir)


# -----------------------------------------------------------------------
# Training loop
# -----------------------------------------------------------------------

def train(cfg: dict) -> None:
    tcfg = cfg["training"]
    mcfg = cfg["model"]

    # --- Distributed setup ---
    ddp = _is_ddp()
    rank = _ddp_rank()
    local_rank = _ddp_local_rank()
    world_size = _ddp_world_size()
    is_main = rank == 0

    if ddp:
        _ddp_init()
        device = torch.device(f"cuda:{local_rank}")
    else:
        device = torch.device(tcfg["device"] if torch.cuda.is_available() else "cpu")

    torch.manual_seed(tcfg["seed"] + rank)
    np.random.seed(tcfg["seed"] + rank)

    if is_main:
        logger.info("Device: %s (DDP=%s, world_size=%d)", device, ddp, world_size)

    # --- Load data ---
    if is_main:
        logger.info("Loading rosbag data...")
    states, images = load_all_bags(cfg)

    # --- Compute normalisation statistics ---
    if is_main:
        logger.info("Computing normalisation statistics...")
    state_mean = states.mean(axis=0).astype(np.float32)
    state_std = states.std(axis=0).astype(np.float32)
    state_std = np.maximum(state_std, 1e-6)

    # Action deltas
    actions = np.diff(states, axis=0).astype(np.float32)
    action_mean = actions.mean(axis=0)
    action_std = actions.std(axis=0)
    action_std = np.maximum(action_std, 1e-6)

    # Image stats (per-channel mean/std over entire dataset)
    img_stack = np.stack(images).astype(np.float32) / 255.0  # (N, H, W, 3)
    image_mean = img_stack.mean(axis=(0, 1, 2)).astype(np.float32)  # (3,)
    image_std = img_stack.std(axis=(0, 1, 2)).astype(np.float32)    # (3,)
    image_std = np.maximum(image_std, 1e-6)
    del img_stack  # Free memory

    if is_main:
        logger.info("State mean: %s", state_mean)
        logger.info("State std:  %s", state_std)
        logger.info("Action mean: %s", action_mean)
        logger.info("Action std:  %s", action_std)
        logger.info("Image mean: %s", image_mean)
        logger.info("Image std:  %s", image_std)

    # Image transform: to tensor then channel-wise normalisation
    img_transform = transforms.Compose([
        transforms.ToTensor(),  # (H,W,3) uint8 → (3,H,W) float [0,1]
        transforms.Normalize(mean=image_mean.tolist(), std=image_std.tolist()),
    ])

    # --- Dataset + DataLoader ---
    dataset = RosbagACTDataset(
        states=states,
        images=images,
        chunk_size=mcfg["chunk_size"],
        image_transform=img_transform,
        state_mean=state_mean,
        state_std=state_std,
        action_mean=action_mean,
        action_std=action_std,
    )
    if is_main:
        logger.info("Dataset size: %d samples (chunk_size=%d)", len(dataset), mcfg["chunk_size"])

    sampler = DistributedSampler(dataset, num_replicas=world_size, rank=rank) if ddp else None

    loader = DataLoader(
        dataset,
        batch_size=tcfg["batch_size"],
        shuffle=(sampler is None),
        sampler=sampler,
        num_workers=tcfg["num_workers"],
        pin_memory=True,
        drop_last=True,
        persistent_workers=tcfg["num_workers"] > 0,
    )

    # --- Model ---
    model = ACTModel(
        state_dim=mcfg["state_dim"],
        action_dim=mcfg["action_dim"],
        chunk_size=mcfg["chunk_size"],
        dim_model=mcfg["dim_model"],
        n_heads=mcfg["n_heads"],
        dim_feedforward=mcfg["dim_feedforward"],
        n_encoder_layers=mcfg["n_encoder_layers"],
        n_decoder_layers=mcfg["n_decoder_layers"],
        n_vae_encoder_layers=mcfg["n_vae_encoder_layers"],
        latent_dim=mcfg["latent_dim"],
        dropout=mcfg["dropout"],
        use_vae=mcfg["use_vae"],
        vision_backbone=mcfg["vision_backbone"],
        pretrained_backbone=mcfg["pretrained_backbone"],
    ).to(device)

    if ddp:
        model = DDP(model, device_ids=[local_rank], output_device=local_rank)

    raw_model = model.module if ddp else model
    n_params = sum(p.numel() for p in raw_model.parameters())
    if is_main:
        logger.info("Model: %.2fM parameters", n_params / 1e6)

    # --- Optimiser ---
    backbone_params = list(raw_model.backbone.parameters())
    backbone_ids = {id(p) for p in backbone_params}
    other_params = [p for p in model.parameters() if id(p) not in backbone_ids]

    optimizer = torch.optim.AdamW(
        [
            {"params": other_params, "lr": tcfg["lr"]},
            {"params": backbone_params, "lr": tcfg["lr_backbone"]},
        ],
        weight_decay=tcfg["weight_decay"],
        betas=(0.9, 0.999),
        eps=1e-8,
    )

    # --- LR Scheduler ---
    scheduler = _build_scheduler(optimizer, tcfg)

    # --- Wandb ---
    use_wandb = _wandb_enabled(cfg) and is_main
    if use_wandb:
        _init_wandb(cfg)

    # --- Output dir ---
    output_dir = Path(tcfg["output_dir"])
    if not output_dir.is_absolute():
        output_dir = (Path(__file__).parent / output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    # --- Training loop ---
    if is_main:
        logger.info("Starting training for %d steps...", tcfg["steps"])
    model.train()
    step = 0
    epoch = 0
    total_steps = tcfg["steps"]
    running_loss = 0.0
    running_l1 = 0.0
    running_kl = 0.0
    t_start = time.monotonic()

    while step < total_steps:
        epoch += 1
        if sampler is not None:
            sampler.set_epoch(epoch)
        for batch in loader:
            if step >= total_steps:
                break

            state = batch["state"].to(device)
            image = batch["image"].to(device)
            action_chunk = batch["action_chunk"].to(device)

            pred, vae_params = model(state, image, actions=action_chunk)
            mu, logvar = vae_params if vae_params is not None else (None, None)

            loss, l1, kl = ACTModel.compute_loss(
                pred, action_chunk, mu, logvar,
                kl_weight=tcfg["kl_weight"],
            )

            optimizer.zero_grad()
            loss.backward()
            if tcfg["grad_clip_norm"] > 0:
                nn.utils.clip_grad_norm_(model.parameters(), tcfg["grad_clip_norm"])
            optimizer.step()

            if scheduler is not None:
                scheduler.step()

            step += 1
            running_loss += loss.item()
            running_l1 += l1.item()
            running_kl += kl.item()

            # Logging (rank 0 only)
            if step % tcfg["log_freq"] == 0 and is_main:
                avg_loss = running_loss / tcfg["log_freq"]
                avg_l1 = running_l1 / tcfg["log_freq"]
                avg_kl = running_kl / tcfg["log_freq"]
                current_lr = optimizer.param_groups[0]["lr"]
                elapsed = time.monotonic() - t_start
                steps_per_s = step / elapsed
                eta = (total_steps - step) / max(steps_per_s, 0.01)
                logger.info(
                    "step %5d/%d | loss %.4f | l1 %.4f | kl %.4f | "
                    "lr %.2e | %.1f steps/s | ETA %s",
                    step, total_steps, avg_loss, avg_l1, avg_kl,
                    current_lr, steps_per_s,
                    time.strftime("%H:%M:%S", time.gmtime(eta)),
                )
                if use_wandb:
                    _log_wandb({
                        "loss": avg_loss,
                        "l1_loss": avg_l1,
                        "kl_loss": avg_kl,
                        "lr": current_lr,
                        "epoch": epoch,
                    }, step=step)
                running_loss = running_l1 = running_kl = 0.0

            # Save checkpoint (rank 0 only)
            if (step % tcfg["save_freq"] == 0 or step == total_steps) and is_main:
                save_checkpoint(
                    raw_model, output_dir, step, cfg,
                    state_mean, state_std,
                    action_mean, action_std,
                    image_mean, image_std,
                )

    elapsed = time.monotonic() - t_start
    if is_main:
        logger.info("Training complete — %d steps in %s", total_steps,
                    time.strftime("%H:%M:%S", time.gmtime(elapsed)))
        logger.info("Final checkpoint: %s", output_dir)

    if use_wandb:
        _finish_wandb()

    if ddp:
        _ddp_cleanup()


# -----------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Train ACT from rosbag data")
    parser.add_argument(
        "--config", type=str, default="config.yaml",
        help="Path to training config YAML",
    )
    parser.add_argument(
        "--override", type=str, action="append", default=[],
        help="Override config values: key=value (dot-notation, e.g. training.lr=5e-5)",
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = (Path(__file__).parent / config_path).resolve()

    if not config_path.exists():
        logger.error("Config not found: %s", config_path)
        sys.exit(1)

    cfg = load_config(config_path)

    # Apply CLI overrides
    for override in args.override:
        key, _, value = override.partition("=")
        if not value:
            logger.error("Invalid override (expected key=value): %s", override)
            sys.exit(1)
        parts = key.split(".")
        target = cfg
        for part in parts[:-1]:
            target = target.setdefault(part, {})
        # Auto-convert numeric and boolean values
        if value.lower() in ("true", "false"):
            value = value.lower() == "true"
        else:
            try:
                value = int(value)
            except ValueError:
                try:
                    value = float(value)
                except ValueError:
                    pass
        target[parts[-1]] = value
        logger.info("Override: %s = %s", key, value)

    logger.info("Config loaded from %s", config_path)

    train(cfg)


if __name__ == "__main__":
    main()
