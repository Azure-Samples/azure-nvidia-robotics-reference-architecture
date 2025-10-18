"""Unified launcher for IsaacLab training and smoke-test workflows."""

from __future__ import annotations

import argparse
import importlib.util
import logging
import shutil
import sys
import tempfile
from contextlib import contextmanager
from typing import Iterator, List, Sequence

from training.utils import AzureConfigError, AzureMLContext, bootstrap_azure_ml

_LOGGER = logging.getLogger("isaaclab.launch")
_REQUIRED_MODULES = {
    "azure.identity": "azure-identity>=1.13.0",
    "azure.ai.ml": "azure-ai-ml",
    "azureml.mlflow": "azureml-mlflow",
    "mlflow": "mlflow",
}


def _optional_int(raw: str | None) -> int | None:
    if raw in (None, ""):
        return None
    return int(raw)


def _optional_str(raw: str | None) -> str | None:
    return None if raw in (None, "") else raw


def _parse_args(argv: Sequence[str] | None) -> tuple[argparse.Namespace, List[str]]:
    parser = argparse.ArgumentParser(description="IsaacLab unified launcher")
    parser.add_argument("--mode", choices=("train", "smoke-test"), default="train", help="Execution mode")
    parser.add_argument("--task", type=_optional_str, default=None, help="IsaacLab task identifier")
    parser.add_argument("--num_envs", type=_optional_int, default=None, help="Number of simulated environments")
    parser.add_argument("--max_iterations", type=_optional_int, default=None, help="Maximum policy iterations")
    parser.add_argument("--headless", action="store_true", help="Run without viewer")
    parser.add_argument(
        "--experiment-name",
        type=_optional_str,
        default=None,
        help="Override Azure ML experiment name. Defaults to the IsaacLab task.",
    )
    parser.add_argument(
        "--disable-mlflow",
        action="store_true",
        help="Skip MLflow configuration for dry runs",
    )
    parser.add_argument(
        "--checkpoint-uri",
        type=_optional_str,
        default=None,
        help="MLflow artifact URI for the checkpoint to materialize before training",
    )
    parser.add_argument(
        "--checkpoint-mode",
        type=_optional_str,
        default="from-scratch",
        help="Checkpoint handling mode (fresh is treated as from-scratch)",
    )
    parser.add_argument(
        "--register-checkpoint",
        type=_optional_str,
        default=None,
        help="Register the final checkpoint as this Azure ML model name",
    )
    args, remaining = parser.parse_known_args(argv)
    return args, list(remaining)


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


def _normalize_checkpoint_mode(value: str | None) -> str:
    if not value:
        return "from-scratch"
    normalized = value.lower()
    if normalized == "fresh":
        return "from-scratch"
    if normalized in {"from-scratch", "warm-start", "resume"}:
        return normalized
    raise SystemExit(f"Unsupported checkpoint mode: {value}")


@contextmanager
def _materialized_checkpoint(artifact_uri: str | None) -> Iterator[str | None]:
    if not artifact_uri:
        yield None
        return

    try:
        import mlflow
    except ImportError as exc:
        raise SystemExit("mlflow is required to download checkpoint artifacts") from exc

    download_root = tempfile.mkdtemp(prefix="skrl-ckpt-")
    try:
        local_path = mlflow.artifacts.download_artifacts(artifact_uri=artifact_uri, dst_path=download_root)
    except Exception as exc:
        shutil.rmtree(download_root, ignore_errors=True)
        raise SystemExit(f"Failed to download checkpoint from {artifact_uri}: {exc}") from exc

    try:
        _LOGGER.info("Checkpoint artifact %s materialized at %s", artifact_uri, local_path)
        yield local_path
    finally:
        shutil.rmtree(download_root, ignore_errors=True)


def _bootstrap(args: argparse.Namespace) -> tuple[AzureMLContext | None, str | None]:
    if args.disable_mlflow:
        _LOGGER.warning("MLflow integration disabled via --disable-mlflow")
        return None, None

    experiment_name = args.experiment_name or (f"isaaclab-{args.task}" if args.task else "isaaclab-training")
    context = bootstrap_azure_ml(experiment_name=experiment_name)
    _LOGGER.info("MLflow context ready: %s", {"experiment": experiment_name, "tracking_uri": context.tracking_uri})
    return context, experiment_name


def _run_training(
    args: argparse.Namespace,
    hydra_args: Sequence[str],
    context: AzureMLContext | None,
) -> None:
    try:
        from training.scripts import skrl_training
    except ImportError as exc:
        raise SystemExit(
            "training.scripts.skrl_training module is unavailable. Ensure training payload includes SKRL training code."
        ) from exc

    skrl_training.run_training(args=args, hydra_args=hydra_args, context=context)


def _run_smoke_test() -> None:
    _LOGGER.info("Running Azure connectivity smoke test")
    from training.scripts import smoke_test_azure

    smoke_test_azure.main([])


def _validate_mlflow_flags(args: argparse.Namespace) -> None:
    if args.disable_mlflow and args.checkpoint_uri:
        raise SystemExit("--checkpoint-uri requires MLflow integration; remove --disable-mlflow")
    if args.disable_mlflow and args.register_checkpoint:
        raise SystemExit("--register-checkpoint requires MLflow integration; remove --disable-mlflow")


def main(argv: Sequence[str] | None = None) -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(name)s | %(message)s")
    args, hydra_args = _parse_args(argv if argv is not None else sys.argv[1:])

    args.checkpoint = None

    cli_state = {"parsed": dict(vars(args)), "hydra": list(hydra_args)}
    _LOGGER.info("Launcher arguments: %s", cli_state)

    _ensure_dependencies()

    if args.mode == "smoke-test":
        _run_smoke_test()
        return

    args.checkpoint_mode = _normalize_checkpoint_mode(args.checkpoint_mode)
    _validate_mlflow_flags(args)

    try:
        context, experiment_name = _bootstrap(args)
    except AzureConfigError as exc:
        raise SystemExit(str(exc)) from exc

    with _materialized_checkpoint(args.checkpoint_uri) as checkpoint_path:
        if checkpoint_path:
            args.checkpoint = checkpoint_path
        _LOGGER.info(
            "Resolved checkpoint parameters: %s",
            {
                "mode": args.checkpoint_mode,
                "materialized_path": args.checkpoint,
                "source_uri": args.checkpoint_uri,
            },
        )

        run_context = {
            "mode": args.mode,
            "experiment": experiment_name,
            "checkpoint_path": args.checkpoint,
        }
        _LOGGER.info("Entering SKRL training: %s", run_context)
        try:
            _run_training(args=args, hydra_args=hydra_args, context=context)
        except Exception:
            _LOGGER.exception("SKRL training failed: %s", run_context)
            raise
        else:
            _LOGGER.debug("Completed SKRL training: %s", run_context)


if __name__ == "__main__":
    main()
