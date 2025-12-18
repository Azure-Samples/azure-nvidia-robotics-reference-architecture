---
title: OSMO Workflows
description: NVIDIA OSMO workflow templates for distributed robotics training
author: Edge AI Team
ms.date: 2025-12-04
ms.topic: reference
---

# OSMO Workflows

NVIDIA OSMO workflow templates for distributed Isaac Lab training on Azure Kubernetes Service.

## 📜 Available Templates

| Template | Purpose | Submission Script |
|----------|---------|-------------------|
| [train.yaml](train.yaml) | Distributed training (base64 inline) | `scripts/submit-osmo-training.sh` |
| [train-dataset.yaml](train-dataset.yaml) | Distributed training (dataset upload) | `scripts/submit-osmo-dataset-training.sh` |

## ⚖️ Workflow Comparison

| Aspect | train.yaml | train-dataset.yaml |
|--------|------------|--------------------|
| Payload | Base64-encoded archive | Dataset folder upload |
| Size limit | ~1MB | Unlimited |
| Versioning | None | Automatic |
| Reusability | Per-run | Across runs |
| Setup | None | Bucket configured |

## 🏋️ Training Workflow (`train.yaml`)

Submits Isaac Lab distributed training through OSMO's workflow orchestration engine.

### Features

* Multi-GPU distributed training coordination
* KAI Scheduler / Volcano integration
* Automatic checkpointing and recovery
* OSMO UI monitoring dashboard

### Workflow Parameters

Parameters are passed as key=value pairs through the submission script:

| Parameter | Description |
|-----------|-------------|
| `azure_subscription_id` | Azure subscription ID |
| `azure_resource_group` | Resource group name |
| `azure_workspace_name` | ML workspace name |
| `task` | Isaac Lab task name |
| `num_envs` | Parallel environments |
| `max_iterations` | Training iterations |

### Usage

```bash
# Default configuration from Terraform outputs
./scripts/submit-osmo-training.sh

# Override parameters
./scripts/submit-osmo-training.sh \
  --azure-subscription-id "your-subscription-id" \
  --azure-resource-group "rg-custom"
```

## 💾 Dataset Training Workflow (`train-dataset.yaml`)

Submits Isaac Lab training using OSMO dataset folder injection instead of base64-encoded archives.

### Features

* Dataset versioning and reusability
* No payload size limits
* Training folder mounted at `/data/<dataset_name>/training`
* All features from `train.yaml`

### Dataset Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `dataset_bucket` | `training` | OSMO bucket for training code |
| `dataset_name` | `training-code` | Dataset name in bucket |
| `training_localpath` | (required) | Local path to src/training relative to workflow |

### Usage

```bash
# Default configuration
./scripts/submit-osmo-dataset-training.sh

# Custom dataset bucket
./scripts/submit-osmo-dataset-training.sh \
  --dataset-bucket custom-bucket \
  --dataset-name my-training-code
```

## ⚙️ Environment Variables

| Variable | Description |
|----------|-------------|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_RESOURCE_GROUP` | Resource group name |
| `WORKFLOW_TEMPLATE` | Path to workflow template |
| `OSMO_CONFIG_DIR` | OSMO configuration directory |
| `OSMO_DATASET_BUCKET` | Dataset bucket name (default: training) |
| `OSMO_DATASET_NAME` | Dataset name (default: training-code) |

## 📋 Prerequisites

1. OSMO control plane deployed (`03-deploy-osmo-control-plane.sh`)
2. OSMO backend operator installed (`04-deploy-osmo-backend.sh`)
3. Storage configured for checkpoints (`05-configure-osmo.sh`)
4. OSMO CLI installed and authenticated

## 📺 Monitoring

Access the OSMO UI dashboard to monitor workflow execution:

```bash
kubectl port-forward svc/osmo-ui 8080:80 -n osmo-system
```

Then open `http://localhost:8080` in your browser.
