---
title: Scripts
description: Submission scripts for training and validation workflows on Azure ML and OSMO platforms
author: Edge AI Team
ms.date: 2025-12-14
ms.topic: reference
---

# Scripts

Submission scripts for training and validation workflows on Azure ML and OSMO platforms. OSMO submissions can fall back to Terraform outputs from `deploy/001-iac` when available.

## 📜 Submission Scripts

| Script                             | Purpose                                              | Platform |
| ---------------------------------- | ---------------------------------------------------- | -------- |
| `submit-azureml-training.sh`       | Package code and submit Azure ML training job        | Azure ML |
| `submit-azureml-validation.sh`     | Submit model validation job                          | Azure ML |
| `submit-osmo-training.sh`          | Package code and submit OSMO workflow (base64)       | OSMO     |
| `submit-osmo-dataset-training.sh`  | Submit OSMO workflow using dataset folder injection  | OSMO     |

## 🚀 Quick Start

OSMO submissions can fall back to Terraform outputs in `deploy/001-iac/`. Azure ML submissions require explicit Azure context values.

```bash
# Azure ML training
./submit-azureml-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0

# OSMO training (base64 encoded)
./submit-osmo-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0

# OSMO training (dataset folder upload)
./submit-osmo-dataset-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0

# Validation (requires registered model)
./submit-azureml-validation.sh --model-name anymal-c-velocity --model-version 1
```

Provide Azure context explicitly when Terraform state is unavailable:

```bash
# OSMO training with explicit Azure context
./submit-osmo-training.sh \
  --task Isaac-Velocity-Rough-Anymal-C-v0 \
  --azure-subscription-id <sub> \
  --azure-resource-group <rg> \
  --azure-workspace-name <workspace>
```

## 💾 OSMO Dataset Training

The `submit-osmo-dataset-training.sh` script uploads `src/training/` as a versioned OSMO dataset. This approach removes the ~1MB size limit of base64-encoded archives and enables dataset reuse across runs.

### Dataset Submission Example

```bash
# Default dataset configuration
./submit-osmo-dataset-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0

# Custom dataset bucket and name
./submit-osmo-dataset-training.sh \
  --dataset-bucket custom-bucket \
  --dataset-name my-training-v1 \
  --task Isaac-Velocity-Rough-Anymal-C-v0

# With checkpoint resume
./submit-osmo-dataset-training.sh \
  --task Isaac-Velocity-Rough-Anymal-C-v0 \
  --checkpoint-uri "runs:/abc123/checkpoint" \
  --checkpoint-mode resume
```

### Dataset Parameters

| Parameter          | Default         | Description                    |
| ------------------ | --------------- | ------------------------------ |
| `--dataset-bucket` | `training`      | OSMO bucket for training code  |
| `--dataset-name`   | `training-code` | Dataset name (auto-versioned)  |
| `--training-path`  | `src/training`  | Local folder to upload         |

The script stages files to exclude `__pycache__` and build artifacts via `.amlignore` patterns before upload.

## ⚙️ Configuration

Scripts resolve values in order: CLI arguments → environment variables → Terraform outputs.

> [!NOTE]
> OSMO submit scripts read Terraform outputs from `deploy/001-iac` if available. If you do not have Terraform state, provide `--azure-subscription-id`, `--azure-resource-group`, and `--azure-workspace-name` or set `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, and `AZUREML_WORKSPACE_NAME`.

### Azure context

| CLI flag                  | Environment variable       |
| ------------------------- | -------------------------- |
| `--azure-subscription-id` | `AZURE_SUBSCRIPTION_ID`    |
| `--azure-resource-group`  | `AZURE_RESOURCE_GROUP`     |
| `--azure-workspace-name`  | `AZUREML_WORKSPACE_NAME`   |

Azure ML submissions validate these values. OSMO submissions include them only when they are set.

| Variable                 | Description                                                |
| ------------------------ | ---------------------------------------------------------- |
| `AZURE_SUBSCRIPTION_ID`  | Azure subscription (required for Azure ML submissions)     |
| `AZURE_RESOURCE_GROUP`   | Resource group name (required for Azure ML submissions)    |
| `AZUREML_WORKSPACE_NAME` | ML workspace name (required for Azure ML submissions)      |
| `TASK`                   | IsaacLab task name                                         |
| `NUM_ENVS`               | Number of parallel environments                            |
| `OSMO_DATASET_BUCKET`    | Dataset bucket for OSMO training                           |
| `OSMO_DATASET_NAME`      | Dataset name for OSMO training                             |

## 📚 Library

| File                       | Purpose                                         |
| -------------------------- | ----------------------------------------------- |
| `lib/terraform-outputs.sh` | Shared functions for reading Terraform outputs |

Source the library to use helper functions:

```bash
source lib/terraform-outputs.sh
read_terraform_outputs ../deploy/001-iac
get_aks_cluster_name   # Returns AKS cluster name
get_azureml_workspace  # Returns ML workspace name
```

## 🔗 Related Documentation

| Resource                                  | Description                                        |
| ----------------------------------------- | -------------------------------------------------- |
| [workflows/](../workflows/)               | YAML templates for training and validation jobs    |
| [workflows/osmo/](../workflows/osmo/)     | OSMO workflow templates including dataset training |
| [deploy/002-setup/](../deploy/002-setup/) | Cluster configuration and OSMO deployment          |
