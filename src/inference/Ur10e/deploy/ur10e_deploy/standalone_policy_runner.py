"""Standalone ACT policy runner — loads checkpoint from rosbag-trained model.

Replaces the lerobot-based PolicyRunner when using checkpoints produced
by the standalone ``train/train.py`` script.  Uses the same interface
(load / predict / reset / buffer_size) so it can be swapped in
``main.py`` without other changes.
"""

from __future__ import annotations

import json
import logging
import sys
import time
from collections import deque
from pathlib import Path

import numpy as np
import torch
from safetensors import safe_open

# Add the train directory to sys.path so we can import ACTModel
_TRAIN_DIR = str((Path(__file__).resolve().parent.parent.parent / "train").resolve())
if _TRAIN_DIR not in sys.path:
    sys.path.insert(0, _TRAIN_DIR)

from act_model import ACTModel  # noqa: E402

logger = logging.getLogger(__name__)


def _wrap_to_pi(angles: np.ndarray) -> np.ndarray:
    """Wrap joint angles to (-π, π]."""
    return (angles + np.pi) % (2 * np.pi) - np.pi


class StandalonePolicyRunner:
    """Load and run the standalone ACT model from a rosbag-trained checkpoint.

    Compatible API with the lerobot-based PolicyRunner so it can be
    used as a drop-in replacement in ``main.py``.

    Parameters
    ----------
    config : PolicyConfig
        Must have ``checkpoint_dir``, ``device``, ``temporal_ensemble_coeff``,
        ``chunk_size``.
    """

    def __init__(self, config) -> None:
        self.cfg = config
        self._model: ACTModel | None = None
        self._action_queue: deque[np.ndarray] = deque()
        self._device = torch.device(config.device)
        self._loaded = False

        # Normalisation stats
        self._state_mean: np.ndarray | None = None
        self._state_std: np.ndarray | None = None
        self._action_mean: np.ndarray | None = None
        self._action_std: np.ndarray | None = None
        self._image_mean: np.ndarray | None = None
        self._image_std: np.ndarray | None = None

        # Temporal ensemble state
        self._ensemble_enabled = config.temporal_ensemble_coeff is not None
        self._ensemble_coeff = config.temporal_ensemble_coeff or 0.01
        self._all_actions: list[np.ndarray] = []
        self._ensemble_step: int = 0

        # Diagnostics
        self.last_norm_input: list[float] | None = None
        self.last_norm_output: list[float] | None = None

    # ------------------------------------------------------------------
    # Loading
    # ------------------------------------------------------------------

    def load(self) -> None:
        """Load the standalone ACT model from checkpoint directory.

        Expects:
            config.json
            model.safetensors
            policy_preprocessor_step_3_normalizer_processor.safetensors
            policy_postprocessor_step_0_unnormalizer_processor.safetensors
        """
        checkpoint_dir = Path(self.cfg.checkpoint_dir).resolve()
        if not checkpoint_dir.exists():
            raise FileNotFoundError(f"Checkpoint directory not found: {checkpoint_dir}")

        logger.info("Loading standalone ACT model from %s ...", checkpoint_dir)

        # Load model config
        config_file = checkpoint_dir / "config.json"
        if not config_file.exists():
            raise FileNotFoundError(f"config.json not found in {checkpoint_dir}")
        with open(config_file) as f:
            model_cfg = json.load(f)

        # Determine dimensions from config
        state_dim = model_cfg["input_features"]["observation.state"]["shape"][0]
        action_dim = model_cfg["output_features"]["action"]["shape"][0]

        # Build model
        self._model = ACTModel(
            state_dim=state_dim,
            action_dim=action_dim,
            chunk_size=model_cfg.get("chunk_size", 100),
            dim_model=model_cfg.get("dim_model", 512),
            n_heads=model_cfg.get("n_heads", 8),
            dim_feedforward=model_cfg.get("dim_feedforward", 3200),
            n_encoder_layers=model_cfg.get("n_encoder_layers", 4),
            n_decoder_layers=model_cfg.get("n_decoder_layers", 1),
            n_vae_encoder_layers=model_cfg.get("n_vae_encoder_layers", 4),
            latent_dim=model_cfg.get("latent_dim", 32),
            dropout=model_cfg.get("dropout", 0.1),
            use_vae=model_cfg.get("use_vae", True),
            vision_backbone=model_cfg.get("vision_backbone", "resnet18"),
            pretrained_backbone=False,  # We're loading trained weights
        )

        # Load weights from safetensors
        weights_file = checkpoint_dir / "model.safetensors"
        if not weights_file.exists():
            raise FileNotFoundError(f"model.safetensors not found in {checkpoint_dir}")

        state_dict = {}
        with safe_open(str(weights_file), framework="pt") as f:
            for key in f.keys():
                state_dict[key] = f.get_tensor(key)

        self._model.load_state_dict(state_dict)
        self._model.to(self._device)
        self._model.eval()

        # Load normalisation stats
        self._load_norm_stats(checkpoint_dir)

        self._loaded = True
        n_params = sum(p.numel() for p in self._model.parameters())
        logger.info("Model loaded — %.2fM parameters on %s", n_params / 1e6, self._device)

    def _load_norm_stats(self, checkpoint_dir: Path) -> None:
        """Load normalisation statistics from preprocessor/postprocessor files."""
        pre_file = checkpoint_dir / "policy_preprocessor_step_3_normalizer_processor.safetensors"
        post_file = checkpoint_dir / "policy_postprocessor_step_0_unnormalizer_processor.safetensors"

        if pre_file.exists():
            with safe_open(str(pre_file), framework="pt") as f:
                for key in f.keys():
                    tensor = f.get_tensor(key).cpu().numpy().flatten()
                    if key == "observation.state.mean":
                        self._state_mean = tensor
                    elif key == "observation.state.std":
                        self._state_std = tensor
                    elif key == "observation.images.color.mean":
                        self._image_mean = tensor
                    elif key == "observation.images.color.std":
                        self._image_std = tensor
                    elif key == "action.mean":
                        self._action_mean = tensor
                    elif key == "action.std":
                        self._action_std = tensor
            logger.info("Preprocessor stats loaded from %s", pre_file.name)

        if post_file.exists():
            with safe_open(str(post_file), framework="pt") as f:
                for key in f.keys():
                    tensor = f.get_tensor(key).cpu().numpy().flatten()
                    if key == "action.mean":
                        self._action_mean = tensor
                    elif key == "action.std":
                        self._action_std = tensor
            logger.info("Postprocessor stats loaded from %s", post_file.name)

        if self._state_mean is not None:
            logger.info("State mean: %s", self._state_mean)
            logger.info("State std:  %s", self._state_std)
        if self._action_mean is not None:
            logger.info("Action mean: %s", self._action_mean)
            logger.info("Action std:  %s", self._action_std)
        if self._image_mean is not None:
            logger.info("Image mean: %s", self._image_mean)
            logger.info("Image std:  %s", self._image_std)

    @property
    def loaded(self) -> bool:
        return self._loaded

    # ------------------------------------------------------------------
    # Inference
    # ------------------------------------------------------------------

    def reset(self) -> None:
        """Clear the action buffer and ensemble state (call at episode start)."""
        self._action_queue.clear()
        self._all_actions = []
        self._ensemble_step = 0
        self.last_norm_input = None
        self.last_norm_output = None
        logger.debug("Policy state reset")

    @torch.inference_mode()
    def predict(
        self,
        joint_positions: np.ndarray,
        image: np.ndarray,
    ) -> np.ndarray:
        """Predict the next action given current observation.

        Parameters
        ----------
        joint_positions : np.ndarray
            Current joint positions, shape (6,) in radians (training convention).
        image : np.ndarray
            Current camera image, shape (H, W, 3) uint8 RGB.

        Returns
        -------
        np.ndarray
            Action delta vector, shape (6,).
        """
        if not self._loaded or self._model is None:
            raise RuntimeError("Model not loaded — call load() first")

        if self._ensemble_enabled:
            return self._predict_ensemble(joint_positions, image)

        if self._action_queue:
            return self._action_queue.popleft()

        state, img_tensor = self._build_observation(joint_positions, image)

        t0 = time.monotonic()
        pred_actions, _ = self._model(state, img_tensor, actions=None)
        dt = time.monotonic() - t0
        logger.debug("Forward pass: %.1f ms", dt * 1000)

        # pred_actions: (1, chunk_size, action_dim)
        action_np = pred_actions[0].cpu().numpy()  # (chunk_size, action_dim)

        # Denormalise actions
        action_np = self._denorm_actions(action_np)

        # Queue remaining actions, return first
        for i in range(1, len(action_np)):
            self._action_queue.append(action_np[i])
        return action_np[0]

    def _predict_ensemble(
        self,
        joint_positions: np.ndarray,
        image: np.ndarray,
    ) -> np.ndarray:
        """Temporal ensemble prediction (ACT paper)."""
        state, img_tensor = self._build_observation(joint_positions, image)

        # Capture normalised input for diagnostics
        self._capture_norm_diagnostics(joint_positions)

        t0 = time.monotonic()
        pred_actions, _ = self._model(state, img_tensor, actions=None)
        dt = time.monotonic() - t0
        logger.debug("Forward pass: %.1f ms", dt * 1000)

        action_np = pred_actions[0].cpu().numpy()  # (chunk_size, action_dim)
        action_np = self._denorm_actions(action_np)

        self._all_actions.append(action_np)

        # Compute weighted average for current timestep
        coeff = self._ensemble_coeff
        weighted_sum = np.zeros(action_np.shape[-1])
        weight_total = 0.0

        for chunk_idx, chunk in enumerate(self._all_actions):
            future_idx = self._ensemble_step - chunk_idx
            if 0 <= future_idx < len(chunk):
                age = self._ensemble_step - chunk_idx
                w = np.exp(-coeff * age)
                weighted_sum += w * chunk[future_idx]
                weight_total += w

        self._ensemble_step += 1

        # Prune old chunks
        while len(self._all_actions) > 1:
            oldest_last_step = 0 + len(self._all_actions[0]) - 1
            if self._ensemble_step > oldest_last_step:
                self._all_actions.pop(0)
            else:
                break

        if weight_total > 0:
            return weighted_sum / weight_total
        return action_np[0]

    def _denorm_actions(self, actions: np.ndarray) -> np.ndarray:
        """Denormalise action predictions back to original scale."""
        if self._action_mean is not None and self._action_std is not None:
            return actions * self._action_std + self._action_mean
        return actions

    def _build_observation(
        self,
        joint_positions: np.ndarray,
        image: np.ndarray,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        """Convert raw observation to model inputs.

        Returns normalised state tensor and image tensor.
        """
        # Wrap to training range
        wrapped = _wrap_to_pi(joint_positions)

        # Normalise state
        state = wrapped.astype(np.float32)
        if self._state_mean is not None:
            state = (state - self._state_mean) / (self._state_std + 1e-8)
        state_tensor = torch.from_numpy(state).float().unsqueeze(0).to(self._device)

        # Image: (H, W, 3) uint8 → (1, 3, H, W) float, normalised
        img = image.astype(np.float32) / 255.0
        if self._image_mean is not None:
            img = (img - self._image_mean) / (self._image_std + 1e-8)
        img_tensor = torch.from_numpy(img).permute(2, 0, 1).unsqueeze(0).float().to(self._device)

        return state_tensor, img_tensor

    def _capture_norm_diagnostics(self, joint_positions: np.ndarray) -> None:
        """Capture normalised input state for dashboard diagnostics."""
        try:
            wrapped = _wrap_to_pi(joint_positions)
            if self._state_mean is not None:
                normalized = (wrapped - self._state_mean) / (self._state_std + 1e-8)
                self.last_norm_input = normalized.tolist()
        except Exception:
            pass

    @property
    def buffer_size(self) -> int:
        """Number of actions remaining in the chunk buffer."""
        return len(self._action_queue)
