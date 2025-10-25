"""RSL-RL training orchestration with IsaacLab environments and Azure MLflow integration.

This module provides the main training loop for reinforcement learning agents using
the RSL-RL library with IsaacLab simulation environments. It handles:
- Environment and agent configuration via Hydra
- Checkpoint loading and model registration
- MLflow metric logging and artifact tracking
- Video recording of training rollouts
- Integration with Azure ML workspaces
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

from isaaclab.app import AppLauncher

import cli_args

# add argparse arguments
parser = argparse.ArgumentParser(description="Train an RL agent with RSL-RL.")
parser.add_argument("--video", action="store_true", default=False, help="Record videos during training.")
parser.add_argument(
    "--video_length",
    type=int,
    default=200,
    help="Length of the recorded video (in steps).",
)
parser.add_argument(
    "--video_interval",
    type=int,
    default=2000,
    help="Interval between video recordings (in steps).",
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
parser.add_argument("--max_iterations", type=int, default=None, help="RL Policy training iterations.")
parser.add_argument(
    "--distributed",
    action="store_true",
    default=False,
    help="Run training with multiple GPUs or nodes.",
)
parser.add_argument(
    "--export_io_descriptors",
    action="store_true",
    default=False,
    help="Export IO descriptors.",
)
parser.add_argument(
    "--disable_azure",
    action="store_true",
    default=False,
    help="Disable Azure integration for training.",
)
parser.add_argument(
    "--azure_config",
    type=str,
    default=None,
    help="Path to Azure configuration file (YAML).",
)
# append RSL-RL cli arguments
cli_args.add_rsl_rl_args(parser)
# append AppLauncher cli args
AppLauncher.add_app_launcher_args(parser)
args_cli, hydra_args = parser.parse_known_args()

# always enable cameras to record video
if args_cli.video:
    args_cli.enable_cameras = True

# clear out sys.argv for Hydra
sys.argv = [sys.argv[0]] + hydra_args

# launch omniverse app
app_launcher = AppLauncher(args_cli)
simulation_app = app_launcher.app

"""Check for minimum supported RSL-RL version."""

import importlib.metadata as metadata
import platform

from packaging import version

# check minimum supported rsl-rl version
RSL_RL_VERSION = "3.0.1"
installed_version = metadata.version("rsl-rl-lib")
if version.parse(installed_version) < version.parse(RSL_RL_VERSION):
    if platform.system() == "Windows":
        cmd = [
            r".\isaaclab.bat",
            "-p",
            "-m",
            "pip",
            "install",
            f"rsl-rl-lib=={RSL_RL_VERSION}",
        ]
    else:
        cmd = [
            "./isaaclab.sh",
            "-p",
            "-m",
            "pip",
            "install",
            f"rsl-rl-lib=={RSL_RL_VERSION}",
        ]
    print(
        f"Please install the correct version of RSL-RL.\nExisting version is: '{installed_version}'"
        f" and required version is: '{RSL_RL_VERSION}'.\nTo install the correct version, run:"
        f"\n\n\t{' '.join(cmd)}\n"
    )
    exit(1)

import gymnasium as gym
import torch
from datetime import datetime

import omni

# Debug: Check rsl_rl package structure
print("[DEBUG] Checking rsl_rl package...")
try:
    import rsl_rl

    print(f"[DEBUG] rsl_rl location: {rsl_rl.__file__}")
    print(f"[DEBUG] rsl_rl version: {rsl_rl.__version__ if hasattr(rsl_rl, '__version__') else 'unknown'}")
    print(f"[DEBUG] rsl_rl contents: {dir(rsl_rl)}")

    # Check if runners exists
    import importlib.util

    runners_spec = importlib.util.find_spec("rsl_rl.runners")
    if runners_spec:
        print(f"[DEBUG] rsl_rl.runners found at: {runners_spec.origin}")
    else:
        print("[ERROR] rsl_rl.runners module not found!")

    # Try to list what's in the rsl_rl package directory
    import os

    rsl_rl_dir = os.path.dirname(rsl_rl.__file__)
    print(f"[DEBUG] Contents of {rsl_rl_dir}:")
    for item in os.listdir(rsl_rl_dir):
        print(f"  - {item}")
except Exception as e:
    print(f"[ERROR] Failed to inspect rsl_rl: {e}")
    import traceback

    traceback.print_exc()

from rsl_rl.runners import OnPolicyRunner, DistillationRunner

_CURRENT_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _CURRENT_DIR.parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from training.utils import AzureConfigError, AzureMLContext, bootstrap_azure_ml

from isaaclab.envs import (
    DirectMARLEnv,
    DirectMARLEnvCfg,
    DirectRLEnvCfg,
    ManagerBasedRLEnvCfg,
    multi_agent_to_single_agent,
)
from isaaclab.utils.dict import print_dict
from isaaclab.utils.io import dump_pickle, dump_yaml

from isaaclab_rl.rsl_rl import RslRlBaseRunnerCfg, RslRlVecEnvWrapper

import isaaclab_tasks  # noqa: F401
from isaaclab_tasks.utils import get_checkpoint_path
from isaaclab_tasks.utils.hydra import hydra_task_config

torch.backends.cuda.matmul.allow_tf32 = True
torch.backends.cudnn.allow_tf32 = True
torch.backends.cudnn.deterministic = False
torch.backends.cudnn.benchmark = False


def _is_primary_rank(args_cli: argparse.Namespace, app_launcher: AppLauncher) -> bool:
    """Return True when current process is responsible for logging side effects."""

    if not args_cli.distributed:
        return True
    return getattr(app_launcher, "local_rank", 0) == 0


def _resolve_env_count(env_cfg: object) -> Optional[int]:
    """Best-effort extraction of the configured number of environments."""

    scene = getattr(env_cfg, "scene", None)
    if scene is not None and hasattr(scene, "num_envs"):
        return scene.num_envs
    return getattr(env_cfg, "num_envs", None)


def _collect_training_metrics(runner: object) -> dict[str, float]:
    """Extract a small set of scalar metrics from the runner when available."""

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


def _start_mlflow_run(
    *,
    context: AzureMLContext,
    experiment_name: str,
    run_name: str,
    tags: dict[str, str],
    params: dict[str, object],
) -> tuple[Optional[Any], bool]:
    """Start an MLflow run and return the module with activation state."""

    try:
        import mlflow
    except ImportError as exc:
        print(f"[WARNING] MLflow not available: {exc}")
        return None, False

    try:
        mlflow.set_tracking_uri(context.tracking_uri)
        mlflow.set_experiment(experiment_name)
        mlflow.start_run(run_name=run_name)
        if tags:
            mlflow.set_tags(tags)
        if params:
            serializable = {k: str(v) for k, v in params.items() if v is not None}
            if serializable:
                mlflow.log_params(serializable)
        print(f"[INFO] MLflow run started: experiment='{experiment_name}', run='{run_name}'")
        return mlflow, True
    except Exception as exc:  # pragma: no cover - network issues are environment specific
        print(f"[WARNING] Failed to start MLflow run: {exc}")
        return None, False


def _log_config_artifacts(mlflow_module: Optional[Any], log_dir: str) -> None:
    """Upload environment and agent configuration artifacts to MLflow."""

    if mlflow_module is None:
        return

    params_dir = Path(log_dir) / "params"
    if not params_dir.exists():
        return

    artifact_map = {
        "env.yaml": "config",
        "agent.yaml": "config",
        "env.pkl": "config",
        "agent.pkl": "config",
    }

    for relative_path, artifact_path in artifact_map.items():
        candidate = params_dir / relative_path
        if candidate.exists():
            try:
                mlflow_module.log_artifact(str(candidate), artifact_path=artifact_path)
            except Exception as exc:  # pragma: no cover - filesystem/MLflow issues
                print(f"[WARNING] Failed to log artifact {candidate}: {exc}")


def _sync_logs_to_storage(
    storage_context: Optional[Any],
    *,
    log_dir: str,
    experiment_name: str,
) -> None:
    """Upload log directory contents to Azure Storage when available."""

    if storage_context is None:
        return

    root = Path(log_dir)
    if not root.exists():
        return

    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    for file_path in root.rglob("*"):
        if not file_path.is_file():
            continue
        blob_name = f"training_logs/{experiment_name}/{timestamp}/" f"{file_path.relative_to(root).as_posix()}"
        try:
            storage_context.upload_file(
                local_path=str(file_path),
                blob_name=blob_name,
            )
        except Exception as exc:  # pragma: no cover - depends on storage environment
            print(f"[WARNING] Failed to upload log '{file_path}': {exc}")


def _register_final_model(
    *,
    context: Optional[AzureMLContext],
    model_path: str,
    model_name: str,
    tags: dict[str, str],
) -> bool:
    """Register a trained model in Azure ML if dependencies are available."""

    if context is None:
        return False

    try:
        from azure.ai.ml.entities import Model
    except ImportError as exc:  # pragma: no cover - optional dependency
        print(f"[WARNING] azure-ai-ml not available for model registration: {exc}")
        return False

    try:
        model = Model(
            name=model_name,
            path=model_path,
            type="custom_model",
            description="RSL-RL checkpoint registered via Azure ML",
            tags=tags,
        )
        context.client.models.create_or_update(model)
        print(f"[INFO] Registered final model '{model_name}' with Azure ML")
        return True
    except Exception as exc:  # pragma: no cover - backend specific failures
        print(f"[WARNING] Failed to register final model '{model_name}': {exc}")
        return False


@hydra_task_config(args_cli.task, args_cli.agent)
def main(
    env_cfg: ManagerBasedRLEnvCfg | DirectRLEnvCfg | DirectMARLEnvCfg,
    agent_cfg: RslRlBaseRunnerCfg,
):
    """Train with RSL-RL agent."""
    # override configurations with non-hydra CLI arguments
    agent_cfg = cli_args.update_rsl_rl_cfg(agent_cfg, args_cli)
    env_cfg.scene.num_envs = args_cli.num_envs if args_cli.num_envs is not None else env_cfg.scene.num_envs
    agent_cfg.max_iterations = (
        args_cli.max_iterations if args_cli.max_iterations is not None else agent_cfg.max_iterations
    )

    # set the environment seed
    # note: certain randomizations occur in the environment initialization so we set the seed here
    env_cfg.seed = agent_cfg.seed
    env_cfg.sim.device = args_cli.device if args_cli.device is not None else env_cfg.sim.device

    # multi-gpu training configuration
    if args_cli.distributed:
        env_cfg.sim.device = f"cuda:{app_launcher.local_rank}"
        agent_cfg.device = f"cuda:{app_launcher.local_rank}"

        # set seed to have diversity in different threads
        seed = agent_cfg.seed + app_launcher.local_rank
        env_cfg.seed = seed
        agent_cfg.seed = seed

    # specify directory for logging experiments
    log_root_path = os.path.join("logs", "rsl_rl", agent_cfg.experiment_name)
    log_root_path = os.path.abspath(log_root_path)
    print(f"[INFO] Logging experiment in directory: {log_root_path}")
    # specify directory for logging runs: {time-stamp}_{run_name}
    log_dir = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    # The Ray Tune workflow extracts experiment name using the logging line below, hence, do not change it (see PR #2346, comment-2819298849)
    print(f"Exact experiment name requested from command line: {log_dir}")
    if agent_cfg.run_name:
        log_dir += f"_{agent_cfg.run_name}"
    log_dir = os.path.join(log_root_path, log_dir)

    resume_path: Optional[str] = None
    if agent_cfg.resume or agent_cfg.algorithm.class_name == "Distillation":
        resume_path = get_checkpoint_path(log_root_path, agent_cfg.load_run, agent_cfg.load_checkpoint)

    if args_cli.azure_config:
        print("[WARNING] --azure_config is deprecated and ignored; provide Azure settings via environment variables.")

    azure_context: Optional[AzureMLContext] = None
    mlflow_module: Optional[Any] = None
    mlflow_run_active = False
    is_primary_process = _is_primary_rank(args_cli, app_launcher)
    experiment_name = f"rsl_rl_{agent_cfg.experiment_name}"

    if args_cli.disable_azure:
        print("[INFO] Azure integration disabled via command line")
    elif not is_primary_process:
        print("[INFO] Skipping Azure bootstrap on non-primary rank; metrics will be reported by rank 0.")
    else:
        try:
            azure_context = bootstrap_azure_ml(experiment_name=experiment_name)
            print("[INFO] Azure ML context initialized with workspace " f"'{azure_context.workspace_name}'")
        except AzureConfigError as exc:
            print(f"[WARNING] Azure ML bootstrap failed: {exc}")
        except Exception as exc:  # pragma: no cover - environment specific failures
            print(f"[WARNING] Unexpected Azure ML bootstrap failure: {exc}")

        if azure_context:
            env_count = _resolve_env_count(env_cfg)
            algorithm_name = getattr(
                getattr(agent_cfg, "algorithm", None),
                "class_name",
                getattr(agent_cfg, "class_name", "unknown"),
            )
            params = {
                "task": args_cli.task,
                "num_envs": env_count,
                "max_iterations": agent_cfg.max_iterations,
                "seed": agent_cfg.seed,
                "device": env_cfg.sim.device,
                "distributed": args_cli.distributed,
                "algorithm": algorithm_name,
                "clip_actions": agent_cfg.clip_actions,
                "resume": bool(agent_cfg.resume),
            }
            tags = {
                "entrypoint": "training/scripts/rsl_rl/train.py",
                "task": args_cli.task or "",
                "distributed": str(args_cli.distributed).lower(),
                "log_dir": log_dir,
                "azureml_workspace": azure_context.workspace_name,
            }
            if azure_context.storage:
                tags["storage_container"] = azure_context.storage.container_name

            run_name = Path(log_dir).name
            mlflow_module, mlflow_run_active = _start_mlflow_run(
                context=azure_context,
                experiment_name=experiment_name,
                run_name=run_name,
                tags=tags,
                params=params,
            )
            if mlflow_run_active and mlflow_module is not None:
                if resume_path:
                    mlflow_module.set_tag("resume_checkpoint_path", str(resume_path))
                mlflow_module.set_tag("is_primary_rank", str(is_primary_process).lower())

    storage_context = azure_context.storage if azure_context else None
    if azure_context and storage_context is None:
        print("[INFO] Azure Storage account not configured; checkpoint uploads will be skipped")

    # set the IO descriptors export flag if requested
    if isinstance(env_cfg, ManagerBasedRLEnvCfg):
        env_cfg.export_io_descriptors = args_cli.export_io_descriptors
    else:
        omni.log.warn(  # type: ignore[attr-defined]
            "IO descriptors are only supported for manager based RL environments. No IO descriptors will be exported."
        )

    # set the log directory for the environment (works for all environment types)
    env_cfg.log_dir = log_dir

    # create isaac environment
    env = gym.make(args_cli.task, cfg=env_cfg, render_mode="rgb_array" if args_cli.video else None)

    # convert to single-agent instance if required by the RL algorithm
    if isinstance(env.unwrapped, DirectMARLEnv):
        env = multi_agent_to_single_agent(env)

    # wrap for video recording
    if args_cli.video:
        video_kwargs = {
            "video_folder": os.path.join(log_dir, "videos", "train"),
            "step_trigger": lambda step: step % args_cli.video_interval == 0,
            "video_length": args_cli.video_length,
            "disable_logger": True,
        }
        print("[INFO] Recording videos during training.")
        print_dict(video_kwargs, nesting=4)
        env = gym.wrappers.RecordVideo(env, **video_kwargs)

    # wrap around environment for rsl-rl
    env = RslRlVecEnvWrapper(env, clip_actions=agent_cfg.clip_actions)

    # create runner from rsl-rl
    if agent_cfg.class_name == "OnPolicyRunner":
        runner = OnPolicyRunner(env, agent_cfg.to_dict(), log_dir=log_dir, device=agent_cfg.device)
    elif agent_cfg.class_name == "DistillationRunner":
        runner = DistillationRunner(env, agent_cfg.to_dict(), log_dir=log_dir, device=agent_cfg.device)
    else:
        raise ValueError(f"Unsupported runner class: {agent_cfg.class_name}")
    # write git state to logs
    runner.add_git_repo_to_log(__file__)
    # load the checkpoint
    if resume_path:
        print(f"[INFO]: Loading model checkpoint from: {resume_path}")
        # load previously trained model
        runner.load(resume_path)

    # dump the configuration into log-directory
    dump_yaml(os.path.join(log_dir, "params", "env.yaml"), env_cfg)
    dump_yaml(os.path.join(log_dir, "params", "agent.yaml"), agent_cfg)
    dump_pickle(os.path.join(log_dir, "params", "env.pkl"), env_cfg)
    dump_pickle(os.path.join(log_dir, "params", "agent.pkl"), agent_cfg)
    if is_primary_process and mlflow_module and mlflow_run_active:
        _log_config_artifacts(mlflow_module, log_dir)

    if is_primary_process and (mlflow_run_active or storage_context):
        original_save = runner.save

        def enhanced_save(path, *args, **kwargs):
            result = original_save(path, *args, **kwargs)

            try:
                current_iter = getattr(runner, "current_learning_iteration", 0)
                full_path = path if os.path.isabs(path) else os.path.join(log_dir, path)

                metrics = _collect_training_metrics(runner)

                if mlflow_module and mlflow_run_active:
                    for name, value in metrics.items():
                        mlflow_module.log_metric(name, value, step=current_iter)
                    if os.path.isfile(full_path):
                        mlflow_module.log_artifact(full_path, artifact_path="checkpoints")
                        mlflow_module.set_tag("last_checkpoint_path", full_path)

                blob_name = None
                if storage_context and os.path.isfile(full_path):
                    blob_name = storage_context.upload_checkpoint(
                        local_path=full_path,
                        model_name=f"{args_cli.task}_{agent_cfg.experiment_name}",
                        step=current_iter,
                    )
                    print("[INFO] Uploaded checkpoint to Azure Storage: " f"{blob_name} (iteration {current_iter})")
                if mlflow_module and mlflow_run_active and blob_name:
                    mlflow_module.set_tag("last_checkpoint_blob", blob_name)
            except Exception as exc:  # pragma: no cover - telemetry only
                print(f"[WARNING] Failed to process checkpoint for Azure/MLflow: {exc}")

            return result

        runner.save = enhanced_save
        print("[INFO] Primary rank will stream checkpoints to Azure and MLflow")

    training_outcome = "success"
    try:
        runner.learn(
            num_learning_iterations=agent_cfg.max_iterations,
            init_at_random_ep_len=True,
        )
    except Exception:
        training_outcome = "failed"
        if mlflow_module and mlflow_run_active:
            mlflow_module.set_tag("training_outcome", training_outcome)
        raise
    else:
        if mlflow_module and mlflow_run_active:
            mlflow_module.set_tag("training_outcome", training_outcome)
    finally:
        if is_primary_process:
            if storage_context:
                try:
                    _sync_logs_to_storage(
                        storage_context,
                        log_dir=log_dir,
                        experiment_name=agent_cfg.experiment_name,
                    )
                    print("[INFO] Uploaded training logs to Azure Storage")
                except Exception as exc:
                    print(f"[WARNING] Failed to upload training logs: {exc}")

            final_model_path = None
            model_candidates = list(Path(log_dir).glob("**/model_*.pt"))
            if not model_candidates:
                model_candidates = list(Path(log_dir).glob("**/policy_*.pt"))
            if model_candidates:
                final_model_path = str(max(model_candidates, key=os.path.getctime))
                print(f"[INFO] Found final model: {final_model_path}")

                if storage_context:
                    try:
                        final_blob = storage_context.upload_checkpoint(
                            local_path=final_model_path,
                            model_name=f"{args_cli.task}_{agent_cfg.experiment_name}_final",
                            step=None,
                        )
                        print("[INFO] Uploaded final model to Azure Storage: " f"{final_blob}")
                    except Exception as exc:
                        print(f"[WARNING] Failed to upload final model to Azure Storage: {exc}")

                if mlflow_module and mlflow_run_active:
                    try:
                        mlflow_module.log_artifact(final_model_path, artifact_path="checkpoints/final")
                    except Exception as exc:
                        print(f"[WARNING] Failed to log final model artifact to MLflow: {exc}")

                _register_final_model(
                    context=azure_context,
                    model_path=final_model_path,
                    model_name=f"rsl_rl_model_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}",
                    tags={
                        "task": args_cli.task or "",
                        "experiment": experiment_name,
                        "entrypoint": "training/scripts/rsl_rl/train.py",
                    },
                )

        if mlflow_module and mlflow_run_active:
            mlflow_module.end_run()
            mlflow_run_active = False

    # close the simulator
    env.close()


if __name__ == "__main__":
    # run the main function
    main()  # type: ignore[arg-type]
    # close sim app
    simulation_app.close()
