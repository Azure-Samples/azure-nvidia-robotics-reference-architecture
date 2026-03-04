---
name: osmo-lerobot-training
description: 'Submit, monitor, and analyze LeRobot imitation learning training jobs on OSMO with Azure ML MLflow integration - Brought to you by microsoft/azure-nvidia-robotics-reference-architecture'
---

# OSMO LeRobot Training

Submit, monitor, and analyze LeRobot behavioral cloning training workflows on the OSMO platform. Covers the full lifecycle: job submission, log streaming, Azure ML metric retrieval, and training summary generation.

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| `osmo` CLI | Workflow submission and monitoring |
| `az` CLI | Azure authentication |
| `terraform` | Infrastructure output resolution |
| `zip`, `base64` | Training payload packaging |
| Python 3.11+ with `azure-ai-ml`, `mlflow` | Metric retrieval from Azure ML |

Authentication must be configured before any OSMO or Azure ML operations:

```bash
# Azure login (required for ML metrics)
az login

# OSMO login (required for workflow operations)
osmo login <service-url> --method dev --username guest
```

## Quick Start

Submit a LeRobot ACT training job with defaults:

```bash
scripts/submit-osmo-lerobot-training.sh -d lerobot/aloha_sim_insertion_human
```

## Parameters Reference

### Submission Script Parameters

| Parameter | Flag | Default | Description |
|-----------|------|---------|-------------|
| Dataset repo ID | `-d`, `--dataset-repo-id` | (required) | HuggingFace dataset repository |
| Policy type | `-p`, `--policy-type` | `act` | `act` or `diffusion` |
| Job name | `-j`, `--job-name` | `lerobot-act-training` | Job identifier |
| Training steps | `--training-steps` | `100000` | Total training iterations |
| Batch size | `--batch-size` | `32` | Training batch size |
| Learning rate | `--learning-rate` | `1e-4` | Optimizer learning rate |
| LR warmup steps | `--lr-warmup-steps` | `1000` | Learning rate warmup |
| Save frequency | `--save-freq` | `5000` | Checkpoint save interval |
| Validation split | `--val-split` | `0.1` | Validation split ratio |
| Register checkpoint | `-r`, `--register-checkpoint` | (none) | Model name for Azure ML registration |
| From blob | `--from-blob` | `false` | Use Azure Blob Storage as data source |
| Storage account | `--storage-account` | (terraform) | Azure Storage account name |
| Blob prefix | `--blob-prefix` | (none) | Blob path prefix for dataset |
| Workflow template | `-w`, `--workflow` | `workflows/osmo/lerobot-train.yaml` | OSMO workflow YAML |
| Image | `-i`, `--image` | `pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime` | Container image |
| Use local OSMO | `--use-local-osmo` | `false` | Use `osmo-dev` CLI |

### Azure ML Context

Resolved from CLI flags > environment variables > Terraform outputs:

| Variable | Flag | Env Var |
|----------|------|---------|
| Subscription ID | `--azure-subscription-id` | `AZURE_SUBSCRIPTION_ID` |
| Resource group | `--azure-resource-group` | `AZURE_RESOURCE_GROUP` |
| Workspace name | `--azure-workspace-name` | `AZUREML_WORKSPACE_NAME` |

## OSMO CLI Reference

Key monitoring commands (see [references/REFERENCE.md](references/REFERENCE.md) for full CLI and SDK documentation):

```bash
# Query workflow status
osmo workflow query <workflow-id>

# Tail recent logs
osmo workflow logs <workflow-id> -n 100

# Error logs only
osmo workflow logs <workflow-id> --error

# List running workflows
osmo workflow list --status running --json

# Cancel a workflow
osmo workflow cancel <workflow-id>
```

### Workflow Status Values

| Status | Meaning |
|--------|---------|
| `pending` | Queued, awaiting resources |
| `running` | Actively executing |
| `completed` | Finished successfully |
| `failed` | Exited with error |
| `cancelled` | Manually cancelled |

## Azure ML Metric Retrieval

Connect via Python SDK to query training metrics (see [references/REFERENCE.md](references/REFERENCE.md) for full patterns):

```python
from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient
import mlflow

ml_client = MLClient(DefaultAzureCredential(), subscription_id, resource_group, workspace_name)
mlflow.set_tracking_uri(ml_client.workspaces.get(workspace_name).mlflow_tracking_uri)

runs = mlflow.search_runs(experiment_names=["lerobot-training"], max_results=10)
```

### Key Metrics Logged

| Metric | Description |
|--------|-------------|
| `train/loss` | Training loss per step |
| `grad_norm` | Gradient norm |
| `learning_rate` | Current learning rate |
| `val/loss` | Validation loss (when val split enabled) |
| `gpu_percent` | GPU utilization (when system metrics enabled) |

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `CUDA_ERROR_NO_DEVICE` | MIG strategy misconfigured | Verify `mig.strategy: single` for vGPU nodes |
| MLflow connection timeout | Token refresh failure | Check `MLFLOW_TRACKING_TOKEN_REFRESH_RETRIES` |
| Dataset download failure | Blob auth issue | Verify managed identity has Storage Blob Reader role |
| OOM during training | Batch size too large | Reduce `--batch-size` |

See [references/REFERENCE.md](references/REFERENCE.md) for detailed debugging commands and Azure ML connectivity checks.

> Brought to you by microsoft/azure-nvidia-robotics-reference-architecture
