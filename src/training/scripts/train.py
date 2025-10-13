"""IsaacLab training entrypoint with Azure ML bootstrap."""

from __future__ import annotations

import argparse
import os
import importlib.util
import logging
from typing import List, Sequence

from training.utils import AzureConfigError, AzureMLContext, bootstrap_azure_ml

_LOGGER = logging.getLogger("isaaclab.train")
_REQUIRED_MODULES = {
    "azure.identity": "azure-identity>=1.13.0",
    "azure.ai.ml": "azure-ai-ml",
    "azureml.mlflow": "azureml-mlflow",
    "mlflow": "mlflow",
}


def _ensure_dependencies() -> None:
    missing: List[str] = []
    for module_name, package_name in _REQUIRED_MODULES.items():
        if importlib.util.find_spec(module_name) is None:
            missing.append(package_name)
    if missing:
        packages = ", ".join(sorted(set(missing)))
        message = (
            "Missing required Python packages for Azure ML integration: "
            f"{packages}. Install the listed packages in the training image."
        )
        raise SystemExit(message)


def _parse_args(argv: Sequence[str] | None) -> tuple[argparse.Namespace, List[str]]:
    parser = argparse.ArgumentParser(description="IsaacLab RL training entrypoint")
    parser.add_argument("--task", type=str, default=None, help="IsaacLab task identifier")
    parser.add_argument("--num_envs", type=int, default=None, help="Number of simulated environments")
    parser.add_argument("--max_iterations", type=int, default=None, help="Maximum policy iterations")
    parser.add_argument("--headless", action="store_true", help="Run without viewer")
    parser.add_argument(
        "--experiment-name",
        type=str,
        default=None,
        help="Override Azure ML experiment name. Defaults to the IsaacLab task.",
    )
    parser.add_argument(
        "--disable-mlflow",
        action="store_true",
        help="Skip MLflow configuration for dry runs",
    )
    args, remaining = parser.parse_known_args(argv)
    return args, list(remaining)


def _bootstrap(args: argparse.Namespace) -> AzureMLContext | None:
    if args.disable_mlflow:
        _LOGGER.warning("MLflow integration disabled via --disable-mlflow")
        return None

    os.environ.setdefault("MLFLOW_TRACKING_TOKEN_REFRESH_RETRIES", "3")
    os.environ.setdefault("MLFLOW_HTTP_REQUEST_TIMEOUT", "60")

    experiment_name = args.experiment_name or (f"isaaclab-{args.task}" if args.task else "isaaclab-training")
    return bootstrap_azure_ml(experiment_name=experiment_name)


def _run_training(
    args: argparse.Namespace,
    hydra_args: Sequence[str],
    context: AzureMLContext | None,
) -> None:
    try:
        from training.skrl import run_training
    except ImportError as exc:
        raise SystemExit(
            "training.skrl module is unavailable. Ensure training payload includes SKRL training code."
        ) from exc

    run_training(args=args, hydra_args=hydra_args, context=context)


def main(argv: Sequence[str] | None = None) -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(name)s | %(message)s")
    args, hydra_args = _parse_args(argv)

    _ensure_dependencies()

    try:
        context = _bootstrap(args)
    except AzureConfigError as exc:
        raise SystemExit(str(exc)) from exc

    _run_training(args=args, hydra_args=hydra_args, context=context)

if __name__ == "__main__":
    main()
