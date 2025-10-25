"""RSL-RL training orchestration with IsaacLab environments and Azure MLflow integration.

This module provides the main training loop for reinforcement learning agents using
the RSL-RL library with IsaacLab simulation environments. It handles:
- Environment and agent configuration via Hydra
- Checkpoint loading and model registration
- MLflow metric logging and artifact tracking
- Video recording of training rollouts
- Integration with Azure ML workspaces
TODO: once tested, mv train.py train_deprecated.py && mv train_refactored.py train.py
"""

from __future__ import annotations

import argparse
import logging
import os
import random
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, NamedTuple, Sequence

from training.utils import AzureMLContext, set_env_defaults

_LOGGER = logging.getLogger("isaaclab.rsl_rl")

_AGENT_ENTRY_DEFAULT = "rsl_rl_cfg_entry_point"


def _build_parser(app_launcher_cls: Any) -> argparse.ArgumentParser:
    """Build argument parser for RSL-RL training with IsaacLab launcher args."""
    import cli_args

    parser = argparse.ArgumentParser(description="Train IsaacLab RSL-RL policies")
    parser.add_argument("--task", type=str, default=None, help="IsaacLab task identifier")
    parser.add_argument("--agent", type=str, default=_AGENT_ENTRY_DEFAULT, help="Agent configuration entry point")
    parser.add_argument("--num_envs", type=int, default=None, help="Override number of vectorized environments")
    parser.add_argument("--max_iterations", type=int, default=None, help="Maximum training iterations")
    parser.add_argument("--seed", type=int, default=None, help="Random seed")
    parser.add_argument("--distributed", action="store_true", help="Enable distributed execution")
    parser.add_argument("--checkpoint", type=str, default=None, help="Resume checkpoint path")
    parser.add_argument("--export_io_descriptors", action="store_true", help="Dump IO descriptors")
    parser.add_argument("--video", action="store_true", help="Record rollout videos")
    parser.add_argument("--video_length", type=int, default=200, help="Video duration in steps")
    parser.add_argument("--video_interval", type=int, default=2000, help="Video capture interval")
    cli_args.add_rsl_rl_args(parser)
    app_launcher_cls.add_app_launcher_args(parser)
    return parser


def _prepare_log_paths(agent_cfg: dict[str, Any], cli_args: argparse.Namespace) -> Path:
    """Configure experiment metadata and create log directory for the run."""
    experiment_name = agent_cfg.get("experiment_name", "rsl_rl_experiment")
    root_path = Path("logs") / "rsl_rl" / experiment_name
    root_path = root_path.resolve()
    timestamp = datetime.utcnow().strftime("%Y-%m-%d_%H-%M-%S")
    run_name = timestamp
    custom_name = agent_cfg.get("run_name")
    if custom_name:
        run_name = f"{run_name}_{custom_name}"
    log_dir = root_path / run_name
    log_dir.mkdir(parents=True, exist_ok=True)
    return log_dir


def _wrap_with_video_recorder(gym_module: Any, env: Any, cli_args: argparse.Namespace, log_dir: Path) -> Any:
    """Wrap environment with video capture when video recording is enabled."""
    if not cli_args.video:
        return env
    video_dir = log_dir / "videos" / "train"
    video_dir.mkdir(parents=True, exist_ok=True)
    video_kwargs = {
        "video_folder": str(video_dir),
        "step_trigger": lambda step: step % cli_args.video_interval == 0,
        "video_length": cli_args.video_length,
        "disable_logger": True,
    }
    _LOGGER.info("Recording training videos to %s", video_dir)
    return gym_module.wrappers.RecordVideo(env, **video_kwargs)


def _log_artifacts(mlflow: Any, log_dir: Path, resume_path: str | None) -> str | None:
    """Log training artifacts to MLflow and derive latest checkpoint URI."""
    params_dir = log_dir / "params"
    for rel_path in ("env.yaml", "agent.yaml", "env.pkl", "agent.pkl"):
        candidate = params_dir / rel_path
        if candidate.exists():
            mlflow.log_artifact(str(candidate), artifact_path="rsl-rl-run")
    if resume_path:
        mlflow.log_artifact(resume_path, artifact_path="rsl-rl-run/checkpoints")

    checkpoint_dir = log_dir / "checkpoints"
    active_run = mlflow.active_run()
    latest_uri: str | None = None
    if checkpoint_dir.exists() and checkpoint_dir.is_dir():
        mlflow.log_artifacts(str(checkpoint_dir), artifact_path="rsl-rl-run/checkpoints")
        latest_file: Path | None = None
        for candidate in checkpoint_dir.rglob("*"):
            if candidate.is_file():
                if latest_file is None or candidate.stat().st_mtime > latest_file.stat().st_mtime:
                    latest_file = candidate
        if active_run and latest_file:
            run_id = active_run.info.run_id
            relative_path = latest_file.relative_to(checkpoint_dir)
            directory_uri = f"runs:/{run_id}/rsl-rl-run/checkpoints"
            latest_uri = f"{directory_uri}/{relative_path.as_posix()}"
            mlflow.set_tag("checkpoint_directory", directory_uri)
            mlflow.set_tag("checkpoint_latest", latest_uri)
            token = f"::checkpoint_uri::{latest_uri}"
            mlflow.set_tag("checkpoint_log_token", token)
            _LOGGER.info("Latest checkpoint: %s", latest_uri)
            print(token)

    videos_dir = log_dir / "videos"
    if videos_dir.exists():
        mlflow.log_artifacts(str(videos_dir), artifact_path="videos")
    return latest_uri


def _register_checkpoint_model(
    *,
    context: AzureMLContext | None,
    model_name: str,
    checkpoint_uri: str,
    checkpoint_mode: str | None,
    task: str | None,
) -> None:
    """Register a checkpoint artifact as an Azure ML model when context is available."""
    if context is None:
        _LOGGER.info("Skipping checkpoint registration (no Azure ML context)")
        return
    try:
        from azure.ai.ml.entities import Model
    except ImportError as exc:
        _LOGGER.error("Azure ML SDK missing; cannot register checkpoint: %s", exc)
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
            description="IsaacLab RSL-RL checkpoint artifact",
            tags=tags,
        )
        context.client.models.create_or_update(model)
        _LOGGER.info("Registered checkpoint as Azure ML model: %s", model_name)
    except Exception as exc:
        _LOGGER.error("Failed to register checkpoint model %s: %s", model_name, exc)


def _resolve_env_count(env_cfg: Any) -> int | None:
    """Extract environment count from configuration object regardless of env type."""
    scene = getattr(env_cfg, "scene", None)
    if scene and hasattr(scene, "num_envs"):
        return scene.num_envs
    return getattr(env_cfg, "num_envs", None)


def _resolve_checkpoint(retrieve_file_path: Any, checkpoint: str | None) -> str | None:
    """Resolve checkpoint location via IsaacLab asset resolver."""
    if not checkpoint:
        return None
    try:
        return retrieve_file_path(checkpoint)
    except FileNotFoundError as exc:
        raise SystemExit(f"Checkpoint path not found: {checkpoint}") from exc


def _normalize_agent_config(agent_cfg: Any) -> dict[str, Any]:
    """Return agent configuration as a plain dictionary."""
    to_dict = getattr(agent_cfg, "to_dict", None)
    if callable(to_dict):
        return to_dict()
    return dict(agent_cfg) if hasattr(agent_cfg, "__iter__") else {"config": agent_cfg}


def _set_num_envs_for_manager_cfg(env_cfg: Any, num_envs: int | None) -> None:
    if num_envs is not None:
        env_cfg.scene.num_envs = num_envs


def _set_num_envs_for_direct_cfg(env_cfg: Any, num_envs: int | None) -> None:
    if num_envs is not None:
        env_cfg.num_envs = num_envs


def _configure_environment(
    env_cfg: Any,
    cli_args: argparse.Namespace,
    app_launcher,
    *,
    manager_cfg_type: Any,
    direct_cfg_type: Any,
    direct_mar_cfg_type: Any,
) -> int:
    """Update environment configuration with CLI overrides and return seed."""
    random_seed = cli_args.seed if cli_args.seed is not None else random.randint(1, 1_000_000)
    random.seed(random_seed)
    set_env_defaults(
        {
            "PYTHONHASHSEED": str(random_seed),
            "HYDRA_FULL_ERROR": "1",
        }
    )

    if isinstance(env_cfg, manager_cfg_type):
        _set_num_envs_for_manager_cfg(env_cfg, cli_args.num_envs)
    elif isinstance(env_cfg, (direct_cfg_type, direct_mar_cfg_type)):
        _set_num_envs_for_direct_cfg(env_cfg, cli_args.num_envs)

    if cli_args.distributed:
        env_cfg.sim.device = f"cuda:{app_launcher.local_rank}"

    env_cfg.seed = random_seed
    return random_seed


def _configure_agent_training(
    agent_cfg: Any,
    cli_args: argparse.Namespace,
    random_seed: int,
    cli_args_module: Any,
) -> None:
    """Align agent training configuration with CLI overrides."""
    updated_cfg = cli_args_module.update_rsl_rl_cfg(agent_cfg, cli_args)
    for key, value in vars(updated_cfg).items():
        setattr(agent_cfg, key, value)

    if cli_args.max_iterations is not None:
        agent_cfg.max_iterations = cli_args.max_iterations
    agent_cfg.seed = random_seed

    if cli_args.distributed:
        agent_cfg.device = f"cuda:{getattr(cli_args, 'local_rank', 0)}"


def _dump_config_files(
    log_dir: Path,
    env_cfg: Any,
    agent_cfg: Any,
    dump_yaml_func: Any,
    dump_pickle_func: Any | None,
) -> None:
    """Persist environment and agent configuration snapshots."""
    params_dir = log_dir / "params"
    params_dir.mkdir(parents=True, exist_ok=True)
    dump_yaml_func(str(params_dir / "env.yaml"), env_cfg)
    dump_yaml_func(str(params_dir / "agent.yaml"), agent_cfg)
    if dump_pickle_func:
        dump_pickle_func(str(params_dir / "env.pkl"), env_cfg)
        dump_pickle_func(str(params_dir / "agent.pkl"), agent_cfg)


def _log_configuration_snapshot(
    cli_args: argparse.Namespace,
    env_cfg: Any,
    agent_cfg: Any,
    random_seed: int,
) -> None:
    """Emit consolidated configuration details for the current run."""
    snapshot = {
        "task": cli_args.task,
        "num_envs": _resolve_env_count(env_cfg),
        "max_iterations": agent_cfg.max_iterations,
        "distributed": cli_args.distributed,
        "seed": random_seed,
        "device": env_cfg.sim.device,
        "algorithm": getattr(getattr(agent_cfg, "algorithm", None), "class_name", agent_cfg.class_name),
    }
    _LOGGER.info("RSL-RL training configuration: %s", snapshot)


def _validate_gym_registry(task: str | None, gym_module: Any) -> None:
    """Ensure the requested task is available in the Gymnasium registry."""
    if not task:
        raise ValueError("Task identifier is required for RSL-RL training")
    if task not in gym_module.envs.registry:
        isaac_envs = [name for name in gym_module.envs.registry if name.startswith("Isaac-")]
        raise ValueError(f"Task {task} not found in gym registry. Available Isaac tasks: {isaac_envs}")


def _create_gym_environment(task: str, env_cfg: Any, is_video_enabled: bool, gym_module: Any) -> Any:
    """Instantiate the IsaacLab task environment."""
    render_mode = "rgb_array" if is_video_enabled else None
    return gym_module.make(task, cfg=env_cfg, render_mode=render_mode)


def _wrap_environment(
    env: Any,
    *,
    cli_args: argparse.Namespace,
    log_dir: Path,
    gym_module: Any,
    multi_agent_to_single_agent: Any,
    direct_mar_env_type: Any,
    vec_wrapper_cls: Any,
    agent_cfg: Any,
) -> Any:
    """Apply optional transformations and RSL-RL vector environment wrapper."""
    if isinstance(env.unwrapped, direct_mar_env_type):
        env = multi_agent_to_single_agent(env)
    env = _wrap_with_video_recorder(gym_module, env, cli_args, log_dir)
    return vec_wrapper_cls(env, clip_actions=agent_cfg.clip_actions)


def _setup_agent_checkpoint(runner: Any, resume_path: str | None) -> None:
    """Load checkpoint into the runner when a resume path is provided."""
    if not resume_path:
        return
    _LOGGER.info("Loading model checkpoint from: %s", resume_path)
    runner.load(resume_path)


def _collect_training_metrics(runner: Any) -> dict[str, float]:
    """Extract metrics from the RSL-RL runner for MLflow logging."""
    metrics: dict[str, float] = {}
    alg = getattr(runner, "alg", None)
    storage = getattr(alg, "storage", None)
    if storage is not None:
        advantages = getattr(storage, "advantages", None)
        if advantages is not None and hasattr(advantages, "mean"):
            try:
                metrics["mean_advantage"] = float(advantages.mean())
            except Exception:
                pass
        values = getattr(storage, "values", None)
        if values is not None and hasattr(values, "mean"):
            try:
                metrics["mean_value"] = float(values.mean())
            except Exception:
                pass
    learning_rate = getattr(alg, "learning_rate", None)
    if isinstance(learning_rate, (int, float)):
        metrics["learning_rate"] = float(learning_rate)
    return metrics


def _apply_mlflow_logging(runner: Any, mlflow: Any | None) -> None:
    """Attach MLflow metric logging to the runner checkpoint save."""
    if mlflow is None:
        return

    original_save = runner.save

    def mlflow_enhanced_save(path, *args, **kwargs):
        result = original_save(path, *args, **kwargs)
        try:
            current_iter = getattr(runner, "current_learning_iteration", 0)
            metrics = _collect_training_metrics(runner)
            if metrics:
                mlflow.log_metrics(metrics, step=current_iter)
            if os.path.isfile(path):
                mlflow.log_artifact(path, artifact_path="checkpoints")
                mlflow.set_tag("last_checkpoint_path", path)
        except Exception as exc:
            _LOGGER.warning("Failed to log checkpoint metrics at save: %s", exc)
        return result

    runner.save = mlflow_enhanced_save


def _start_mlflow_run(
    mlflow: Any,
    *,
    context: AzureMLContext | None,
    args: argparse.Namespace,
    cli_args: argparse.Namespace,
    env_cfg: Any,
    agent_cfg: Any,
    log_dir: Path,
    resume_path: str | None,
    random_seed: int,
) -> None:
    """Bootstrap MLflow tracking."""
    mlflow.autolog(log_models=False)
    mlflow.start_run(run_name=log_dir.name)

    env_count = _resolve_env_count(env_cfg)
    algorithm_name = getattr(getattr(agent_cfg, "algorithm", None), "class_name", agent_cfg.class_name)
    mlflow.log_params(
        {
            "algorithm": algorithm_name,
            "task": cli_args.task,
            "num_envs": env_count,
            "max_iterations": agent_cfg.max_iterations,
            "distributed": cli_args.distributed,
            "resume_checkpoint": bool(resume_path),
            "seed": random_seed,
            "clip_actions": agent_cfg.clip_actions,
        }
    )

    if resume_path:
        mlflow.set_tag("checkpoint_resume", resume_path)
    mlflow.set_tag("log_dir", str(log_dir))
    mlflow.set_tag("task", cli_args.task or "")
    mlflow.set_tag("entrypoint", "training/scripts/rsl_rl/train.py")
    if context:
        mlflow.set_tag("azureml_workspace", context.workspace_name)
    mlflow.set_tag("checkpoint_mode", args.checkpoint_mode)
    if args.checkpoint_uri:
        mlflow.set_tag("checkpoint_source_uri", args.checkpoint_uri)


def _finalize_mlflow_run(
    mlflow: Any,
    *,
    training_outcome: str,
    log_dir: Path,
    resume_path: str | None,
    context: AzureMLContext | None,
    args: argparse.Namespace,
    cli_args: argparse.Namespace,
) -> None:
    """Log artifacts, register models, and close the MLflow run."""
    mlflow.set_tag("training_outcome", training_outcome)
    latest_checkpoint_uri = _log_artifacts(mlflow, log_dir, resume_path)
    if args.register_checkpoint and latest_checkpoint_uri:
        _register_checkpoint_model(
            context=context,
            model_name=args.register_checkpoint,
            checkpoint_uri=latest_checkpoint_uri,
            checkpoint_mode=args.checkpoint_mode,
            task=cli_args.task,
        )
    mlflow.end_run()


def _execute_training_loop(runner: Any, descriptor: dict[str, Any], max_iterations: int) -> dict[str, Any]:
    """Run the RSL-RL training loop and attach elapsed seconds to the descriptor."""
    start = time.perf_counter()
    try:
        runner.learn(num_learning_iterations=max_iterations, init_at_random_ep_len=True)
    except Exception:
        descriptor["elapsed_seconds"] = round(time.perf_counter() - start, 2)
        raise
    descriptor["elapsed_seconds"] = round(time.perf_counter() - start, 2)
    return descriptor


class TrainingModules(NamedTuple):
    """Aggregated imports and helpers required for training."""

    hydra_task_config: Any
    gym_module: Any
    manager_cfg_type: Any
    direct_cfg_type: Any
    direct_mar_cfg_type: Any
    direct_mar_env_type: Any
    multi_agent_to_single_agent: Any
    retrieve_file_path: Any
    print_dict: Any
    dump_yaml: Any
    dump_pickle: Any | None
    vec_env_wrapper: Any
    runner_on_policy: Any
    runner_distillation: Any
    mlflow_module: Any | None
    cli_args_module: Any


class LaunchState(NamedTuple):
    """Holds precomputed launch artifacts shared across training steps."""

    agent_cfg: Any
    random_seed: int
    log_dir: Path
    resume_path: str | None


def _prepare_cli_arguments(
    parser: argparse.ArgumentParser,
    args: argparse.Namespace,
    hydra_args: Sequence[str],
) -> tuple[argparse.Namespace, Sequence[str]]:
    """Parse CLI inputs and emit launch argument logging."""
    tokens = [sys.argv[0]] + list(hydra_args)
    cli_args, unparsed_args = parser.parse_known_args(tokens[1:])
    if cli_args.video:
        cli_args.enable_cameras = True
    _LOGGER.info("RSL-RL runner arguments: task=%s, hydra_overrides=%s", cli_args.task, list(unparsed_args))
    return cli_args, unparsed_args


def _initialize_simulation(
    app_launcher_cls: Any, cli_args: argparse.Namespace, unparsed_args: Sequence[str]
) -> tuple[Any, Any]:
    """Launch IsaacLab simulation application using parsed arguments."""
    sys.argv = [sys.argv[0]] + list(unparsed_args)
    app_launcher = app_launcher_cls(cli_args)
    simulation_app = app_launcher.app
    return app_launcher, simulation_app


def _load_training_modules(
    cli_args: argparse.Namespace,
    context: AzureMLContext | None,
) -> TrainingModules:
    """Import IsaacLab, RSL-RL, and optional MLflow modules."""
    import isaaclab_tasks  # noqa: F401
    from isaaclab_tasks.utils.hydra import hydra_task_config
    import gymnasium as gym_module
    from rsl_rl.runners import OnPolicyRunner, DistillationRunner

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
    from isaaclab_rl.rsl_rl import RslRlVecEnvWrapper

    import cli_args as cli_args_module

    mlflow_module = None
    if context:
        import mlflow as mlflow_module

    return TrainingModules(
        hydra_task_config=hydra_task_config,
        gym_module=gym_module,
        manager_cfg_type=ManagerBasedRLEnvCfg,
        direct_cfg_type=DirectRLEnvCfg,
        direct_mar_cfg_type=DirectMARLEnvCfg,
        direct_mar_env_type=DirectMARLEnv,
        multi_agent_to_single_agent=multi_agent_to_single_agent,
        retrieve_file_path=retrieve_file_path,
        print_dict=print_dict,
        dump_yaml=dump_yaml,
        dump_pickle=dump_pickle,
        vec_env_wrapper=RslRlVecEnvWrapper,
        runner_on_policy=OnPolicyRunner,
        runner_distillation=DistillationRunner,
        mlflow_module=mlflow_module,
        cli_args_module=cli_args_module,
    )


def _close_simulation(simulation_app: Any | None) -> None:
    """Close simulation app and suppress expected shutdown issues."""
    if simulation_app is None:
        return
    try:
        simulation_app.close()
    except Exception:
        _LOGGER.info("Simulation app close raised exception (expected during shutdown)")


def _prepare_launch_state(
    env_cfg: Any,
    agent_cfg: Any,
    cli_args: argparse.Namespace,
    app_launcher: Any,
    modules: TrainingModules,
) -> LaunchState:
    """Compute seed, agent config, and logging paths for a launch."""
    resume_path = _resolve_checkpoint(modules.retrieve_file_path, cli_args.checkpoint)

    random_seed = _configure_environment(
        env_cfg,
        cli_args,
        app_launcher,
        manager_cfg_type=modules.manager_cfg_type,
        direct_cfg_type=modules.direct_cfg_type,
        direct_mar_cfg_type=modules.direct_mar_cfg_type,
    )
    _configure_agent_training(agent_cfg, cli_args, random_seed, modules.cli_args_module)

    agent_dict = _normalize_agent_config(agent_cfg)
    log_dir = _prepare_log_paths(agent_dict, cli_args)
    _dump_config_files(log_dir, env_cfg, agent_cfg, modules.dump_yaml, modules.dump_pickle)

    if isinstance(env_cfg, modules.manager_cfg_type) and cli_args.export_io_descriptors:
        env_cfg.export_io_descriptors = True
        env_cfg.io_descriptors_output_dir = str(log_dir)

    env_cfg.log_dir = str(log_dir)
    modules.print_dict(env_cfg.to_dict())
    modules.print_dict(agent_dict)
    _log_configuration_snapshot(cli_args, env_cfg, agent_cfg, random_seed)

    return LaunchState(
        agent_cfg=agent_cfg,
        random_seed=random_seed,
        log_dir=log_dir,
        resume_path=resume_path,
    )


def _instantiate_environment(
    env_cfg: Any,
    cli_args: argparse.Namespace,
    modules: TrainingModules,
    log_dir: Path,
    agent_cfg: Any,
) -> Any:
    """Create and wrap the target environment for training."""
    _validate_gym_registry(cli_args.task, modules.gym_module)
    _LOGGER.info("Creating environment for task %s", cli_args.task)
    env = _create_gym_environment(cli_args.task, env_cfg, cli_args.video, modules.gym_module)
    return _wrap_environment(
        env,
        cli_args=cli_args,
        log_dir=log_dir,
        gym_module=modules.gym_module,
        multi_agent_to_single_agent=modules.multi_agent_to_single_agent,
        direct_mar_env_type=modules.direct_mar_env_type,
        vec_wrapper_cls=modules.vec_env_wrapper,
        agent_cfg=agent_cfg,
    )


def _initialize_runner(env: Any, state: LaunchState, modules: TrainingModules) -> Any:
    """Instantiate the RSL-RL runner and apply optional checkpointing/logging."""
    agent_dict = _normalize_agent_config(state.agent_cfg)
    if state.agent_cfg.class_name == "OnPolicyRunner":
        runner = modules.runner_on_policy(env, agent_dict, log_dir=str(state.log_dir), device=state.agent_cfg.device)
    elif state.agent_cfg.class_name == "DistillationRunner":
        runner = modules.runner_distillation(env, agent_dict, log_dir=str(state.log_dir), device=state.agent_cfg.device)
    else:
        raise ValueError(f"Unsupported runner class: {state.agent_cfg.class_name}")

    runner.add_git_repo_to_log(__file__)
    _setup_agent_checkpoint(runner, state.resume_path)
    _apply_mlflow_logging(runner, modules.mlflow_module)
    return runner


def _start_mlflow_if_needed(
    modules: TrainingModules,
    *,
    context: AzureMLContext | None,
    args: argparse.Namespace,
    cli_args: argparse.Namespace,
    env_cfg: Any,
    agent_cfg: Any,
    log_dir: Path,
    resume_path: str | None,
    random_seed: int,
) -> bool:
    """Start an MLflow run when tracking is enabled on the context."""
    if modules.mlflow_module is None:
        return False
    _start_mlflow_run(
        modules.mlflow_module,
        context=context,
        args=args,
        cli_args=cli_args,
        env_cfg=env_cfg,
        agent_cfg=agent_cfg,
        log_dir=log_dir,
        resume_path=resume_path,
        random_seed=random_seed,
    )
    return True


def _finalize_mlflow_if_needed(
    modules: TrainingModules,
    *,
    mlflow_active: bool,
    training_outcome: str,
    log_dir: Path,
    resume_path: str | None,
    context: AzureMLContext | None,
    args: argparse.Namespace,
    cli_args: argparse.Namespace,
) -> None:
    """Close MLflow run when it was previously started."""
    if not (modules.mlflow_module and mlflow_active):
        return
    _finalize_mlflow_run(
        modules.mlflow_module,
        training_outcome=training_outcome,
        log_dir=log_dir,
        resume_path=resume_path,
        context=context,
        args=args,
        cli_args=cli_args,
    )


def _run_hydra_training(
    *,
    args: argparse.Namespace,
    cli_args: argparse.Namespace,
    context: AzureMLContext | None,
    app_launcher: Any,
    modules: TrainingModules,
) -> None:
    """Execute hydra-configured IsaacLab training launch."""
    if cli_args.seed == -1:
        cli_args.seed = random.randint(0, 10000)

    @modules.hydra_task_config(cli_args.task, cli_args.agent)
    def _launch(env_cfg, agent_cfg):
        env = None
        training_outcome = "success"
        state = _prepare_launch_state(env_cfg, agent_cfg, cli_args, app_launcher, modules)
        mlflow_active = False
        try:
            env = _instantiate_environment(env_cfg, cli_args, modules, state.log_dir, agent_cfg)
            runner = _initialize_runner(env, state, modules)
            mlflow_active = _start_mlflow_if_needed(
                modules,
                context=context,
                args=args,
                cli_args=cli_args,
                env_cfg=env_cfg,
                agent_cfg=agent_cfg,
                log_dir=state.log_dir,
                resume_path=state.resume_path,
                random_seed=state.random_seed,
            )

            descriptor = {
                "task": cli_args.task,
                "log_dir": str(state.log_dir),
                "resume_checkpoint": bool(state.resume_path),
                "max_iterations": agent_cfg.max_iterations,
            }
            _LOGGER.info("Starting RSL-RL training: %s", descriptor)
            try:
                descriptor = _execute_training_loop(runner, descriptor, agent_cfg.max_iterations)
            except Exception:
                training_outcome = "failed"
                _LOGGER.exception("Training failed after %.2f seconds", descriptor.get("elapsed_seconds", 0))
                raise
            else:
                if modules.mlflow_module:
                    active_run = modules.mlflow_module.active_run()
                    if active_run:
                        descriptor["mlflow_run_id"] = active_run.info.run_id
            _LOGGER.info("Finished RSL-RL training: %s", descriptor)
        finally:
            if env is not None:
                env.close()
            _finalize_mlflow_if_needed(
                modules,
                mlflow_active=mlflow_active,
                training_outcome=training_outcome,
                log_dir=state.log_dir,
                resume_path=state.resume_path,
                context=context,
                args=args,
                cli_args=cli_args,
            )

    _launch()


def run_training(
    *,
    args: argparse.Namespace,
    hydra_args: Sequence[str],
    context: AzureMLContext | None,
) -> None:
    """Execute RSL-RL training with IsaacLab environment and optional Azure ML tracking."""
    simulation_app = None
    try:
        from isaaclab.app import AppLauncher
    except ImportError as exc:
        raise SystemExit("IsaacLab packages are required for RSL-RL training") from exc

    parser = _build_parser(AppLauncher)
    cli_args, unparsed_args = _prepare_cli_arguments(parser, args, hydra_args)

    try:
        app_launcher, simulation_app = _initialize_simulation(AppLauncher, cli_args, unparsed_args)
        modules = _load_training_modules(cli_args, context)
        _run_hydra_training(
            args=args,
            cli_args=cli_args,
            context=context,
            app_launcher=app_launcher,
            modules=modules,
        )
    finally:
        _close_simulation(simulation_app)
