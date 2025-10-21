"""Script to train RL agent with RSL-RL."""

"""Launch Isaac Sim Simulator first."""

import argparse
import sys

import os
from pathlib import Path

from isaaclab.app import AppLauncher

# local imports
import cli_args  # isort: skip

# add argparse arguments
parser = argparse.ArgumentParser(description="Train an RL agent with RSL-RL.")
parser.add_argument(
    "--video", action="store_true", default=False, help="Record videos during training."
)
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
parser.add_argument(
    "--num_envs", type=int, default=None, help="Number of environments to simulate."
)
parser.add_argument("--task", type=str, default=None, help="Name of the task.")
parser.add_argument(
    "--agent",
    type=str,
    default="rsl_rl_cfg_entry_point",
    help="Name of the RL agent configuration entry point.",
)
parser.add_argument(
    "--seed", type=int, default=None, help="Seed used for the environment"
)
parser.add_argument(
    "--max_iterations", type=int, default=None, help="RL Policy training iterations."
)
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
import yaml
from datetime import datetime

import omni

# Debug: Check rsl_rl package structure
print("[DEBUG] Checking rsl_rl package...")
try:
    import rsl_rl

    print(f"[DEBUG] rsl_rl location: {rsl_rl.__file__}")
    print(
        f"[DEBUG] rsl_rl version: {rsl_rl.__version__ if hasattr(rsl_rl, '__version__') else 'unknown'}"
    )
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

# Azure integration imports
_AZURE_IMPORT_ERROR: Exception | None = None

_CURRENT_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _CURRENT_DIR.parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

try:
    from scripts.rsl_rl.azure_integration import AzureIntegrationManager

    AZURE_AVAILABLE = True
except ImportError as exc:  # noqa: F841 - used for logging later
    AzureIntegrationManager = None
    AZURE_AVAILABLE = False
    _AZURE_IMPORT_ERROR = exc

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


def _load_azure_config(config_path=None) -> dict:
    """Load Azure configuration from file or environment variables.

    Args:
        config_path: Optional path to YAML configuration file

    Returns:
        Dictionary with Azure configuration
    """
    config = {"enabled": False}

    # Try to load from file first
    if config_path and os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                config = yaml.safe_load(f)
            print(f"[INFO] Loaded Azure config from: {config_path}")
            return config
        except Exception as e:
            print(f"[WARNING] Failed to load Azure config from {config_path}: {e}")

    # Try to find default config file
    default_config_paths = [
        "scripts/azure_config.yaml",
        "scripts/rsl_rl/config/azure_config.yaml",
        "azure_config.yaml",
        "config/azure_config.yaml",
    ]

    for path in default_config_paths:
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    config = yaml.safe_load(f)
                print(f"[INFO] Loaded Azure config from: {path}")
                return config
            except Exception as e:
                print(f"[WARNING] Failed to load Azure config from {path}: {e}")
                continue

    # Fallback to environment variables
    env_config = {
        "enabled": os.getenv("AZURE_INTEGRATION_ENABLED", "false").lower() == "true",
        "storage": {
            "enabled": True,
            "account_name": os.getenv("AZURE_STORAGE_ACCOUNT_NAME"),
            "container_name": os.getenv(
                "AZURE_STORAGE_CONTAINER_NAME", "isaaclab-training-logs"
            ),
            "upload_interval": int(os.getenv("AZURE_STORAGE_UPLOAD_INTERVAL", "300")),
            "local_backup": os.getenv("AZURE_STORAGE_LOCAL_BACKUP", "true").lower()
            == "true",
            "background_sync": os.getenv(
                "AZURE_STORAGE_BACKGROUND_SYNC", "true"
            ).lower()
            == "true",
        },
        "ml": {
            "enabled": True,
            "subscription_id": os.getenv("AZURE_SUBSCRIPTION_ID"),
            "resource_group": os.getenv("AZURE_RESOURCE_GROUP"),
            "workspace_name": os.getenv("AZURE_ML_WORKSPACE_NAME"),
        },
        "auth": {
            "method": "service_principal",
            "tenant_id": os.getenv("AZURE_TENANT_ID"),
        },
    }

    # Check if we have minimum required environment variables
    required_vars = [
        "AZURE_STORAGE_ACCOUNT_NAME",
        "AZURE_SUBSCRIPTION_ID",
        "AZURE_RESOURCE_GROUP",
        "AZURE_ML_WORKSPACE_NAME",
    ]
    if all(os.getenv(var) for var in required_vars):
        env_config["enabled"] = True
        print("[INFO] Using Azure config from environment variables")
        return env_config
    else:
        print(
            "[INFO] Azure integration not configured (missing environment variables or config file)"
        )
        return {"enabled": False}


@hydra_task_config(args_cli.task, args_cli.agent)
def main(
    env_cfg: ManagerBasedRLEnvCfg | DirectRLEnvCfg | DirectMARLEnvCfg,
    agent_cfg: RslRlBaseRunnerCfg,
):
    """Train with RSL-RL agent."""
    # override configurations with non-hydra CLI arguments
    agent_cfg = cli_args.update_rsl_rl_cfg(agent_cfg, args_cli)
    env_cfg.scene.num_envs = (
        args_cli.num_envs if args_cli.num_envs is not None else env_cfg.scene.num_envs
    )
    agent_cfg.max_iterations = (
        args_cli.max_iterations
        if args_cli.max_iterations is not None
        else agent_cfg.max_iterations
    )

    # set the environment seed
    # note: certain randomizations occur in the environment initialization so we set the seed here
    env_cfg.seed = agent_cfg.seed
    env_cfg.sim.device = (
        args_cli.device if args_cli.device is not None else env_cfg.sim.device
    )

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

    # Initialize Azure integration
    azure_manager = None
    if not args_cli.disable_azure and AZURE_AVAILABLE:
        try:
            # Load Azure configuration
            azure_config = _load_azure_config(args_cli.azure_config)
            if azure_config and azure_config.get("enabled", True):
                azure_manager = AzureIntegrationManager(azure_config)

                storage_available = (
                    azure_manager.storage_manager is not None
                    and azure_manager.storage_manager.is_available()
                )
                ml_available = (
                    azure_manager.ml_manager is not None
                    and azure_manager.ml_manager.is_available()
                )
                print(
                    "[DEBUG] Azure connectivity status: "
                    f"storage_available={storage_available}, ml_available={ml_available}"
                )

                if azure_manager.is_available():
                    print("[INFO] Azure integration initialized successfully")

                    # Setup experiment in Azure ML
                    experiment_name = f"rsl_rl_{agent_cfg.experiment_name}"
                    run_name = f"{log_dir.split('/')[-1]}_{args_cli.task}"

                    # Prepare training parameters for logging
                    training_params = {
                        "task": args_cli.task,
                        "num_envs": env_cfg.scene.num_envs,
                        "max_iterations": agent_cfg.max_iterations,
                        "seed": agent_cfg.seed,
                        "device": env_cfg.sim.device,
                        "distributed": args_cli.distributed,
                        "algorithm": (
                            agent_cfg.algorithm.class_name
                            if hasattr(agent_cfg, "algorithm")
                            else "unknown"
                        ),
                    }

                    # Add agent-specific parameters if available
                    if hasattr(agent_cfg, "to_dict"):
                        try:
                            agent_dict = agent_cfg.to_dict()
                            training_params.update(
                                {
                                    f"agent_{k}": str(v)
                                    for k, v in agent_dict.items()
                                    if k not in ["device", "max_iterations", "seed"]
                                    and not isinstance(v, dict)
                                }
                            )
                        except Exception as e:
                            print(f"[WARNING] Could not extract agent parameters: {e}")

                    if azure_manager.setup_experiment(
                        experiment_name, run_name, training_params
                    ):
                        current_run = None
                        if (
                            azure_manager.ml_manager is not None
                            and azure_manager.ml_manager.current_run is not None
                        ):
                            current_run = (
                                azure_manager.ml_manager.current_run.info.run_id
                                if hasattr(azure_manager.ml_manager.current_run, "info")
                                else None
                            )
                        print(
                            "[INFO] Azure ML experiment ready: "
                            f"experiment='{experiment_name}', run='{run_name}', run_id='{current_run}'"
                        )
                    else:
                        print(
                            "[WARNING] Azure ML experiment setup failed; metrics will not reach AML"
                        )
                else:
                    print(
                        "[WARNING] Azure services not available, continuing without Azure integration"
                    )
                    azure_manager = None
            else:
                print("[INFO] Azure integration disabled by configuration")
        except Exception as e:
            print(f"[WARNING] Failed to initialize Azure integration: {e}")
            azure_manager = None
    elif args_cli.disable_azure:
        print("[INFO] Azure integration disabled via command line")
    elif not AZURE_AVAILABLE:
        detail = f" ImportError: {_AZURE_IMPORT_ERROR}" if _AZURE_IMPORT_ERROR else ""
        print(
            "[INFO] Azure integration not available (modules not imported)." f"{detail}"
        )
        print(
            "[INFO] Install `azure-ai-ml`, `azureml-mlflow`, and `mlflow` as described in "
            "https://learn.microsoft.com/en-us/azure/machine-learning/how-to-use-mlflow-configure-tracking"
        )

    # set the IO descriptors export flag if requested
    if isinstance(env_cfg, ManagerBasedRLEnvCfg):
        env_cfg.export_io_descriptors = args_cli.export_io_descriptors
    else:
        omni.log.warn(
            "IO descriptors are only supported for manager based RL environments. No IO descriptors will be exported."
        )

    # set the log directory for the environment (works for all environment types)
    env_cfg.log_dir = log_dir

    # create isaac environment
    env = gym.make(
        args_cli.task, cfg=env_cfg, render_mode="rgb_array" if args_cli.video else None
    )

    # convert to single-agent instance if required by the RL algorithm
    if isinstance(env.unwrapped, DirectMARLEnv):
        env = multi_agent_to_single_agent(env)

    # save resume path before creating a new log_dir
    if agent_cfg.resume or agent_cfg.algorithm.class_name == "Distillation":
        resume_path = get_checkpoint_path(
            log_root_path, agent_cfg.load_run, agent_cfg.load_checkpoint
        )

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
        runner = OnPolicyRunner(
            env, agent_cfg.to_dict(), log_dir=log_dir, device=agent_cfg.device
        )
    elif agent_cfg.class_name == "DistillationRunner":
        runner = DistillationRunner(
            env, agent_cfg.to_dict(), log_dir=log_dir, device=agent_cfg.device
        )
    else:
        raise ValueError(f"Unsupported runner class: {agent_cfg.class_name}")
    # write git state to logs
    runner.add_git_repo_to_log(__file__)
    # load the checkpoint
    if agent_cfg.resume or agent_cfg.algorithm.class_name == "Distillation":
        print(f"[INFO]: Loading model checkpoint from: {resume_path}")
        # load previously trained model
        runner.load(resume_path)

    # dump the configuration into log-directory
    dump_yaml(os.path.join(log_dir, "params", "env.yaml"), env_cfg)
    dump_yaml(os.path.join(log_dir, "params", "agent.yaml"), agent_cfg)
    dump_pickle(os.path.join(log_dir, "params", "env.pkl"), env_cfg)
    dump_pickle(os.path.join(log_dir, "params", "agent.pkl"), agent_cfg)

    # Setup checkpoint tracking callback if Azure is available
    if azure_manager is not None:
        # Monkey patch the runner's save method to track checkpoints
        original_save = runner.save

        def enhanced_save(path, *args, **kwargs):
            """Enhanced save method that tracks checkpoints to Azure."""
            # Call original save method
            result = original_save(path, *args, **kwargs)

            try:
                # Only log checkpoints from main process in distributed training
                if not args_cli.distributed or (
                    hasattr(app_launcher, "local_rank") and app_launcher.local_rank == 0
                ):
                    # Get current iteration from runner
                    current_iter = getattr(runner, "current_learning_iteration", 0)

                    # Get current metrics if available
                    metrics = {}
                    if hasattr(runner, "alg") and hasattr(runner.alg, "storage"):
                        try:
                            # Extract metrics from algorithm storage
                            storage = runner.alg.storage
                            metrics = {
                                "mean_reward": float(storage.advantages.mean()),
                                "mean_value": float(storage.values.mean()),
                            }

                            # Add learning statistics if available
                            if hasattr(runner.alg, "learning_rate"):
                                metrics["learning_rate"] = float(
                                    runner.alg.learning_rate
                                )
                        except Exception as e:
                            print(f"[DEBUG] Could not extract storage metrics: {e}")

                    # Try to get metrics from writer
                    if hasattr(runner, "writer") and hasattr(runner.writer, "writer"):
                        try:
                            # TensorBoard writer - try to get recent scalars
                            tb_writer = runner.writer.writer
                            if hasattr(tb_writer, "scalar_dict"):
                                metrics.update(
                                    {
                                        k: float(v)
                                        for k, v in tb_writer.scalar_dict.items()
                                        if isinstance(v, (int, float))
                                    }
                                )
                        except Exception as e:
                            print(f"[DEBUG] Could not extract writer metrics: {e}")

                    # Log checkpoint to Azure
                    model_name = f"{args_cli.task}_{agent_cfg.experiment_name}"

                    # Construct full path if relative
                    full_path = (
                        path if os.path.isabs(path) else os.path.join(log_dir, path)
                    )

                    azure_manager.log_checkpoint(
                        full_path, model_name, current_iter, metrics
                    )

                    aml_state = (
                        "available"
                        if (
                            azure_manager.ml_manager is not None
                            and azure_manager.ml_manager.is_available()
                        )
                        else "unavailable"
                    )
                    print(
                        "[INFO] Logged checkpoint to Azure: "
                        f"{full_path} (iteration {current_iter}); AML logging {aml_state}"
                    )

                    # Also log metrics to Azure ML if available
                    if (
                        metrics
                        and azure_manager.ml_manager
                        and azure_manager.ml_manager.is_available()
                    ):
                        azure_manager.log_training_metrics(metrics, current_iter)

            except Exception as e:
                print(f"[WARNING] Failed to log checkpoint to Azure: {e}")
                import traceback

                traceback.print_exc()

            return result

        runner.save = enhanced_save
        print("[INFO] Enhanced checkpoint tracking enabled for Azure integration")

        # Also patch the learn method to log metrics periodically
        if hasattr(runner, "learn"):
            original_learn = runner.learn

            def enhanced_learn(*args, **kwargs):
                """Enhanced learn method that logs metrics to Azure ML."""
                # Store reference to azure_manager in runner for access during training
                runner._azure_manager = azure_manager
                runner._azure_log_interval = 10  # Log every 10 iterations

                return original_learn(*args, **kwargs)

            runner.learn = enhanced_learn
            print("[INFO] Enhanced metrics logging enabled for Azure integration")

    # run training
    runner.learn(
        num_learning_iterations=agent_cfg.max_iterations, init_at_random_ep_len=True
    )

    # Finalize Azure integration after training
    if azure_manager is not None:
        try:
            # Sync final logs to Azure Storage
            azure_manager.sync_training_logs(log_dir, agent_cfg.experiment_name)

            # Find and register final model if it exists
            final_model_path = None
            model_files = list(Path(log_dir).glob("**/model_*.pt"))
            if not model_files:
                model_files = list(Path(log_dir).glob("**/policy_*.pt"))
            if model_files:
                # Use the most recent model file
                final_model_path = str(max(model_files, key=os.path.getctime))
                print(f"[INFO] Found final model: {final_model_path}")

            azure_manager.finalize_training(final_model_path)
            print("[INFO] Azure integration finalized successfully")

        except Exception as e:
            print(f"[WARNING] Failed to finalize Azure integration: {e}")

    # close the simulator
    env.close()


if __name__ == "__main__":
    # run the main function
    main()
    # close sim app
    simulation_app.close()
