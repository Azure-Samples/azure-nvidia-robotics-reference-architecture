"""Azure ML bootstrap helpers for IsaacLab training entrypoints."""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Optional, TYPE_CHECKING

from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential
import mlflow  # type: ignore[import-not-found]


if TYPE_CHECKING:  # pragma: no cover - optional dependency import guard
    from azure.storage.blob import BlobServiceClient


class AzureConfigError(RuntimeError):
    """Raised when required Azure ML configuration is unavailable."""


@dataclass(frozen=True)
class AzureStorageContext:
    blob_client: "BlobServiceClient"
    container_name: str

    def upload_file(self, *, local_path: str, blob_name: str) -> str:
        file_path = Path(local_path)
        if not file_path.is_file():
            raise FileNotFoundError(f"Checkpoint file not found: {local_path}")

        blob = self.blob_client.get_blob_client(
            container=self.container_name,
            blob=blob_name,
        )
        with file_path.open("rb") as data_stream:
            blob.upload_blob(data_stream, overwrite=True)
        return blob_name

    def upload_checkpoint(
        self,
        *,
        local_path: str,
        model_name: str,
        step: Optional[int] = None,
    ) -> str:
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        file_path = Path(local_path)
        suffix = file_path.suffix or ""
        step_segment = f"_step_{step}" if step is not None else ""
        blob_name = f"checkpoints/{model_name}/{timestamp}{step_segment}{suffix}"
        return self.upload_file(local_path=local_path, blob_name=blob_name)


@dataclass(frozen=True)
class AzureMLContext:
    client: Any
    tracking_uri: str
    workspace_name: str
    storage: Optional[AzureStorageContext] = None


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise AzureConfigError(
            f"Environment variable {name} is required for Azure ML bootstrap"
        )
    return value


def _optional_env(name: str) -> Optional[str]:
    value = os.environ.get(name)
    return value or None


def _build_credential() -> Any:
    try:
        from training.scripts.rsl_rl.utils.auth_helpers import AzureAuthenticator
    except ImportError:
        return DefaultAzureCredential(
            managed_identity_client_id=_optional_env("AZURE_CLIENT_ID"),
            authority=_optional_env("AZURE_AUTHORITY_HOST"),
        )

    credential = AzureAuthenticator().get_credential()
    if credential is None:
        raise AzureConfigError("Failed to obtain Azure credential for ML bootstrap")
    return credential


def _build_storage_context(credential: Any) -> Optional[AzureStorageContext]:
    account_name = _optional_env("AZURE_STORAGE_ACCOUNT_NAME")
    if not account_name:
        return None

    try:
        from azure.core.exceptions import AzureError, ResourceExistsError
        from azure.storage.blob import BlobServiceClient
    except ImportError as exc:  # pragma: no cover - optional dependency guard
        raise AzureConfigError(
            "azure-storage-blob is required to upload checkpoints. Install the package or unset AZURE_STORAGE_ACCOUNT_NAME."
        ) from exc

    container_name = (
        _optional_env("AZURE_STORAGE_CONTAINER_NAME") or "isaaclab-training-logs"
    )
    account_url = f"https://{account_name}.blob.core.windows.net/"

    try:
        blob_client = BlobServiceClient(account_url=account_url, credential=credential)
        container_client = blob_client.get_container_client(container_name)
        try:
            container_client.create_container()
        except ResourceExistsError:
            pass
        return AzureStorageContext(
            blob_client=blob_client, container_name=container_name
        )
    except AzureError as exc:
        raise AzureConfigError(
            f"Failed to initialize Azure Storage container '{container_name}' in account '{account_name}': {exc}"
        ) from exc


def bootstrap_azure_ml(
    *,
    experiment_name: str,
) -> AzureMLContext:
    subscription_id = _require_env("AZURE_SUBSCRIPTION_ID")
    resource_group = _require_env("AZURE_RESOURCE_GROUP")
    workspace_name = _require_env("AZUREML_WORKSPACE_NAME")

    credential = _build_credential()

    client = MLClient(
        credential=credential,
        subscription_id=subscription_id,
        resource_group_name=resource_group,
        workspace_name=workspace_name,
    )

    workspace = client.workspaces.get(workspace_name)
    tracking_uri = getattr(workspace, "mlflow_tracking_uri", None)
    if not tracking_uri:
        raise AzureConfigError(
            "Azure ML workspace does not expose an MLflow tracking URI"
        )

    mlflow.set_tracking_uri(tracking_uri)
    if experiment_name:
        mlflow.set_experiment(experiment_name)

    storage_context = _build_storage_context(credential)

    return AzureMLContext(
        client=client,
        tracking_uri=tracking_uri,
        workspace_name=workspace_name,
        storage=storage_context,
    )
