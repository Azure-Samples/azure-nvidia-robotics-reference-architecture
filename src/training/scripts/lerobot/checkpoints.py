"""Checkpoint upload and model registration for LeRobot training."""

from __future__ import annotations

import os
from pathlib import Path

EXIT_SUCCESS = 0


def upload_checkpoint_via_mlflow(
    run: "Any",
    checkpoint_path: Path,
    checkpoint_name: str,
    *,
    source: str = "osmo-lerobot-training",
) -> bool:
    """Upload a checkpoint directory as an MLflow artifact and register as a model.

    Args:
        run: Active MLflow run object.
        checkpoint_path: Local path to checkpoint directory.
        checkpoint_name: Identifier for the checkpoint (e.g., "005000").
        source: Source tag value for provenance tracking.

    Returns:
        True if registration succeeded.
    """
    import mlflow

    try:
        job_name = os.environ.get("JOB_NAME", "lerobot-training")
        policy_type = os.environ.get("POLICY_TYPE", "act")
        register_name = os.environ.get("REGISTER_CHECKPOINT", "") or job_name
        model_name = register_name.replace("_", "-")

        artifact_path = f"checkpoints/{checkpoint_name}"
        mlflow.log_artifacts(str(checkpoint_path), artifact_path)
        model_uri = f"runs:/{run.info.run_id}/{artifact_path}"
        mlflow.set_tag(f"checkpoint_{checkpoint_name}_artifact", artifact_path)

        result = mlflow.register_model(
            model_uri=model_uri,
            name=model_name,
            tags={
                "framework": "lerobot",
                "policy_type": policy_type,
                "job_name": job_name,
                "checkpoint": checkpoint_name,
                "source": source,
            },
        )
        print(f"[MLflow] Checkpoint registered: {result.name} v{result.version}")
        return True
    except Exception as exc:
        print(f"[MLflow] Failed to register checkpoint {checkpoint_name}: {exc}")
        return False


def upload_new_checkpoints(
    run: "Any",
    output_dir: Path,
    uploaded: set[str],
    *,
    source: str = "osmo-lerobot-training",
) -> None:
    """Scan for new checkpoint directories and upload via MLflow.

    Args:
        run: Active MLflow run object.
        output_dir: Training output directory containing checkpoints/.
        uploaded: Set of already-uploaded checkpoint names (mutated in place).
        source: Source tag value for provenance tracking.
    """
    checkpoints_dir = output_dir / "checkpoints"
    if not checkpoints_dir.exists():
        return

    for ckpt_dir in checkpoints_dir.iterdir():
        if ckpt_dir.is_dir() and ckpt_dir.name not in uploaded:
            pretrained_dir = ckpt_dir / "pretrained_model"
            if pretrained_dir.exists() and (pretrained_dir / "model.safetensors").exists():
                print(f"[MLflow] Uploading checkpoint: {ckpt_dir.name}")
                if upload_checkpoint_via_mlflow(run, pretrained_dir, ckpt_dir.name, source=source):
                    uploaded.add(ckpt_dir.name)


def register_final_checkpoint() -> int:
    """Register the latest checkpoint to Azure ML model registry.

    Reads configuration from environment variables:
        REGISTER_CHECKPOINT: Model name for registration.
        OUTPUT_DIR: Training output directory.
        MLFLOW_TRACKING_URI: MLflow tracking URI.
        MLFLOW_EXPERIMENT_NAME: MLflow experiment name.

    Returns:
        Exit code (0 on success).
    """
    import mlflow

    register_name = os.environ.get("REGISTER_CHECKPOINT", "")
    if not register_name:
        return EXIT_SUCCESS

    output_dir = Path(os.environ.get("OUTPUT_DIR", "/workspace/outputs/train"))
    job_name = os.environ.get("JOB_NAME", "lerobot-training")
    policy_type = os.environ.get("POLICY_TYPE", "act")

    checkpoint_dirs = sorted(
        output_dir.glob("checkpoints/*"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )

    if not checkpoint_dirs:
        pretrained_dir = output_dir / "pretrained_model"
        if pretrained_dir.exists():
            checkpoint_path = pretrained_dir
            checkpoint_name = "last"
        else:
            print(f"[WARNING] No checkpoints found in {output_dir}")
            return EXIT_SUCCESS
    else:
        checkpoint_path = checkpoint_dirs[0] / "pretrained_model"
        checkpoint_name = checkpoint_dirs[0].name
        if not checkpoint_path.exists():
            checkpoint_path = checkpoint_dirs[0]

    print(f"[INFO] Registering checkpoint from: {checkpoint_path}")
    print(f"[INFO] Model name: {register_name}")

    tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", "")
    if tracking_uri:
        mlflow.set_tracking_uri(tracking_uri)

    experiment_name = os.environ.get("MLFLOW_EXPERIMENT_NAME", "") or f"lerobot-{policy_type}-{job_name}"
    mlflow.set_experiment(experiment_name)

    try:
        with mlflow.start_run(run_name=f"{job_name}-register") as run:
            artifact_path = f"checkpoints/{checkpoint_name}"
            mlflow.log_artifacts(str(checkpoint_path), artifact_path)
            model_uri = f"runs:/{run.info.run_id}/{artifact_path}"

            result = mlflow.register_model(
                model_uri=model_uri,
                name=register_name,
                tags={
                    "framework": "lerobot",
                    "policy_type": policy_type,
                    "job_name": job_name,
                    "checkpoint": checkpoint_name,
                    "source": "osmo-workflow",
                },
            )
            print(f"[INFO] Model registered: {result.name} (version: {result.version})")
    except Exception as exc:
        print(f"[ERROR] Failed to register checkpoint: {exc}")
        import traceback

        traceback.print_exc()

    return EXIT_SUCCESS


def upload_checkpoints_to_azure_ml() -> int:
    """Upload all checkpoints to Azure ML model registry (non-MLflow path).

    Used by the azure-data workflow as a fallback when checkpoints weren't
    uploaded during training.

    Returns:
        Exit code (0 on success).
    """
    subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID", "")
    resource_group = os.environ.get("AZURE_RESOURCE_GROUP", "")
    workspace_name = os.environ.get("AZUREML_WORKSPACE_NAME", "")

    if not all([subscription_id, resource_group, workspace_name]):
        return EXIT_SUCCESS

    try:
        from azure.ai.ml import MLClient
        from azure.ai.ml.constants import AssetTypes
        from azure.ai.ml.entities import Model
        from azure.identity import DefaultAzureCredential
    except ImportError:
        print("[AzureML] azure-ai-ml not available, skipping checkpoint upload")
        return EXIT_SUCCESS

    output_dir = Path(os.environ.get("OUTPUT_DIR", "/workspace/outputs/train"))
    job_name = os.environ.get("JOB_NAME", "lerobot-training")
    policy_type = os.environ.get("POLICY_TYPE", "act")
    register_name = os.environ.get("REGISTER_CHECKPOINT", "") or job_name

    checkpoints_dir = output_dir / "checkpoints"
    if not checkpoints_dir.exists():
        print("[AzureML] No checkpoints directory found, skipping upload")
        return EXIT_SUCCESS

    try:
        credential = DefaultAzureCredential(
            managed_identity_client_id=os.environ.get("AZURE_CLIENT_ID"),
            authority=os.environ.get("AZURE_AUTHORITY_HOST"),
        )
        client = MLClient(
            credential=credential,
            subscription_id=subscription_id,
            resource_group_name=resource_group,
            workspace_name=workspace_name,
        )

        uploaded = 0
        for ckpt_dir in sorted(checkpoints_dir.iterdir()):
            if not ckpt_dir.is_dir():
                continue
            pretrained = ckpt_dir / "pretrained_model"
            checkpoint_path = pretrained if pretrained.exists() else ckpt_dir

            if not (checkpoint_path / "model.safetensors").exists():
                continue

            model_name = register_name.replace("_", "-")
            model = Model(
                path=str(checkpoint_path),
                name=model_name,
                description=(f"LeRobot {policy_type} policy from job: {job_name} " f"(checkpoint {ckpt_dir.name})"),
                type=AssetTypes.CUSTOM_MODEL,
                tags={
                    "framework": "lerobot",
                    "policy_type": policy_type,
                    "job_name": job_name,
                    "checkpoint": ckpt_dir.name,
                    "source": "osmo-azure-data-training",
                },
            )
            registered = client.models.create_or_update(model)
            print(f"[AzureML] Registered: {registered.name} " f"v{registered.version} ({ckpt_dir.name})")
            uploaded += 1

        if uploaded == 0:
            print("[AzureML] No valid checkpoints found to upload")
        else:
            print(f"[AzureML] Uploaded {uploaded} checkpoint(s) to Azure ML")

    except Exception as exc:
        print(f"[AzureML] Checkpoint upload failed: {exc}")
        import traceback

        traceback.print_exc()

    return EXIT_SUCCESS
