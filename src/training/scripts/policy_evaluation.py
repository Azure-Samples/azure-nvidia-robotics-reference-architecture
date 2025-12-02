"""Generic IsaacLab policy evaluation.

Evaluates any trained IsaacLab policy with automatic task/framework detection.
Supports SKRL and RSL-RL frameworks with model metadata auto-detection.

Usage:
    python -m training.scripts.policy_evaluation \
        --model-path /mnt/azureml/model \
        --task Isaac-Velocity-Rough-Anymal-C-v0 \
        --framework skrl \
        --eval-episodes 100 \
        --headless

Exit Codes:
    0 - Validation passed (success_rate >= threshold)
    1 - Validation failed or error
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import torch

_LOGGER = logging.getLogger("isaaclab.eval")


# =============================================================================
# Metadata
# =============================================================================


@dataclass
class ModelMetadata:
    """Model metadata for validation configuration."""

    task: str = ""
    framework: str = "skrl"
    success_threshold: float = 0.7

    @classmethod
    def from_json(cls, path: Path) -> ModelMetadata:
        """Load metadata from model_metadata.json.

        Args:
            path: Path to model_metadata.json file

        Returns:
            ModelMetadata instance with loaded values or defaults
        """
        if not path.exists():
            return cls()
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return cls(
            task=data.get("tags", {}).get("task", ""),
            framework=data.get("tags", {}).get("framework", "skrl"),
            success_threshold=float(
                data.get("properties", {}).get("success_threshold", 0.7)
            ),
        )


def load_metadata(
    model_path: str, task: str = "", framework: str = ""
) -> ModelMetadata:
    """Load metadata with CLI overrides.

    Args:
        model_path: Path to model directory
        task: Optional task override from CLI
        framework: Optional framework override from CLI

    Returns:
        ModelMetadata with CLI overrides applied
    """
    meta = ModelMetadata.from_json(Path(model_path) / "model_metadata.json")
    if task:
        meta.task = task
    if framework:
        meta.framework = framework
    return meta


# =============================================================================
# Agent Loading
# =============================================================================


def load_agent(
    checkpoint_path: str,
    framework: str,
    task_id: str,
    observation_space: Any,
    action_space: Any,
    device: str = "cuda",
) -> Any:
    """Load agent based on framework.

    Args:
        checkpoint_path: Path to checkpoint file
        framework: Framework type (skrl, rsl_rl)
        task_id: IsaacLab task identifier
        observation_space: Environment observation space
        action_space: Environment action space
        device: Torch device string

    Returns:
        Loaded agent instance

    Raises:
        ValueError: If framework is not supported
    """
    _LOGGER.info("Loading %s agent from %s", framework, checkpoint_path)

    if framework == "skrl":
        return _load_skrl(checkpoint_path, task_id, observation_space, action_space, device)
    elif framework == "rsl_rl":
        return _load_rsl_rl(checkpoint_path, device)
    else:
        raise ValueError(f"Unsupported framework: {framework}")


def _load_skrl(
    checkpoint_path: str,
    task_id: str,
    obs_space: Any,
    act_space: Any,
    device: str,
) -> Any:
    """Load SKRL agent using task's skrl_cfg_entry_point."""
    from isaaclab_tasks.utils.hydra import hydra_task_config
    from skrl.agents.torch.ppo import PPO

    agent_cfg = None

    @hydra_task_config(task_id, "skrl_cfg_entry_point")
    def get_cfg(env_cfg: Any, cfg: Any) -> None:
        nonlocal agent_cfg
        agent_cfg = cfg

    get_cfg()

    agent = PPO(
        models={},
        memory=None,
        cfg=agent_cfg,
        observation_space=obs_space,
        action_space=act_space,
        device=torch.device(device),
    )
    agent.load(checkpoint_path)
    agent.set_running_mode("eval")
    return agent


def _load_rsl_rl(checkpoint_path: str, device: str) -> Any:
    """Load RSL-RL agent from checkpoint."""
    checkpoint = torch.load(checkpoint_path, map_location=device, weights_only=False)
    from rsl_rl.modules import ActorCritic

    policy = ActorCritic(**checkpoint.get("model_cfg", {}))
    policy.load_state_dict(checkpoint["model_state_dict"])
    policy.eval()
    return policy.to(device)


# =============================================================================
# Evaluation
# =============================================================================


@dataclass
class Metrics:
    """Episode metrics collector."""

    rewards: list[float] = field(default_factory=list)
    lengths: list[int] = field(default_factory=list)
    successes: int = 0

    def add(self, reward: float, length: int, success: bool) -> None:
        """Add metrics for a completed episode.

        Args:
            reward: Total episode reward
            length: Episode length in steps
            success: Whether episode was successful
        """
        self.rewards.append(reward)
        self.lengths.append(length)
        if success:
            self.successes += 1

    @property
    def count(self) -> int:
        """Return number of completed episodes."""
        return len(self.rewards)

    def to_dict(self) -> dict[str, Any]:
        """Convert metrics to dictionary for JSON serialization.

        Returns:
            Dictionary with aggregated metrics
        """
        if not self.rewards:
            return {"error": "No episodes completed"}
        return {
            "eval_episodes": self.count,
            "mean_reward": float(np.mean(self.rewards)),
            "std_reward": float(np.std(self.rewards)),
            "mean_length": float(np.mean(self.lengths)),
            "success_rate": self.successes / self.count,
        }


def evaluate(env: Any, agent: Any, num_episodes: int, framework: str) -> Metrics:
    """Run evaluation episodes and collect metrics.

    Args:
        env: IsaacLab environment
        agent: Loaded agent instance
        num_episodes: Number of episodes to evaluate
        framework: Framework type for action selection

    Returns:
        Metrics instance with evaluation results
    """
    metrics = Metrics()
    num_envs = env.num_envs
    ep_rewards = torch.zeros(num_envs, device=env.device)
    ep_lengths = torch.zeros(num_envs, dtype=torch.int32, device=env.device)

    obs, _ = env.reset()
    step = 0

    while metrics.count < num_episodes:
        with torch.inference_mode():
            if framework == "skrl":
                actions = agent.act(obs, timestep=step, timesteps=0)[0]
            else:  # rsl_rl
                actions = agent.act_inference(obs)

        obs, rewards, terminated, truncated, info = env.step(actions)
        ep_rewards += rewards.squeeze()
        ep_lengths += 1
        step += 1

        dones = (terminated | truncated).squeeze()
        for idx in torch.where(dones)[0]:
            if metrics.count >= num_episodes:
                break

            success = info.get("success", terminated)[idx].item()
            metrics.add(
                float(ep_rewards[idx]),
                int(ep_lengths[idx]),
                bool(success) and not truncated[idx].item(),
            )
            ep_rewards[idx] = 0
            ep_lengths[idx] = 0

            if metrics.count % 20 == 0:
                _LOGGER.info("Progress: %d/%d episodes", metrics.count, num_episodes)

    return metrics


# =============================================================================
# Main
# =============================================================================


def find_checkpoint(model_path: str) -> str:
    """Find checkpoint file in model directory.

    Args:
        model_path: Path to model directory

    Returns:
        Path to checkpoint file

    Raises:
        FileNotFoundError: If no checkpoint found
    """
    model_dir = Path(model_path)
    for pattern in ["best_agent.pt", "checkpoints/*.pt", "*.pt", "*.pth"]:
        matches = list(model_dir.glob(pattern))
        if matches:
            return str(max(matches, key=lambda p: p.stat().st_mtime))
    raise FileNotFoundError(f"No checkpoint found in {model_path}")


def _build_parser() -> argparse.ArgumentParser:
    """Build argument parser for policy evaluation."""
    parser = argparse.ArgumentParser(
        description="Generic IsaacLab policy evaluation",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--model-path",
        required=True,
        help="Path to mounted model directory",
    )
    parser.add_argument(
        "--task",
        default="",
        help="Override task ID (empty = use metadata)",
    )
    parser.add_argument(
        "--framework",
        default="",
        help="Override framework (empty = auto-detect)",
    )
    parser.add_argument(
        "--eval-episodes",
        type=int,
        default=100,
        help="Number of evaluation episodes",
    )
    parser.add_argument(
        "--num-envs",
        type=int,
        default=64,
        help="Number of parallel environments",
    )
    parser.add_argument(
        "--success-threshold",
        type=float,
        default=-1,
        help="Override threshold (negative = use metadata)",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run without rendering",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed",
    )
    return parser


def main() -> int:
    """Main entry point for policy evaluation.

    Returns:
        Exit code: 0 for success, 1 for failure
    """
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    args = _build_parser().parse_args()

    # Load metadata
    meta = load_metadata(args.model_path, args.task, args.framework)
    if not meta.task:
        _LOGGER.error("Task not specified and not found in metadata")
        return 1

    threshold = (
        args.success_threshold if args.success_threshold >= 0 else meta.success_threshold
    )
    _LOGGER.info(
        "Task: %s, Framework: %s, Threshold: %.2f",
        meta.task,
        meta.framework,
        threshold,
    )

    # Launch simulation
    from isaaclab.app import AppLauncher

    app = AppLauncher(
        argparse.Namespace(headless=args.headless, enable_cameras=False)
    )

    try:
        import gymnasium as gym

        from isaaclab_rl.skrl import SkrlVecEnvWrapper
        from isaaclab_tasks.utils.parse_cfg import parse_env_cfg

        import isaaclab_tasks  # noqa: F401 - Required for task registration

        # Create environment
        env_cfg = parse_env_cfg(
            meta.task, "cuda:0", args.num_envs, use_fabric=True
        )
        env_cfg.seed = args.seed
        env = gym.make(meta.task, cfg=env_cfg, render_mode=None)
        if meta.framework == "skrl":
            env = SkrlVecEnvWrapper(env, ml_framework="torch")

        # Load agent and evaluate
        checkpoint = find_checkpoint(args.model_path)
        agent = load_agent(
            checkpoint,
            meta.framework,
            meta.task,
            env.observation_space,
            env.action_space,
            "cuda",
        )
        metrics = evaluate(env, agent, args.eval_episodes, meta.framework)
        result = metrics.to_dict()

        # Output results
        print("\n" + "=" * 60)
        print(json.dumps(result, indent=2))
        print("=" * 60)

        success_rate = result.get("success_rate", 0)
        if success_rate >= threshold:
            print(f"\n✅ PASSED: {success_rate:.2f} >= {threshold}")
            return 0
        else:
            print(f"\n❌ FAILED: {success_rate:.2f} < {threshold}")
            return 1

    except Exception as e:
        _LOGGER.exception("Evaluation failed: %s", e)
        return 1
    finally:
        app.app.close()


if __name__ == "__main__":
    sys.exit(main())
