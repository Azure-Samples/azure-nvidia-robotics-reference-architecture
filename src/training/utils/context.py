"""Azure ML bootstrap helpers for IsaacLab training entrypoints."""

from __future__ import annotations

import os
from dataclasses import dataclass

from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential
import mlflow

from training.utils.env import require_env, set_env_defaults


class AzureConfigError(RuntimeError):
    """Raised when required Azure ML configuration is unavailable."""


@dataclass(frozen=True)
class AzureMLContext:
    client: MLClient
    tracking_uri: str
    workspace_name: str


def _build_credential() -> DefaultAzureCredential:
    return DefaultAzureCredential(
        managed_identity_client_id=os.environ.get("AZURE_CLIENT_ID"),
        authority=os.environ.get("AZURE_AUTHORITY_HOST"),
    )


def bootstrap_azure_ml(
    *,
    experiment_name: str,
) -> AzureMLContext:
    subscription_id = require_env("AZURE_SUBSCRIPTION_ID", error_type=AzureConfigError)
    resource_group = require_env("AZURE_RESOURCE_GROUP", error_type=AzureConfigError)
    workspace_name = require_env("AZUREML_WORKSPACE_NAME", error_type=AzureConfigError)

    set_env_defaults(
        {
            "MLFLOW_TRACKING_TOKEN_REFRESH_RETRIES": "3",
            "MLFLOW_HTTP_REQUEST_TIMEOUT": "60",
        }
    )

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
