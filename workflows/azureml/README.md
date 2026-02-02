---
title: AzureML Workflows
description: Azure Machine Learning job templates for robotics training and validation
author: Edge AI Team
ms.date: 2025-12-04
ms.topic: reference
---

Azure Machine Learning job templates for Isaac Lab training and validation workloads.

## 📜 Available Templates

| Template                       | Purpose                               | Submission Script                      |
|--------------------------------|---------------------------------------|----------------------------------------|
| [train.yaml](train.yaml)       | Training jobs with checkpoint support | `scripts/submit-azureml-training.sh`   |
| [validate.yaml](validate.yaml) | Policy validation and inference       | `scripts/submit-azureml-validation.sh` |

## 🏋️ Training Job (`train.yaml`)

Submits Isaac Lab reinforcement learning training to AKS GPU nodes via Azure ML.

### Key Parameters

| Input             | Description                     | Default                            |
|-------------------|---------------------------------|------------------------------------|
| `mode`            | Execution mode                  | `train`                            |
| `checkpoint_mode` | Checkpoint loading strategy     | `from-scratch`                     |
| `task`            | Isaac Lab task name             | `Isaac-Velocity-Rough-Anymal-C-v0` |
| `num_envs`        | Number of parallel environments | `4096`                             |
| `headless`        | Run without rendering           | `true`                             |
| `max_iterations`  | Training iterations             | `4500`                             |

### Training Usage

```bash
# Default configuration from Terraform outputs
./scripts/submit-azureml-training.sh

# Override specific parameters
./scripts/submit-azureml-training.sh \
  --resource-group rg-custom \
  --workspace-name mlw-custom
```

## ✅ Validation Job (`validate.yaml`)

Runs trained policy validation and generates inference metrics.

### Validation Parameters

| Input             | Description                 | Default                            |
|-------------------|-----------------------------|------------------------------------|
| `mode`            | Execution mode              | `play`                             |
| `checkpoint_mode` | Must use trained checkpoint | `from-trained`                     |
| `task`            | Isaac Lab task name         | `Isaac-Velocity-Rough-Anymal-C-v0` |
| `num_envs`        | Environments for validation | `1024`                             |

### Validation Usage

```bash
# Default configuration
./scripts/submit-azureml-validation.sh

# With custom checkpoint
./scripts/submit-azureml-validation.sh \
  --checkpoint-path "azureml://datastores/checkpoints/paths/model.pt"
```

## ⚙️ Environment Variables

All scripts support environment variable configuration:

| Variable                 | Description             |
|--------------------------|-------------------------|
| `AZURE_SUBSCRIPTION_ID`  | Azure subscription ID   |
| `AZURE_RESOURCE_GROUP`   | Resource group name     |
| `AZUREML_WORKSPACE_NAME` | Azure ML workspace name |
| `AZUREML_COMPUTE`        | Compute target name     |

## 📋 Prerequisites

1. Azure ML extension installed on AKS cluster
2. Kubernetes compute target attached to workspace
3. GPU instance types configured in cluster
