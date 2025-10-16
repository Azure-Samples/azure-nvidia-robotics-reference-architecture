"""SKRL training loop instrumented with Azure MLflow."""

from __future__ import annotations

import argparse
import logging
import os
import random
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, Sequence

try:
    from packaging.version import parse as parse_version
except ImportError:
    parse_version = None

from training.utils import AzureMLContext

_LOGGER = logging.getLogger("isaaclab.skrl")
_SKRL_MIN_VERSION = "1.4.3"
_METRIC_INTERVAL = 10


def _build_parser(app_launcher_cls) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Train IsaacLab SKRL policies")
    parser.add_argument("--task", type=str, default=None, help="IsaacLab task identifier")
    parser.add_argument("--agent", type=str, default=None, help="Override agent configuration entry point")
    parser.add_argument(
        "--algorithm",
        type=str,
        default="PPO",
        choices=["AMP", "PPO", "IPPO", "MAPPO"],
        help="RL algorithm",
    )
    parser.add_argument(
        "--ml_framework",
        type=str,
        default="torch",
        choices=["torch", "jax", "jax-numpy"],
        help="Numerical backend",
    )
    parser.add_argument("--num_envs", type=int, default=None, help="Override number of vectorized environments")
    parser.add_argument("--max_iterations", type=int, default=None, help="Maximum training iterations")
    parser.add_argument("--seed", type=int, default=None, help="Random seed")
    parser.add_argument("--distributed", action="store_true", help="Enable distributed execution")
    parser.add_argument("--checkpoint", type=str, default=None, help="Resume checkpoint path")
    parser.add_argument("--export_io_descriptors", action="store_true", help="Dump IO descriptors")
    parser.add_argument("--video", action="store_true", help="Record rollout videos")
    parser.add_argument("--video_length", type=int, default=200, help="Video duration in steps")
    parser.add_argument("--video_interval", type=int, default=2000, help="Video capture interval")
    app_launcher_cls.add_app_launcher_args(parser)
    return parser


def _agent_entry(args_cli: argparse.Namespace) -> str:
    if args_cli.agent:
        return args_cli.agent
    algorithm = (args_cli.algorithm or "").lower()
    if algorithm == "ppo":
        return "skrl_cfg_entry_point"
    if algorithm in {"ippo", "mappo", "amp"}:
        return f"skrl_{algorithm}_cfg_entry_point"
    return "skrl_cfg_entry_point"


def _ensure_skrl_version(skrl_module) -> None:
    if parse_version is None:
        _LOGGER.warning("packaging module unavailable; skipping skrl version enforcement")
        return

    if parse_version(skrl_module.__version__) < parse_version(_SKRL_MIN_VERSION):
        raise SystemExit(
            f"skrl {skrl_module.__version__} detected; version >= {_SKRL_MIN_VERSION} is required"
        )


def _prepare_log_paths(agent_cfg: Dict, args_cli: argparse.Namespace) -> Path:
    experiment_cfg = agent_cfg.setdefault("agent", {}).setdefault("experiment", {})
    root_path = Path(experiment_cfg.get("directory") or Path("logs") / "skrl").resolve()
    timestamp = datetime.utcnow().strftime("%Y-%m-%d_%H-%M-%S")
    algorithm_label = (args_cli.algorithm or "rl").lower()
    run_name = f"{timestamp}_{algorithm_label}_{args_cli.ml_framework}"
    custom_name = experiment_cfg.get("experiment_name")
    if custom_name:
        run_name = f"{run_name}_{custom_name}"
    experiment_cfg["directory"] = str(root_path)
    experiment_cfg["experiment_name"] = run_name
    log_dir = root_path / run_name
    log_dir.mkdir(parents=True, exist_ok=True)
    return log_dir


def _maybe_wrap_video(gym_module, env, args_cli: argparse.Namespace, log_dir: Path):
    if not args_cli.video:
        return env
    video_dir = log_dir / "videos" / "train"
    video_dir.mkdir(parents=True, exist_ok=True)
    video_kwargs = {
        "video_folder": str(video_dir),
        "step_trigger": lambda step: step % args_cli.video_interval == 0,
        "video_length": args_cli.video_length,
        "disable_logger": True,
    }
    _LOGGER.info("Recording training videos to %s", video_dir)
    return gym_module.wrappers.RecordVideo(env, **video_kwargs)


def _build_metric_callback(mlflow_module):
    def _callback(step: int, info: Dict[str, float]) -> None:
        if step % _METRIC_INTERVAL != 0:
            return
        metrics = {}

        for key in ("episode_reward_mean", "success_rate", "episode_length_mean"):
            value = info.get(key)
            if value is not None:
                metrics[key] = float(value)

        for key in ("timesteps_total", "iterations_total", "fps"):
            value = info.get(key)
            if value is not None:
                metrics[key] = float(value)

        for key in ("policy_loss", "value_loss", "entropy", "learning_rate"):
            value = info.get(key)
            if value is not None:
                metrics[key] = float(value)

        for stat_key in ("episode_reward", "episode_length"):
            for suffix in ("_min", "_max", "_std"):
                key = f"{stat_key}{suffix}"
                value = info.get(key)
                if value is not None:
                    metrics[key] = float(value)

        try:
            import torch
            if torch.cuda.is_available():
                device = torch.cuda.current_device()
                metrics["gpu_memory_allocated"] = float(torch.cuda.memory_allocated(device)) / (1024**3)
                try:
                    metrics["gpu_utilization"] = float(torch.cuda.utilization(device))
                except (AttributeError, RuntimeError):
                    pass
        except ImportError:
            pass

        if metrics:
            mlflow_module.log_metrics(metrics, step=step)

    return _callback


def _log_artifacts(mlflow_module, log_dir: Path, resume_path: Optional[str]) -> Optional[str]:
    params_dir = log_dir / "params"
    for rel_path in ("env.yaml", "agent.yaml", "env.pkl", "agent.pkl"):
        candidate = params_dir / rel_path
        if candidate.exists():
            mlflow_module.log_artifact(str(candidate), artifact_path="skrl-run")
    if resume_path:
        mlflow_module.log_artifact(resume_path, artifact_path="skrl-run/checkpoints")
    checkpoint_dir = log_dir / "checkpoints"
    active_run = mlflow_module.active_run()
    latest_uri: Optional[str] = None
    if checkpoint_dir.exists() and checkpoint_dir.is_dir():
        mlflow_module.log_artifacts(str(checkpoint_dir), artifact_path="skrl-run/checkpoints")
        latest_file: Optional[Path] = None
        for candidate in checkpoint_dir.rglob("*"):
            if candidate.is_file():
                if latest_file is None or candidate.stat().st_mtime > latest_file.stat().st_mtime:
                    latest_file = candidate
        if active_run and latest_file:
            run_id = active_run.info.run_id
            relative_path = latest_file.relative_to(checkpoint_dir)
            directory_uri = f"runs:/{run_id}/skrl-run/checkpoints"
            latest_uri = f"{directory_uri}/{relative_path.as_posix()}"
            mlflow_module.set_tag("checkpoint_directory", directory_uri)
            mlflow_module.set_tag("checkpoint_latest", latest_uri)
            token = f"::checkpoint_uri::{latest_uri}"
            mlflow_module.set_tag("checkpoint_log_token", token)
            _LOGGER.info("Latest SKRL checkpoint stored at %s", latest_uri)
            print(token)
    videos_dir = log_dir / "videos"
    if videos_dir.exists():
        mlflow_module.log_artifacts(str(videos_dir), artifact_path="videos")
    return latest_uri


def _register_checkpoint_model(
    *,
    context: Optional[AzureMLContext],
    model_name: str,
    checkpoint_uri: str,
    checkpoint_mode: Optional[str],
    task: Optional[str],
) -> None:
    if context is None:
        _LOGGER.warning("Azure ML context unavailable; skipping checkpoint registration for %s", model_name)
        return
    try:
        from azure.ai.ml.entities import Model
    except ImportError as exc:  # pragma: no cover - dependency guard
        _LOGGER.error("Azure ML SDK missing; cannot register checkpoint %s: %s", model_name, exc)
        return

    tags = {
        "checkpoint_mode": checkpoint_mode or "from-scratch",
    }
    if task:
        tags["task"] = task

    try:
        model = Model(
            name=model_name,
            path=checkpoint_uri,
            type="custom_model",
            description="IsaacLab SKRL checkpoint artifact",
            tags=tags,
        )
        context.client.models.create_or_update(model)
        _LOGGER.info("Registered SKRL checkpoint %s as Azure ML model %s", checkpoint_uri, model_name)
    except Exception as exc:  # pragma: no cover - AzureML errors are environment-dependent
        _LOGGER.error("Failed to register checkpoint %s as Azure ML model %s: %s", checkpoint_uri, model_name, exc)


def _resolve_env_count(env_cfg) -> Optional[int]:
    scene = getattr(env_cfg, "scene", None)
    if scene and hasattr(scene, "env") and hasattr(scene.env, "num_envs"):
        return scene.env.num_envs
    return getattr(env_cfg, "num_envs", None)


def _resolve_checkpoint(retrieve_file_path, checkpoint: Optional[str]) -> Optional[str]:
    if not checkpoint:
        return None
    try:
        return retrieve_file_path(checkpoint)
    except FileNotFoundError as exc:
        raise SystemExit(f"Checkpoint path not found: {checkpoint}") from exc


def _namespace_to_tokens(args: argparse.Namespace) -> Sequence[str]:
    tokens = []
    if getattr(args, "task", None):
        tokens.extend(["--task", str(args.task)])
    if getattr(args, "num_envs", None) is not None:
        tokens.extend(["--num_envs", str(args.num_envs)])
    if getattr(args, "max_iterations", None) is not None:
        tokens.extend(["--max_iterations", str(args.max_iterations)])
    if getattr(args, "headless", False):
        tokens.append("--headless")
    if getattr(args, "checkpoint", None):
        tokens.extend(["--checkpoint", str(args.checkpoint)])
    return tokens


def _namespace_payload(namespace: argparse.Namespace) -> Dict[str, object]:
    payload: Dict[str, object] = {}
    for key, value in vars(namespace).items():
        if isinstance(value, (str, int, float, bool)) or value is None:
            payload[key] = value
        else:
            payload[key] = str(value)
    return payload


def run_training(
    *,
    args: argparse.Namespace,
    hydra_args: Sequence[str],
    context: Optional[AzureMLContext],
) -> None:
    try:
        from isaaclab.app import AppLauncher
    except ImportError as exc:
        raise SystemExit("IsaacLab packages are required for SKRL training") from exc

    parser = _build_parser(AppLauncher)
    tokens = list(_namespace_to_tokens(args)) + list(hydra_args)
    args_cli, leftover = parser.parse_known_args(tokens)

    if getattr(args_cli, "video", False):
        setattr(args_cli, "enable_cameras", True)

    parse_report = {
        "parsed": _namespace_payload(args_cli),
        "hydra_overrides": list(leftover),
        "launcher_hydra_args": list(hydra_args),
    }
    _LOGGER.info("SKRL runner arguments: %s", parse_report)

    sys.argv = [sys.argv[0]] + leftover
    app_launcher = AppLauncher(args_cli)
    simulation_app = app_launcher.app

    kit_log_dir = getattr(getattr(simulation_app, "config", None), "log_dir", None)
    if kit_log_dir:
        _LOGGER.info("Kit logs located at %s", kit_log_dir)

    try:
        import isaaclab_tasks  # noqa: F401
        from isaaclab_tasks.utils.hydra import hydra_task_config
        import gymnasium as gym_module
        import skrl as skrl_module
        _ensure_skrl_version(skrl_module)
        _LOGGER.info("Detected skrl version: %s", getattr(skrl_module, "__version__", "unknown"))

        from isaaclab.envs import (
            DirectMARLEnv,
            DirectMARLEnvCfg,
            DirectRLEnvCfg,
            ManagerBasedRLEnvCfg,
            multi_agent_to_single_agent,
        )
        from isaaclab.utils.assets import retrieve_file_path
        from isaaclab.utils.dict import print_dict
        from isaaclab.utils.io import dump_yaml
        try:
            from isaaclab.utils.io import dump_pickle
        except ImportError:
            dump_pickle = None
        from isaaclab_rl.skrl import SkrlVecEnvWrapper

        if args_cli.ml_framework.startswith("torch"):
            from skrl.utils.runner.torch import Runner
        else:
            from skrl.utils.runner.jax import Runner

        mlflow_module = None
        if context:
            import mlflow as mlflow_module
        agent_entry = _agent_entry(args_cli)

        @hydra_task_config(args_cli.task, agent_entry)
        def _launch(env_cfg, agent_cfg):
            random_seed = args_cli.seed if args_cli.seed is not None else random.randint(1, 1_000_000)
            random.seed(random_seed)
            os.environ.setdefault("PYTHONHASHSEED", str(random_seed))
            os.environ.setdefault("HYDRA_FULL_ERROR", "1")

            if isinstance(env_cfg, ManagerBasedRLEnvCfg):
                env_cfg.scene.num_envs = args_cli.num_envs or env_cfg.scene.num_envs
            elif isinstance(env_cfg, DirectRLEnvCfg):
                env_cfg.num_envs = args_cli.num_envs or env_cfg.num_envs
            elif isinstance(env_cfg, DirectMARLEnvCfg):
                env_cfg.num_envs = args_cli.num_envs or env_cfg.num_envs

            env_dict = env_cfg.to_dict()
            agent_dict = agent_cfg.to_dict()

            print_dict(env_dict)
            print_dict(agent_dict)

            log_dir = _prepare_log_paths(agent_cfg, args_cli)
            params_dir = log_dir / "params"
            params_dir.mkdir(parents=True, exist_ok=True)
            dump_yaml(str(params_dir / "env.yaml"), env_cfg)
            dump_yaml(str(params_dir / "agent.yaml"), agent_cfg)
            if dump_pickle:
                dump_pickle(str(params_dir / "env.pkl"), env_cfg)
                dump_pickle(str(params_dir / "agent.pkl"), agent_cfg)

            resume_path = _resolve_checkpoint(retrieve_file_path, args_cli.checkpoint)
            if isinstance(env_cfg, ManagerBasedRLEnvCfg) and args_cli.export_io_descriptors:
                env_cfg.export_io_descriptors = True
                env_cfg.io_descriptors_output_dir = str(log_dir)

            env_count = _resolve_env_count(env_cfg)
            trainer_cfg = agent_dict.get("agent", {}).get("trainer", {})
            config_snapshot = {
                "algorithm": args_cli.algorithm,
                "ml_framework": args_cli.ml_framework,
                "num_envs": env_count,
                "max_iterations": args_cli.max_iterations,
                "distributed": args_cli.distributed,
                "trainer": trainer_cfg,
            }
            _LOGGER.info("SKRL training configuration: %s", config_snapshot)

            env = gym_module.make(
                args_cli.task,
                cfg=env_cfg,
                render_mode="rgb_array" if args_cli.video else None,
            )

            if isinstance(env.unwrapped, DirectMARLEnv) and args_cli.algorithm.lower() == "ppo":
                env = multi_agent_to_single_agent(env)

            env = _maybe_wrap_video(gym_module, env, args_cli, log_dir)
            env = SkrlVecEnvWrapper(env, ml_framework=args_cli.ml_framework)

            runner = Runner(env, agent_cfg)
            if resume_path and hasattr(runner, "agent"):
                runner.agent.load(resume_path)

            outcome = "success"
            run_started = False
            if mlflow_module:
                mlflow_module.autolog(log_models=False)
                mlflow_module.start_run(run_name=log_dir.name)
                run_started = True
                env_count = _resolve_env_count(env_cfg)
                mlflow_module.log_params(
                    {
                        "algorithm": args_cli.algorithm,
                        "ml_framework": args_cli.ml_framework,
                        "num_envs": env_count,
                        "distributed": args_cli.distributed,
                        "resume_checkpoint": bool(resume_path),
                        "seed": random_seed,
                    }
                )
                if resume_path:
                    mlflow_module.set_tag("checkpoint_resume", resume_path)
                mlflow_module.set_tag("log_dir", str(log_dir))
                mlflow_module.set_tag("task", args_cli.task or "")
                mlflow_module.set_tag("entrypoint", "training/scripts/train.py")
                if context:
                    mlflow_module.set_tag("azureml_workspace", context.workspace_name)
                checkpoint_mode = getattr(args, "checkpoint_mode", None)
                if checkpoint_mode:
                    mlflow_module.set_tag("checkpoint_mode", checkpoint_mode)
                if getattr(args, "checkpoint_uri", None):
                    mlflow_module.set_tag("checkpoint_source_uri", args.checkpoint_uri)
                if hasattr(runner, "register_callback"):
                    runner.register_callback("on_episode_end", _build_metric_callback(mlflow_module))

            runner_start = time.perf_counter()
            run_descriptor = {
                "algorithm": args_cli.algorithm,
                "ml_framework": args_cli.ml_framework,
                "log_dir": str(log_dir),
                "resume_checkpoint": bool(resume_path),
                "resume_path": resume_path,
            }
            _LOGGER.info("SKRL runner starting: %s", run_descriptor)

            try:
                runner.run()
            except Exception:
                outcome = "failed"
                failure_payload = dict(run_descriptor)
                failure_payload["elapsed_seconds"] = round(time.perf_counter() - runner_start, 2)
                _LOGGER.exception("SKRL runner failed: %s", failure_payload)
                raise
            else:
                success_payload = dict(run_descriptor)
                success_payload["elapsed_seconds"] = round(time.perf_counter() - runner_start, 2)
                if mlflow_module and run_started:
                    active_run = mlflow_module.active_run()
                    if active_run:
                        success_payload["mlflow_run_id"] = active_run.info.run_id
                _LOGGER.info("SKRL runner completed: %s", success_payload)
            finally:
                env.close()
                if mlflow_module and run_started:
                    mlflow_module.set_tag("training_outcome", outcome)
                    latest_checkpoint_uri = _log_artifacts(mlflow_module, log_dir, resume_path)
                    register_name = getattr(args, "register_checkpoint", None)
                    if register_name and latest_checkpoint_uri:
                        _register_checkpoint_model(
                            context=context,
                            model_name=register_name,
                            checkpoint_uri=latest_checkpoint_uri,
                            checkpoint_mode=getattr(args, "checkpoint_mode", None),
                            task=args_cli.task,
                        )
                    mlflow_module.end_run()

        _launch()
    except ImportError as exc:  # pragma: no cover - dependency diagnostics
        raise SystemExit("Required IsaacLab dependencies are missing for SKRL training") from exc
    finally:
        simulation_app.close()
