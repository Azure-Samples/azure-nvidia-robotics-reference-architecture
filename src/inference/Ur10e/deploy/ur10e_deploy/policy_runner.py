"""ACT policy inference engine — loads checkpoint and runs forward pass.

Wraps LeRobot's ACTPolicy with pre/post-processing pipelines and
action chunk buffering for efficient 30 Hz deployment.
"""

from __future__ import annotations

import logging
import time
from collections import deque
from pathlib import Path

import numpy as np
import torch


def _wrap_to_pi(angles: np.ndarray) -> np.ndarray:
    """Wrap joint angles to (-π, π].

    UR RTDE reports cumulative joint angles that can exceed 2π.
    Training data is typically recorded within [-π, π], so feeding
    unwrapped values produces severe out-of-distribution inputs.
    """
    return (angles + np.pi) % (2 * np.pi) - np.pi

from .config import PolicyConfig

logger = logging.getLogger(__name__)


class PolicyRunner:
    """Load and run the ACT policy from a local checkpoint.

    Handles:
    - Model loading from safetensors checkpoint
    - Pre-processing (normalization) and post-processing (unnormalization)
    - Action chunk buffering — one forward pass produces ``chunk_size``
      actions; subsequent calls dequeue from the buffer until empty.
    - Temporal ensemble — when ``temporal_ensemble_coeff`` is set,
      overlapping action chunks are exponentially averaged for smoother
      motion (see ACT paper, Zhao et al.).

    Parameters
    ----------
    config : PolicyConfig
        Checkpoint path, device, action mode, chunk settings.
    """

    def __init__(self, config: PolicyConfig) -> None:
        self.cfg = config
        self._policy = None
        self._action_queue: deque[np.ndarray] = deque()
        self._device = torch.device(config.device)
        self._loaded = False

        # Temporal ensemble state
        self._ensemble_enabled = config.temporal_ensemble_coeff is not None
        self._ensemble_coeff = config.temporal_ensemble_coeff or 0.01
        self._all_actions: list[np.ndarray] | None = None  # (num_chunks, chunk_size, action_dim)
        self._ensemble_step: int = 0

        # Diagnostics — normalized input/output for dashboard
        self.last_norm_input: list[float] | None = None
        self.last_norm_output: list[float] | None = None

    # ------------------------------------------------------------------
    # Loading
    # ------------------------------------------------------------------

    def load(self) -> None:
        """Load the ACT policy and pre/post processors from checkpoint.

        Uses a Windows-compatible workaround for draccus temp-file
        locking issues in ``PreTrainedConfig.from_pretrained``.
        """
        import json
        import os
        import tempfile

        import draccus
        from lerobot.configs.policies import PreTrainedConfig
        from lerobot.policies.act.modeling_act import ACTPolicy

        checkpoint_dir = Path(self.cfg.checkpoint_dir).resolve()
        if not checkpoint_dir.exists():
            raise FileNotFoundError(
                f"Checkpoint directory not found: {checkpoint_dir}"
            )
        logger.info("Loading ACT policy from %s ...", checkpoint_dir)

        # --- Load config (Windows-safe) ---
        # PreTrainedConfig.from_pretrained uses NamedTemporaryFile which
        # causes PermissionError on Windows.  Parse the config manually.
        config_file = str(checkpoint_dir / "config.json")

        with open(config_file) as f:
            raw_config = json.load(f)

        # Resolve the concrete config subclass from the "type" discriminator
        # without going through draccus (which rejects unknown fields).
        import dataclasses

        config_type_name = raw_config.get("type")
        if config_type_name is None:
            raise ValueError("config.json missing 'type' field")

        # Map policy type name → concrete config class
        _CONFIG_CLASSES = {
            "act": "lerobot.policies.act.configuration_act.ACTConfig",
            "diffusion": "lerobot.policies.diffusion.configuration_diffusion.DiffusionConfig",
            "tdmpc": "lerobot.policies.tdmpc.configuration_tdmpc.TDMPCConfig",
            "vqbet": "lerobot.policies.vqbet.configuration_vqbet.VQBeTConfig",
        }

        import importlib
        module_path = _CONFIG_CLASSES.get(config_type_name)
        if module_path is None:
            raise ValueError(f"Unknown policy type: {config_type_name}")
        mod_name, cls_name = module_path.rsplit(".", 1)
        concrete_cls = getattr(importlib.import_module(mod_name), cls_name)

        # Strip "type" discriminator and any fields not in the concrete class
        raw_config.pop("type", None)
        valid_fields = {fld.name for fld in dataclasses.fields(concrete_cls)}
        unknown = set(raw_config.keys()) - valid_fields
        for key in unknown:
            logger.warning("Stripping unknown config field: %s", key)
            raw_config.pop(key)

        tmp_path = os.path.join(tempfile.gettempdir(), "_lerobot_cfg.json")
        with open(tmp_path, "w") as f:
            json.dump(raw_config, f)
        try:
            with draccus.config_type("json"):
                policy_cfg = draccus.parse(concrete_cls, tmp_path, args=[])
        finally:
            try:
                os.remove(tmp_path)
            except OSError:
                pass

        # Load policy with pre-parsed config (bypasses the buggy path)
        self._policy = ACTPolicy.from_pretrained(
            str(checkpoint_dir), config=policy_cfg
        )

        # --- Load normalization stats from preprocessor/postprocessor ---
        # model.safetensors doesn't include these; they're in separate files.
        self._load_norm_stats(checkpoint_dir)

        self._policy.to(self._device)
        self._policy.eval()
        self._loaded = True

        # Log model summary
        n_params = sum(p.numel() for p in self._policy.parameters())
        logger.info(
            "Policy loaded — %.1fM parameters on %s",
            n_params / 1e6,
            self._device,
        )

    def _load_norm_stats(self, checkpoint_dir: Path) -> None:
        """Load normalization statistics from preprocessor/postprocessor safetensors.

        The checkpoint stores mean/std stats in separate files rather
        than in model.safetensors.  This method reads them and writes
        them into the policy's normalize/unnormalize ParameterDicts.
        """
        import torch
        from safetensors import safe_open

        pre_file = checkpoint_dir / "policy_preprocessor_step_3_normalizer_processor.safetensors"
        post_file = checkpoint_dir / "policy_postprocessor_step_0_unnormalizer_processor.safetensors"

        def _read_stats(stats_file: Path) -> dict[str, torch.Tensor]:
            """Read all tensors from a safetensors file."""
            if not stats_file.exists():
                logger.warning("Stats file not found: %s", stats_file)
                return {}
            result = {}
            with safe_open(str(stats_file), framework="pt") as f:
                for key in f.keys():
                    result[key] = f.get_tensor(key)
            return result

        def _inject_into_module(module, stats: dict[str, torch.Tensor], label: str) -> None:
            """Inject stats into a Normalize/Unnormalize module.

            The module has ParameterDict children like:
              buffer_observation_state → ParameterDict(mean=..., std=...)
            Stats keys are like: observation.state.mean
            """
            for raw_key, tensor in stats.items():
                # raw_key = "observation.state.mean"
                parts = raw_key.rsplit(".", 1)  # ["observation.state", "mean"]
                if len(parts) != 2:
                    continue
                feature_key, stat_name = parts
                if stat_name not in ("mean", "std"):
                    continue  # skip min/max — only mean_std used
                # Attribute name: "buffer_" + feature_key with dots → underscores
                buf_attr = "buffer_" + feature_key.replace(".", "_")
                if hasattr(module, buf_attr):
                    param_dict = getattr(module, buf_attr)
                    if stat_name in param_dict:
                        param_dict[stat_name].data.copy_(tensor)
                        logger.debug("Loaded %s.%s.%s", label, buf_attr, stat_name)

        stats = _read_stats(pre_file)
        if stats:
            _inject_into_module(self._policy.normalize_inputs, stats, "normalize_inputs")
            _inject_into_module(self._policy.normalize_targets, stats, "normalize_targets")

        post_stats = _read_stats(post_file)
        if post_stats:
            _inject_into_module(self._policy.unnormalize_outputs, post_stats, "unnormalize_outputs")

        logger.info("Normalization stats loaded from preprocessor/postprocessor files")

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
        if self._policy is not None:
            self._policy.reset()
        logger.debug("Policy state reset")

    @torch.inference_mode()
    def predict(
        self,
        joint_positions: np.ndarray,
        image: np.ndarray,
    ) -> np.ndarray:
        """Predict the next action given current observation.

        When temporal ensemble is enabled, each forward pass produces a
        full chunk of future actions. Overlapping predictions from
        successive forward passes are combined via exponential weighting:
        ``w(k) = exp(-coeff * k)`` where k is the age of the chunk.
        This smooths chunk-boundary discontinuities.

        When ensemble is disabled, falls back to simple chunk buffering
        (return first action, queue the rest).

        Parameters
        ----------
        joint_positions : np.ndarray
            Current joint positions, shape ``(6,)`` in radians.
        image : np.ndarray
            Current camera image, shape ``(480, 848, 3)`` uint8 RGB.

        Returns
        -------
        np.ndarray
            Action vector, shape ``(6,)``. Depending on ``action_mode``
            this is either a delta or absolute joint target.
        """
        if not self._loaded or self._policy is None:
            raise RuntimeError("Policy not loaded — call load() first")

        # --- Temporal ensemble path ---
        if self._ensemble_enabled:
            return self._predict_ensemble(joint_positions, image)

        # --- Simple chunk-buffer path ---
        if self._action_queue:
            return self._action_queue.popleft()

        obs = self._build_observation(joint_positions, image)

        t0 = time.monotonic()
        action = self._policy.select_action(obs)
        dt = time.monotonic() - t0
        logger.debug("Forward pass: %.1f ms", dt * 1000)

        action_np = action.cpu().numpy()
        if action_np.ndim == 2:
            for i in range(1, len(action_np)):
                self._action_queue.append(action_np[i])
            return action_np[0]
        return action_np

    def _predict_ensemble(
        self,
        joint_positions: np.ndarray,
        image: np.ndarray,
    ) -> np.ndarray:
        """Temporal-ensemble prediction (ACT paper, Zhao et al.).

        Every step runs a forward pass producing a full action chunk.
        The action for the current timestep is the exponentially-weighted
        average of all chunks that predict this timestep.
        """
        obs = self._build_observation(joint_positions, image)

        t0 = time.monotonic()
        action = self._policy.select_action(obs)
        dt = time.monotonic() - t0
        logger.debug("Forward pass: %.1f ms", dt * 1000)

        # Capture normalization diagnostics
        self._capture_norm_diagnostics(joint_positions)

        action_np = action.cpu().numpy()
        if action_np.ndim == 1:
            action_np = action_np.reshape(1, -1)  # (1, action_dim)

        # Store this chunk (each chunk[j] predicts timestep = ensemble_step + j)
        self._all_actions.append(action_np)

        # Compute weighted average for the current timestep
        coeff = self._ensemble_coeff
        weighted_sum = np.zeros(action_np.shape[-1])
        weight_total = 0.0

        for chunk_idx, chunk in enumerate(self._all_actions):
            # chunk was produced at step chunk_idx
            # For current step (ensemble_step), the relevant index is:
            future_idx = self._ensemble_step - chunk_idx
            if 0 <= future_idx < len(chunk):
                age = self._ensemble_step - chunk_idx
                w = np.exp(-coeff * age)
                weighted_sum += w * chunk[future_idx]
                weight_total += w

        self._ensemble_step += 1

        # Prune old chunks that no longer contribute
        max_keep = action_np.shape[0]
        while (
            len(self._all_actions) > 1
            and self._ensemble_step - 0 >= len(self._all_actions[0])
        ):
            # The oldest chunk's last timestep has passed
            oldest_last_step = 0 + len(self._all_actions[0]) - 1
            if self._ensemble_step > oldest_last_step:
                self._all_actions.pop(0)
            else:
                break

        if weight_total > 0:
            return weighted_sum / weight_total
        return action_np[0]

    def _capture_norm_diagnostics(self, joint_positions: np.ndarray) -> None:
        """Capture normalized input state for diagnostics.

        Reads the mean/std from normalize_inputs to compute what the
        policy sees after normalization.  Uses wrapped angles to match
        what ``_build_observation`` feeds to the model.
        """
        try:
            wrapped = _wrap_to_pi(joint_positions)
            norm_mod = self._policy.normalize_inputs
            if hasattr(norm_mod, "buffer_observation_state"):
                pd = norm_mod.buffer_observation_state
                if "mean" in pd and "std" in pd:
                    mean = pd["mean"].detach().cpu().numpy().flatten()
                    std = pd["std"].detach().cpu().numpy().flatten()
                    std = np.where(std < 1e-8, 1.0, std)
                    normalized = (wrapped - mean) / std
                    self.last_norm_input = normalized.tolist()
        except Exception:
            pass  # diagnostics are best-effort

    def _build_observation(
        self,
        joint_positions: np.ndarray,
        image: np.ndarray,
    ) -> dict[str, torch.Tensor]:
        """Convert raw observation arrays to the policy input dict.

        Joint positions are wrapped to (-π, π] so that the normalized
        z-scores stay within the training distribution.
        """
        # Wrap RTDE angles to the range the policy was trained on
        wrapped = _wrap_to_pi(joint_positions)

        # State: (6,) → (1, 6) batch dim
        state = torch.from_numpy(wrapped).float().unsqueeze(0).to(self._device)

        # Image: (H, W, 3) uint8 → (1, 3, H, W) float [0, 1]
        img_tensor = torch.from_numpy(image).float().permute(2, 0, 1) / 255.0
        img_tensor = img_tensor.unsqueeze(0).to(self._device)

        return {
            "observation.state": state,
            "observation.images.color": img_tensor,
        }

    # ------------------------------------------------------------------
    # Diagnostics
    # ------------------------------------------------------------------

    @property
    def buffer_size(self) -> int:
        """Number of actions remaining in the chunk buffer."""
        return len(self._action_queue)
