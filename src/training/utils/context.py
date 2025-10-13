"""Azure ML bootstrap helpers for IsaacLab training entrypoints."""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any

from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential
import mlflow


class AzureConfigError(RuntimeError):
    """Raised when required Azure ML configuration is unavailable."""


@dataclass(frozen=True)
class AzureMLContext:
    client: Any
    tracking_uri: str
    workspace_name: str


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise AzureConfigError(f"Environment variable {name} is required for Azure ML bootstrap")
    return value


def _build_credential() -> DefaultAzureCredential:
    return DefaultAzureCredential(
        managed_identity_client_id=os.environ.get("AZURE_CLIENT_ID"),
        authority=os.environ.get("AZURE_AUTHORITY_HOST"),
    )


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
    tracking_uri = workspace.mlflow_tracking_uri
    if not tracking_uri:
        raise AzureConfigError("Azure ML workspace does not expose an MLflow tracking URI")

    mlflow.set_tracking_uri(tracking_uri)
    if experiment_name:
        mlflow.set_experiment(experiment_name)

    return AzureMLContext(client=client, tracking_uri=tracking_uri, workspace_name=workspace_name)
