"""Minimal SKRL training test for diagnostics.

Exercises the core training path without MLflow, checkpoints, or Azure
integration: AppLauncher, gym.make, Runner.run, env.close.
"""

from __future__ import annotations

import argparse
import os
import time

# AppLauncher must be created before any other Isaac imports

parser = argparse.ArgumentParser(description="Minimal SKRL training test")
parser.add_argument("--task", type=str, default="Isaac-Velocity-Rough-Anymal-C-v0")
parser.add_argument("--num_envs", type=int, default=16)
parser.add_argument("--max_iterations", type=int, default=5)

from isaaclab.app import AppLauncher

AppLauncher.add_app_launcher_args(parser)
args, hydra_args = parser.parse_known_args()
args.headless = True

# Hydra re-parses sys.argv; remove flags it does not recognize
import sys

sys.argv = [sys.argv[0]] + list(hydra_args)

app_launcher = AppLauncher(args)
simulation_app = app_launcher.app

# Post-AppLauncher imports

import gymnasium as gym
from isaaclab.envs import DirectRLEnvCfg, ManagerBasedRLEnvCfg
from isaaclab_rl.skrl import SkrlVecEnvWrapper
from skrl.utils.runner.torch import Runner

import isaaclab_tasks  # noqa: F401
from isaaclab_tasks.utils.hydra import hydra_task_config

from training.simulation_shutdown import prepare_for_shutdown
from training.stream import install_ansi_stripping


def main() -> None:
    install_ansi_stripping()
    wall_start = time.perf_counter()

    print(f"task={args.task}  num_envs={args.num_envs}  max_iterations={args.max_iterations}", flush=True)

    @hydra_task_config(args.task, "skrl_cfg_entry_point")
    def _train(env_cfg, agent_cfg):
        if isinstance(env_cfg, ManagerBasedRLEnvCfg):
            env_cfg.scene.num_envs = args.num_envs
        elif isinstance(env_cfg, DirectRLEnvCfg):
            env_cfg.num_envs = args.num_envs

        env = gym.make(args.task, cfg=env_cfg)
        env = SkrlVecEnvWrapper(env, ml_framework="torch")
        print(f"Environment created: obs={env.observation_space.shape}, act={env.action_space.shape}", flush=True)

        agent_dict = agent_cfg.to_dict() if hasattr(agent_cfg, "to_dict") else agent_cfg
        trainer_cfg = agent_dict.setdefault("trainer", {})
        rollouts = agent_dict.get("agent", {}).get("rollouts", 1)
        trainer_cfg["timesteps"] = args.max_iterations * rollouts
        trainer_cfg["close_environment_at_exit"] = False
        trainer_cfg["disable_progressbar"] = False

        print(
            f"Training: {args.max_iterations} iterations x {rollouts} rollouts = {trainer_cfg['timesteps']} timesteps",
            flush=True,
        )

        runner = Runner(env, agent_dict)
        t0 = time.perf_counter()
        runner.run()
        print(f"Training completed in {time.perf_counter() - t0:.1f}s", flush=True)

        prepare_for_shutdown()
        env.close()

    _train()

    print(f"Total wall time: {time.perf_counter() - wall_start:.1f}s", flush=True)
    os._exit(0)


if __name__ == "__main__":
    main()
