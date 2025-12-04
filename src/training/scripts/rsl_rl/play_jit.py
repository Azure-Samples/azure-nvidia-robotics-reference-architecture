"""Script to play an exported JIT (TorchScript) policy in Isaac Sim environment.

This script runs inference using a JIT-exported policy model against the same
simulation environment used for training, enabling validation of the exported
model before Azure ML deployment.
"""

"""Launch Isaac Sim Simulator first."""

import argparse
import sys

from isaaclab.app import AppLauncher

# local imports
import cli_args  # isort: skip

parser = argparse.ArgumentParser(description="Run inference using an exported JIT policy.")
parser.add_argument("--video", action="store_true", default=False, help="Record videos during inference.")
parser.add_argument(
    "--video_length",
    type=int,
    default=200,
    help="Length of the recorded video (in steps).",
)
parser.add_argument(
    "--disable_fabric",
    action="store_true",
    default=False,
    help="Disable fabric and use USD I/O operations.",
)
parser.add_argument("--num_envs", type=int, default=None, help="Number of environments to simulate.")
parser.add_argument("--task", type=str, default=None, help="Name of the task.")
parser.add_argument(
    "--agent",
    type=str,
    default="rsl_rl_cfg_entry_point",
    help="Name of the RL agent configuration entry point.",
)
parser.add_argument("--seed", type=int, default=None, help="Seed used for the environment")
parser.add_argument(
    "--jit-model",
    type=str,
    required=True,
    help="Path to the exported JIT policy model (.pt).",
)
parser.add_argument(
    "--real-time",
    action="store_true",
    default=False,
    help="Run in real-time, if possible.",
)
parser.add_argument(
    "--max-steps",
    type=int,
    default=1000,
    help="Maximum number of simulation steps (0 for unlimited).",
)

cli_args.add_rsl_rl_args(parser)
AppLauncher.add_app_launcher_args(parser)
args_cli, hydra_args = parser.parse_known_args()

if args_cli.video:
    args_cli.enable_cameras = True

sys.argv = [sys.argv[0]] + hydra_args

app_launcher = AppLauncher(args_cli)
simulation_app = app_launcher.app

"""Rest everything follows."""

import gymnasium as gym
import numpy as np
import os
import time

import torch

from isaaclab.envs import (
    DirectMARLEnv,
    DirectMARLEnvCfg,
    DirectRLEnvCfg,
    ManagerBasedRLEnvCfg,
    multi_agent_to_single_agent,
)
from isaaclab.utils.dict import print_dict

from isaaclab_rl.rsl_rl import RslRlBaseRunnerCfg, RslRlVecEnvWrapper

import isaaclab_tasks  # noqa: F401
from isaaclab_tasks.utils.hydra import hydra_task_config


class JitPolicy:
    """Wrapper for JIT (TorchScript) policy inference compatible with IsaacLab environments."""

    def __init__(self, jit_path: str, device: str = "cpu"):
        """Initialize JIT model.

        Args:
            jit_path: Path to the JIT model file (.pt).
            device: Target device for inference.
        """
        self.device = device

        print(f"[INFO] Loading JIT model from: {jit_path}")
        self.model = torch.jit.load(jit_path, map_location=device)
        self.model.eval()
        print(f"[INFO] JIT model loaded on device: {device}")

    def __call__(self, obs: torch.Tensor) -> torch.Tensor:
        """Run inference on observations.

        Args:
            obs: Observation tensor of shape (num_envs, obs_dim), dict, or TensorDict with 'policy' key.

        Returns:
            Action tensor of shape (num_envs, action_dim).
        """
        # Handle TensorDict or dict observations from RslRlVecEnvWrapper
        if hasattr(obs, "__getitem__") and not isinstance(obs, torch.Tensor):
            obs = obs["policy"]
        with torch.inference_mode():
            return self.model(obs.to(self.device))


@hydra_task_config(args_cli.task, args_cli.agent)
def main(
    env_cfg: ManagerBasedRLEnvCfg | DirectRLEnvCfg | DirectMARLEnvCfg,
    agent_cfg: RslRlBaseRunnerCfg,
):
    """Play with JIT policy in Isaac Sim environment."""
    agent_cfg: RslRlBaseRunnerCfg = cli_args.update_rsl_rl_cfg(agent_cfg, args_cli)
    env_cfg.scene.num_envs = args_cli.num_envs if args_cli.num_envs is not None else env_cfg.scene.num_envs

    env_cfg.seed = agent_cfg.seed
    env_cfg.sim.device = args_cli.device if args_cli.device is not None else env_cfg.sim.device

    jit_path = os.path.abspath(args_cli.jit_model)
    if not os.path.exists(jit_path):
        raise FileNotFoundError(f"JIT model not found: {jit_path}")

    log_dir = os.path.dirname(jit_path)
    env_cfg.log_dir = log_dir

    env = gym.make(args_cli.task, cfg=env_cfg, render_mode="rgb_array" if args_cli.video else None)

    if isinstance(env.unwrapped, DirectMARLEnv):
        env = multi_agent_to_single_agent(env)

    if args_cli.video:
        video_kwargs = {
            "video_folder": os.path.join(log_dir, "videos", "jit_play"),
            "step_trigger": lambda step: step == 0,
            "video_length": args_cli.video_length,
            "disable_logger": True,
        }
        print("[INFO] Recording videos during JIT inference.")
        print_dict(video_kwargs, nesting=4)
        env = gym.wrappers.RecordVideo(env, **video_kwargs)

    env = RslRlVecEnvWrapper(env, clip_actions=agent_cfg.clip_actions)

    policy = JitPolicy(jit_path, device=env.unwrapped.device)

    dt = env.unwrapped.step_dt

    obs = env.get_observations()
    timestep = 0
    total_reward = 0.0
    episode_rewards = []
    current_episode_reward = torch.zeros(env_cfg.scene.num_envs, device=env.unwrapped.device)

    inference_times = []

    print(f"\n[INFO] Starting JIT policy inference...")
    print(f"[INFO] Num envs: {env_cfg.scene.num_envs}")
    print(f"[INFO] Max steps: {args_cli.max_steps if args_cli.max_steps > 0 else 'unlimited'}")
    print("-" * 60)

    while simulation_app.is_running():
        start_time = time.time()

        inf_start = time.perf_counter()
        actions = policy(obs)
        inf_time = (time.perf_counter() - inf_start) * 1000
        inference_times.append(inf_time)

        obs, rewards, dones, _ = env.step(actions)

        current_episode_reward += rewards
        done_envs = dones.nonzero(as_tuple=False).squeeze(-1)
        if len(done_envs) > 0:
            for idx in done_envs:
                episode_rewards.append(current_episode_reward[idx].item())
            current_episode_reward[done_envs] = 0.0

        total_reward += rewards.sum().item()
        timestep += 1

        if timestep % 100 == 0:
            avg_inf_time = np.mean(inference_times[-100:])
            print(
                f"Step {timestep}: "
                f"avg_reward={total_reward / (timestep * env_cfg.scene.num_envs):.4f}, "
                f"episodes={len(episode_rewards)}, "
                f"inf_time={avg_inf_time:.2f}ms"
            )

        if args_cli.video and timestep == args_cli.video_length:
            break

        if args_cli.max_steps > 0 and timestep >= args_cli.max_steps:
            break

        sleep_time = dt - (time.time() - start_time)
        if args_cli.real_time and sleep_time > 0:
            time.sleep(sleep_time)

    print("-" * 60)
    print(f"\n[RESULTS] JIT Policy Inference Summary")
    print(f"  Total steps: {timestep}")
    print(f"  Total episodes completed: {len(episode_rewards)}")
    if episode_rewards:
        print(f"  Mean episode reward: {np.mean(episode_rewards):.4f}")
        print(f"  Std episode reward: {np.std(episode_rewards):.4f}")
    print(f"  Mean inference time: {np.mean(inference_times):.2f}ms")
    print(f"  Max inference time: {np.max(inference_times):.2f}ms")
    print(f"  Min inference time: {np.min(inference_times):.2f}ms")

    env.close()


if __name__ == "__main__":
    main()
    simulation_app.close()
