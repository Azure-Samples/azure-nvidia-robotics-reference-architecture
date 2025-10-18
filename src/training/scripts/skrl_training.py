"""SKRL training orchestration with IsaacLab environments and Azure MLflow integration.

This module provides the main training loop for reinforcement learning agents using
the SKRL library with IsaacLab simulation environments. It handles:
- Environment and agent configuration via Hydra
- Checkpoint loading and model registration
- MLflow metric logging and artifact tracking
- Video recording of training rollouts
- Integration with Azure ML workspaces
"""

from __future__ import annotations

import argparse
import logging
import random
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, NamedTuple, Optional, Sequence, Tuple

from training.scripts.skrl_mlflow_agent import create_mlflow_logging_wrapper
from training.utils import AzureMLContext, set_env_defaults

_LOGGER = logging.getLogger("isaaclab.skrl")

_DEFAULT_MLFLOW_INTERVAL = 10
_MLFLOW_INTERVAL_PRESETS = {
    "step": 1,
    "balanced": _DEFAULT_MLFLOW_INTERVAL,
}
_MLFLOW_ROLLOUT_PRESET = "rollout"

_AGENT_ENTRY_DEFAULT = "skrl_cfg_entry_point"
_AGENT_ENTRY_MAP = {
    "ippo": "skrl_ippo_cfg_entry_point",
    "mappo": "skrl_mappo_cfg_entry_point",
    "amp": "skrl_amp_cfg_entry_point",
}


def _parse_mlflow_log_interval(interval_arg: str, rollouts: int) -> int:
    """Parse mlflow_log_interval argument into integer interval.

    Args:
        interval_arg: CLI argument value (preset name or integer string)
        rollouts: Number of rollouts per iteration from agent config

    Returns:
        Integer interval for metric logging
    """
    interval_arg = interval_arg.strip().lower()
    if not interval_arg:
        return _DEFAULT_MLFLOW_INTERVAL

    preset_value = _MLFLOW_INTERVAL_PRESETS.get(interval_arg)
    if preset_value is not None:
        return preset_value

    if interval_arg == _MLFLOW_ROLLOUT_PRESET:
        return rollouts if rollouts > 0 else _DEFAULT_MLFLOW_INTERVAL
    try:
        interval = int(interval_arg)
        return max(1, interval)
    except ValueError:
        _LOGGER.warning(
            "Invalid mlflow_log_interval '%s', using default (%d)",
            interval_arg,
            _DEFAULT_MLFLOW_INTERVAL,
        )
        return _DEFAULT_MLFLOW_INTERVAL


def _build_parser(app_launcher_cls) -> argparse.ArgumentParser:
    """Build argument parser for SKRL training with IsaacLab launcher args."""
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
    parser.add_argument(
        "--mlflow_log_interval",
        type=str,
        default="balanced",
        help="MLflow metric logging interval: 'step' (every step), 'balanced' (every 10 steps), 'rollout' (per rollout), or integer",
    )
    app_launcher_cls.add_app_launcher_args(parser)
    return parser


def _agent_entry(args_cli: argparse.Namespace) -> str:
    """Resolve agent configuration entry point for selected algorithm."""
    if args_cli.agent:
        return args_cli.agent
    algorithm = (args_cli.algorithm or "").lower()
    return _AGENT_ENTRY_MAP.get(algorithm, _AGENT_ENTRY_DEFAULT)


def _prepare_log_paths(agent_cfg: Dict, args_cli: argparse.Namespace) -> Path:
    """Configure experiment metadata and create log directory for the run.

    Args:
        agent_cfg: Agent configuration dictionary to populate with experiment details.
        args_cli: Parsed CLI arguments that drive naming and algorithm metadata.

    Returns:
        Absolute path to the run-specific log directory.
    """
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
    """Wrap environment with video capture when video recording is enabled.

    Args:
        gym_module: Gymnasium module providing wrappers.
        env: Environment instance to optionally wrap.
        args_cli: Parsed CLI arguments containing video options.
        log_dir: Base directory for run artifacts.

    Returns:
        Environment wrapped with video recorder when requested; otherwise original env.
    """
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

def _log_artifacts(mlflow_module, log_dir: Path, resume_path: Optional[str]) -> Optional[str]:
    """Log training artifacts to MLflow and derive latest checkpoint URI.

    Args:
        mlflow_module: MLflow module used for logging operations.
        log_dir: Log directory containing artifacts to upload.
        resume_path: Path to the resumed checkpoint, if any.

    Returns:
        URI to the most recent checkpoint artifact, or None when unavailable.
    """
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
    """Register a checkpoint artifact as an Azure ML model when context is available.

    Args:
        context: Azure ML context responsible for model registration.
        model_name: Target Azure ML model name.
        checkpoint_uri: MLflow URI for the checkpoint artifact.
        checkpoint_mode: Checkpoint mode metadata tag.
        task: IsaacLab task identifier for tagging.
    """
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
    """Extract environment count from configuration object regardless of env type."""
    scene = getattr(env_cfg, "scene", None)
    if scene and hasattr(scene, "env") and hasattr(scene.env, "num_envs"):
        return scene.env.num_envs
    return getattr(env_cfg, "num_envs", None)


def _resolve_checkpoint(retrieve_file_path, checkpoint: Optional[str]) -> Optional[str]:
    """Resolve checkpoint location via IsaacLab asset resolver.

    Args:
        retrieve_file_path: Callable resolving checkpoint identifiers to absolute paths.
        checkpoint: User-specified checkpoint identifier or path.

    Returns:
        Resolved checkpoint path, or None when checkpoint not provided.

    Raises:
        SystemExit: If the checkpoint cannot be located.
    """
    if not checkpoint:
        return None
    try:
        return retrieve_file_path(checkpoint)
    except FileNotFoundError as exc:
        raise SystemExit(f"Checkpoint path not found: {checkpoint}") from exc


def _namespace_snapshot(namespace: argparse.Namespace) -> Tuple[Dict[str, object], Sequence[str]]:
    """Provide a serializable snapshot and CLI token list for a namespace."""

    payload: Dict[str, object] = {}
    for key, value in vars(namespace).items():
        if isinstance(value, (str, int, float, bool)) or value is None:
            payload[key] = value
        else:
            payload[key] = str(value)

    tokens: list[str] = []
    task = payload.get("task")
    if task:
        tokens.extend(["--task", str(task)])
    num_envs = payload.get("num_envs")
    if num_envs is not None:
        tokens.extend(["--num_envs", str(num_envs)])
    max_iterations = payload.get("max_iterations")
    if max_iterations is not None:
        tokens.extend(["--max_iterations", str(max_iterations)])
    if payload.get("headless"):
        tokens.append("--headless")
    checkpoint = payload.get("checkpoint")
    if checkpoint:
        tokens.extend(["--checkpoint", str(checkpoint)])

    return payload, tokens


def _normalize_agent_config(agent_cfg: Any) -> Dict[str, Any]:
    """Return agent configuration as a plain dictionary."""

    to_dict = getattr(agent_cfg, "to_dict", None)
    if callable(to_dict):
        return to_dict()
    return agent_cfg


def _configure_environment(
    env_cfg: Any,
    args_cli: argparse.Namespace,
    app_launcher,
    *,
    manager_cfg_type: Any,
    direct_cfg_type: Any,
    direct_mar_cfg_type: Any,
) -> int:
    """Update environment configuration with CLI overrides and return seed."""

    random_seed = args_cli.seed if args_cli.seed is not None else random.randint(1, 1_000_000)
    random.seed(random_seed)
    set_env_defaults({
        "PYTHONHASHSEED": str(random_seed),
        "HYDRA_FULL_ERROR": "1",
    })

    if isinstance(env_cfg, manager_cfg_type):
        env_cfg.scene.num_envs = args_cli.num_envs or env_cfg.scene.num_envs
    elif isinstance(env_cfg, direct_cfg_type):
        env_cfg.num_envs = args_cli.num_envs or env_cfg.num_envs
    elif isinstance(env_cfg, direct_mar_cfg_type):
        env_cfg.num_envs = args_cli.num_envs or env_cfg.num_envs

    if args_cli.distributed:
        env_cfg.sim.device = f"cuda:{app_launcher.local_rank}"

    env_cfg.seed = random_seed
    return random_seed


def _configure_agent_training(
    agent_dict: Dict[str, Any],
    args_cli: argparse.Namespace,
    random_seed: int,
) -> int:
    """Align agent training configuration with CLI overrides."""

    trainer_cfg = agent_dict.setdefault("trainer", {})
    agent_section = agent_dict.setdefault("agent", {})
    rollouts = agent_section.get("rollouts", 1)

    if args_cli.max_iterations:
        trainer_cfg["timesteps"] = args_cli.max_iterations * rollouts

    trainer_cfg["close_environment_at_exit"] = False
    agent_dict["seed"] = random_seed
    return rollouts


def _configure_jax_backend(ml_framework: str, skrl_module) -> None:
    """Select JAX backend when running with a JAX-based framework."""

    if not ml_framework.startswith("jax"):
        return
    skrl_module.config.jax.backend = "jax" if ml_framework == "jax" else "numpy"


def _dump_config_files(
    log_dir: Path,
    env_cfg: Any,
    agent_dict: Dict[str, Any],
    dump_yaml_func,
    dump_pickle_func,
) -> None:
    """Persist environment and agent configuration snapshots."""

    params_dir = log_dir / "params"
    params_dir.mkdir(parents=True, exist_ok=True)
    dump_yaml_func(str(params_dir / "env.yaml"), env_cfg)
    dump_yaml_func(str(params_dir / "agent.yaml"), agent_dict)
    if dump_pickle_func:
        dump_pickle_func(str(params_dir / "env.pkl"), env_cfg)
        dump_pickle_func(str(params_dir / "agent.pkl"), agent_dict)


def _log_configuration_snapshot(
    args_cli: argparse.Namespace,
    env_cfg: Any,
    agent_dict: Dict[str, Any],
    random_seed: int,
    rollouts: int,
) -> None:
    """Emit consolidated configuration details for the current run."""

    trainer_cfg = agent_dict.get("trainer", {})
    snapshot = {
        "algorithm": args_cli.algorithm,
        "ml_framework": args_cli.ml_framework,
        "num_envs": _resolve_env_count(env_cfg),
        "max_iterations": args_cli.max_iterations,
        "trainer_timesteps": trainer_cfg.get("timesteps"),
        "rollouts": rollouts,
        "distributed": args_cli.distributed,
        "seed": random_seed,
        "device": env_cfg.sim.device,
    }
    _LOGGER.info("SKRL training configuration: %s", snapshot)


def _validate_gym_registry(task: Optional[str], gym_module) -> None:
    """Ensure the requested task is available in the Gymnasium registry."""

    if not task:
        raise ValueError("Task identifier is required for SKRL training")
    if task not in gym_module.envs.registry:
        isaac_envs = [name for name in gym_module.envs.registry if name.startswith("Isaac-")]
        raise ValueError(f"Task {task} not found in gym registry. Available Isaac tasks: {isaac_envs}")


def _create_gym_environment(task: str, env_cfg: Any, enable_video: bool, gym_module):
    """Instantiate the IsaacLab task environment."""

    render_mode = "rgb_array" if enable_video else None
    return gym_module.make(task, cfg=env_cfg, render_mode=render_mode)


def _wrap_environment(
    env,
    *,
    args_cli: argparse.Namespace,
    log_dir: Path,
    gym_module,
    multi_agent_to_single_agent,
    direct_mar_env_type: Any,
    vec_wrapper_cls,
):
    """Apply optional transformations and SKRL vector environment wrapper."""

    if isinstance(env.unwrapped, direct_mar_env_type) and args_cli.algorithm.lower() == "ppo":
        env = multi_agent_to_single_agent(env)
    env = _maybe_wrap_video(gym_module, env, args_cli, log_dir)
    return vec_wrapper_cls(env, ml_framework=args_cli.ml_framework)


def _setup_agent_checkpoint(runner, resume_path: Optional[str]) -> None:
    """Load checkpoint into the runner agent when a resume path is provided."""

    if not resume_path:
        return
    try:
        runner.agent.load(resume_path)
    except AttributeError as exc:  # pragma: no cover - defensive guard
        raise RuntimeError("Runner agent unavailable during checkpoint load") from exc


def _apply_mlflow_logging(runner, mlflow_module) -> None:
    """Attach MLflow metric logging to the agent update loop."""

    if mlflow_module is None:
        return
    try:
        wrapper_func = create_mlflow_logging_wrapper(
            agent=runner.agent,
            mlflow_module=mlflow_module,
            metric_filter=None,
        )
        runner.agent._update = wrapper_func
    except AttributeError as exc:  # pragma: no cover - defensive guard
        raise RuntimeError("Runner agent unavailable for MLflow logging") from exc


def _start_mlflow_run(
    mlflow_module,
    *,
    context: Optional[AzureMLContext],
    args: argparse.Namespace,
    args_cli: argparse.Namespace,
    env_cfg: Any,
    agent_dict: Dict[str, Any],
    log_dir: Path,
    resume_path: Optional[str],
    random_seed: int,
    rollouts: int,
) -> int:
    """Bootstrap MLflow tracking and return the computed log interval."""

    mlflow_module.autolog(log_models=False)
    mlflow_module.start_run(run_name=log_dir.name)

    env_count = _resolve_env_count(env_cfg)
    log_interval = _parse_mlflow_log_interval(args_cli.mlflow_log_interval, rollouts)
    mlflow_module.log_params(
        {
            "algorithm": args_cli.algorithm,
            "ml_framework": args_cli.ml_framework,
            "num_envs": env_count,
            "distributed": args_cli.distributed,
            "resume_checkpoint": bool(resume_path),
            "seed": random_seed,
            "mlflow_log_interval": log_interval,
            "mlflow_log_interval_preset": args_cli.mlflow_log_interval,
        }
    )

    if resume_path:
        mlflow_module.set_tag("checkpoint_resume", resume_path)
    mlflow_module.set_tag("log_dir", str(log_dir))
    mlflow_module.set_tag("task", args_cli.task or "")
    mlflow_module.set_tag("entrypoint", "training/scripts/train.py")
    if context:
        mlflow_module.set_tag("azureml_workspace", context.workspace_name)
    mlflow_module.set_tag("checkpoint_mode", args.checkpoint_mode)
    if args.checkpoint_uri:
        mlflow_module.set_tag("checkpoint_source_uri", args.checkpoint_uri)
    return log_interval


def _finalize_mlflow_run(
    mlflow_module,
    *,
    outcome: str,
    log_dir: Path,
    resume_path: Optional[str],
    context: Optional[AzureMLContext],
    args: argparse.Namespace,
    args_cli: argparse.Namespace,
) -> None:
    """Log artifacts, register models, and close the MLflow run."""

    mlflow_module.set_tag("training_outcome", outcome)
    latest_checkpoint_uri = _log_artifacts(mlflow_module, log_dir, resume_path)
    if args.register_checkpoint and latest_checkpoint_uri:
        _register_checkpoint_model(
            context=context,
            model_name=args.register_checkpoint,
            checkpoint_uri=latest_checkpoint_uri,
            checkpoint_mode=args.checkpoint_mode,
            task=args_cli.task,
        )
    mlflow_module.end_run()


def _execute_training_loop(runner, descriptor: Dict[str, Any]) -> Dict[str, Any]:
    """Run the SKRL training loop and attach elapsed seconds to the descriptor."""

    start = time.perf_counter()
    try:
        runner.run()
    except Exception:
        descriptor["elapsed_seconds"] = round(time.perf_counter() - start, 2)
        raise
    descriptor["elapsed_seconds"] = round(time.perf_counter() - start, 2)
    return descriptor


class TrainingModules(NamedTuple):
    """Aggregated imports and helpers required for training."""

    hydra_task_config: Any
    gym_module: Any
    skrl_module: Any
    runner_cls: Any
    manager_cfg_type: Any
    direct_cfg_type: Any
    direct_mar_cfg_type: Any
    direct_mar_env_type: Any
    multi_agent_to_single_agent: Any
    retrieve_file_path: Any
    print_dict: Any
    dump_yaml: Any
    dump_pickle: Optional[Any]
    vec_env_wrapper: Any
    mlflow_module: Optional[Any]


class LaunchState(NamedTuple):
    """Holds precomputed launch artifacts shared across training steps."""

    agent_dict: Dict[str, Any]
    random_seed: int
    rollouts: int
    log_dir: Path
    resume_path: Optional[str]


def _prepare_cli_arguments(
    parser: argparse.ArgumentParser,
    args: argparse.Namespace,
    hydra_args: Sequence[str],
) -> tuple[argparse.Namespace, Sequence[str]]:
    """Parse CLI inputs and emit launch argument logging."""

    _, base_tokens = _namespace_snapshot(args)
    tokens = list(base_tokens) + list(hydra_args)
    args_cli, leftover = parser.parse_known_args(tokens)
    if args_cli.video:
        args_cli.enable_cameras = True
    parsed_payload, _ = _namespace_snapshot(args_cli)
    parse_report = {
        "parsed": parsed_payload,
        "hydra_overrides": list(leftover),
        "launcher_hydra_args": list(hydra_args),
    }
    _LOGGER.info("SKRL runner arguments: %s", parse_report)
    return args_cli, leftover


def _initialize_simulation(app_launcher_cls, args_cli: argparse.Namespace, leftover: Sequence[str]):
    """Launch IsaacLab simulation application using parsed arguments."""

    sys.argv = [sys.argv[0]] + list(leftover)
    app_launcher = app_launcher_cls(args_cli)
    simulation_app = app_launcher.app
    kit_log_dir = getattr(getattr(simulation_app, "config", None), "log_dir", None)
    if kit_log_dir:
        _LOGGER.debug("Kit logs located at %s", kit_log_dir)
    return app_launcher, simulation_app


def _load_training_modules(
    args_cli: argparse.Namespace,
    context: Optional[AzureMLContext],
) -> TrainingModules:
    """Import IsaacLab, SKRL, and optional MLflow modules."""

    import isaaclab_tasks  # noqa: F401
    from isaaclab_tasks.utils.hydra import hydra_task_config
    import gymnasium as gym_module
    import skrl as skrl_module

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
        from skrl.utils.runner.torch import Runner as runner_cls
    else:
        from skrl.utils.runner.jax import Runner as runner_cls

    mlflow_module = None
    if context:
        import mlflow as mlflow_module

    return TrainingModules(
        hydra_task_config=hydra_task_config,
        gym_module=gym_module,
        skrl_module=skrl_module,
        runner_cls=runner_cls,
        manager_cfg_type=ManagerBasedRLEnvCfg,
        direct_cfg_type=DirectRLEnvCfg,
        direct_mar_cfg_type=DirectMARLEnvCfg,
        direct_mar_env_type=DirectMARLEnv,
        multi_agent_to_single_agent=multi_agent_to_single_agent,
        retrieve_file_path=retrieve_file_path,
        print_dict=print_dict,
        dump_yaml=dump_yaml,
        dump_pickle=dump_pickle,
        vec_env_wrapper=SkrlVecEnvWrapper,
        mlflow_module=mlflow_module,
    )


def _close_simulation(simulation_app) -> None:
    """Close simulation app and suppress expected shutdown issues."""

    if simulation_app is None:
        return
    try:
        simulation_app.close()
    except Exception:
        _LOGGER.exception("Failed to close simulation app")


def _build_run_descriptor(
    args_cli: argparse.Namespace,
    log_dir: Path,
    resume_path: Optional[str],
    agent_dict: Dict[str, Any],
    rollouts: int,
    log_interval: Optional[int],
) -> Dict[str, Any]:
    """Compose structured payload for runner logging."""

    descriptor: Dict[str, Any] = {
        "algorithm": args_cli.algorithm,
        "ml_framework": args_cli.ml_framework,
        "log_dir": str(log_dir),
        "resume_checkpoint": bool(resume_path),
        "resume_path": resume_path,
        "trainer_timesteps": agent_dict.get("trainer", {}).get("timesteps"),
        "max_iterations": args_cli.max_iterations,
        "rollouts": rollouts,
    }
    if log_interval is not None:
        descriptor["mlflow_log_interval"] = log_interval
    return descriptor


def _prepare_launch_state(
    env_cfg: Any,
    agent_cfg: Any,
    args_cli: argparse.Namespace,
    app_launcher,
    modules: TrainingModules,
) -> LaunchState:
    """Compute seed, agent config, and logging paths for a launch."""

    resume_path = _resolve_checkpoint(modules.retrieve_file_path, args_cli.checkpoint)
    agent_dict = _normalize_agent_config(agent_cfg)
    random_seed = _configure_environment(
        env_cfg,
        args_cli,
        app_launcher,
        manager_cfg_type=modules.manager_cfg_type,
        direct_cfg_type=modules.direct_cfg_type,
        direct_mar_cfg_type=modules.direct_mar_cfg_type,
    )
    rollouts = _configure_agent_training(agent_dict, args_cli, random_seed)
    _configure_jax_backend(args_cli.ml_framework, modules.skrl_module)

    log_dir = _prepare_log_paths(agent_dict, args_cli)
    _dump_config_files(log_dir, env_cfg, agent_dict, modules.dump_yaml, modules.dump_pickle)

    if isinstance(env_cfg, modules.manager_cfg_type) and args_cli.export_io_descriptors:
        env_cfg.export_io_descriptors = True
        env_cfg.io_descriptors_output_dir = str(log_dir)

    env_cfg.log_dir = str(log_dir)
    modules.print_dict(env_cfg.to_dict())
    modules.print_dict(agent_dict)
    _log_configuration_snapshot(args_cli, env_cfg, agent_dict, random_seed, rollouts)

    return LaunchState(
        agent_dict=agent_dict,
        random_seed=random_seed,
        rollouts=rollouts,
        log_dir=log_dir,
        resume_path=resume_path,
    )


def _instantiate_environment(
    env_cfg: Any,
    args_cli: argparse.Namespace,
    modules: TrainingModules,
    log_dir: Path,
):
    """Create and wrap the target environment for training."""

    _validate_gym_registry(args_cli.task, modules.gym_module)
    _LOGGER.info("Creating environment for task %s", args_cli.task)
    env = _create_gym_environment(args_cli.task, env_cfg, args_cli.video, modules.gym_module)
    return _wrap_environment(
        env,
        args_cli=args_cli,
        log_dir=log_dir,
        gym_module=modules.gym_module,
        multi_agent_to_single_agent=modules.multi_agent_to_single_agent,
        direct_mar_env_type=modules.direct_mar_env_type,
        vec_wrapper_cls=modules.vec_env_wrapper,
    )


def _initialize_runner(env, state: LaunchState, modules: TrainingModules):
    """Instantiate the SKRL runner and apply optional checkpointing/logging."""

    runner = modules.runner_cls(env, state.agent_dict)
    _setup_agent_checkpoint(runner, state.resume_path)
    _apply_mlflow_logging(runner, modules.mlflow_module)
    return runner


def _start_mlflow_if_needed(
    modules: TrainingModules,
    *,
    context: Optional[AzureMLContext],
    args: argparse.Namespace,
    args_cli: argparse.Namespace,
    env_cfg: Any,
    agent_dict: Dict[str, Any],
    log_dir: Path,
    resume_path: Optional[str],
    random_seed: int,
    rollouts: int,
) -> Tuple[Optional[int], bool]:
    """Start an MLflow run when tracking is enabled on the context."""

    if modules.mlflow_module is None:
        return None, False
    log_interval = _start_mlflow_run(
        modules.mlflow_module,
        context=context,
        args=args,
        args_cli=args_cli,
        env_cfg=env_cfg,
        agent_dict=agent_dict,
        log_dir=log_dir,
        resume_path=resume_path,
        random_seed=random_seed,
        rollouts=rollouts,
    )
    return log_interval, True


def _finalize_mlflow_if_needed(
    modules: TrainingModules,
    *,
    mlflow_active: bool,
    outcome: str,
    log_dir: Path,
    resume_path: Optional[str],
    context: Optional[AzureMLContext],
    args: argparse.Namespace,
    args_cli: argparse.Namespace,
) -> None:
    """Close MLflow run when it was previously started."""

    if not (modules.mlflow_module and mlflow_active):
        return
    _finalize_mlflow_run(
        modules.mlflow_module,
        outcome=outcome,
        log_dir=log_dir,
        resume_path=resume_path,
        context=context,
        args=args,
        args_cli=args_cli,
    )


def _run_hydra_training(
    *,
    args: argparse.Namespace,
    args_cli: argparse.Namespace,
    context: Optional[AzureMLContext],
    app_launcher,
    modules: TrainingModules,
) -> None:
    """Execute hydra-configured IsaacLab training launch."""

    if args_cli.seed == -1:
        args_cli.seed = random.randint(0, 10000)

    agent_entry = _agent_entry(args_cli)

    @modules.hydra_task_config(args_cli.task, agent_entry)
    def _launch(env_cfg, agent_cfg):
        env = None
        outcome = "success"
        state = _prepare_launch_state(env_cfg, agent_cfg, args_cli, app_launcher, modules)
        log_interval = None
        mlflow_active = False
        try:
            env = _instantiate_environment(env_cfg, args_cli, modules, state.log_dir)
            runner = _initialize_runner(env, state, modules)
            log_interval, mlflow_active = _start_mlflow_if_needed(
                modules,
                context=context,
                args=args,
                args_cli=args_cli,
                env_cfg=env_cfg,
                agent_dict=state.agent_dict,
                log_dir=state.log_dir,
                resume_path=state.resume_path,
                random_seed=state.random_seed,
                rollouts=state.rollouts,
            )

            run_descriptor = _build_run_descriptor(
                args_cli,
                state.log_dir,
                state.resume_path,
                state.agent_dict,
                state.rollouts,
                log_interval,
            )
            descriptor = dict(run_descriptor)
            _LOGGER.info("SKRL runner starting: %s", run_descriptor)
            try:
                descriptor = _execute_training_loop(runner, descriptor)
            except Exception:
                outcome = "failed"
                _LOGGER.exception("SKRL runner failed: %s", descriptor)
                raise
            else:
                if modules.mlflow_module:
                    active_run = modules.mlflow_module.active_run()
                    if active_run:
                        descriptor["mlflow_run_id"] = active_run.info.run_id
                _LOGGER.debug("SKRL runner completed: %s", descriptor)
        finally:
            if env is not None:
                env.close()
            _finalize_mlflow_if_needed(
                modules,
                mlflow_active=mlflow_active,
                outcome=outcome,
                log_dir=state.log_dir,
                resume_path=state.resume_path,
                context=context,
                args=args,
                args_cli=args_cli,
            )

    try:
        _launch()
    except Exception:
        _LOGGER.exception("Exception during hydra launch execution")
        raise


def run_training(
    *,
    args: argparse.Namespace,
    hydra_args: Sequence[str],
    context: Optional[AzureMLContext],
) -> None:
    """Execute SKRL training with IsaacLab environment and optional Azure ML tracking.

    Args:
        args: Parsed launch arguments including checkpoint behavior.
        hydra_args: Sequence of Hydra overrides to forward to IsaacLab launcher.
        context: Azure ML context enabling MLflow tracking and model registration.

    Raises:
        SystemExit: If IsaacLab dependencies are missing or task is unavailable.
    """
    simulation_app = None
    try:
        from isaaclab.app import AppLauncher
    except ImportError as exc:
        raise SystemExit("IsaacLab packages are required for SKRL training") from exc

    parser = _build_parser(AppLauncher)
    args_cli, leftover = _prepare_cli_arguments(parser, args, hydra_args)

    try:
        app_launcher, simulation_app = _initialize_simulation(AppLauncher, args_cli, leftover)
        modules = _load_training_modules(args_cli, context)
        _run_hydra_training(
            args=args,
            args_cli=args_cli,
            context=context,
            app_launcher=app_launcher,
            modules=modules,
        )
    except ImportError as exc:
        _LOGGER.error("ImportError caught in run_training: %s", exc)
        raise SystemExit("Required IsaacLab dependencies are missing for SKRL training") from exc
    except Exception:
        _LOGGER.exception("Unexpected exception in run_training")
        raise
    finally:
        _close_simulation(simulation_app)
