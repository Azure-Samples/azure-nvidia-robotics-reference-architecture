---
title: Workflows
description: AzureML and OSMO workflow templates for robotics training and validation jobs
author: Edge AI Team
ms.date: 2025-12-14
ms.topic: reference
---

# Workflows

Workflow templates for submitting robotics training and validation jobs to Azure infrastructure.

## 📁 Directory Structure

```text
workflows/
├── README.md
├── azureml/
│   ├── README.md
│   ├── train.yaml          # Training job specification
│   └── validate.yaml       # Validation job specification
└── osmo/
    ├── README.md
    ├── train.yaml           # OSMO training (base64 payload)
    └── train-dataset.yaml   # OSMO training (dataset folder upload)
```

## ⚖️ Platform Comparison

| Feature | AzureML | OSMO |
|---------|---------|------|
| Orchestration | Azure ML Job Service | OSMO Workflow Engine |
| Scheduling | Azure ML Compute | KAI Scheduler / Volcano |
| Multi-node | Azure ML distributed jobs | OSMO workflow DAGs |
| Checkpointing | MLflow integration | MLflow + custom handlers |
| Monitoring | Azure ML Studio | OSMO UI Dashboard |

## 🚀 Quick Start

### AzureML Workflows

```bash
# Training job
./scripts/submit-azureml-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0

# Validation job
./scripts/submit-azureml-validation.sh --model-name anymal-c-velocity --model-version 1
```

### OSMO Workflows

```bash
# Base64 payload (< 1MB training code)
./scripts/submit-osmo-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0

# Dataset folder upload (unlimited size, versioned)
./scripts/submit-osmo-dataset-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0
```

## 💾 OSMO Dataset Workflow

The `train-dataset.yaml` template uploads `src/training/` as a versioned OSMO dataset instead of base64-encoding it inline.

| Aspect | train.yaml | train-dataset.yaml |
|--------|------------|--------------------|
| Payload method | Base64-encoded archive | Dataset folder upload |
| Size limit | ~1MB | Unlimited |
| Versioning | None | Automatic |
| Reusability | Per-run | Across runs |

### Dataset Submission

```bash
# Default configuration
./scripts/submit-osmo-dataset-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0

# Custom dataset configuration
./scripts/submit-osmo-dataset-training.sh \
  --dataset-bucket custom-bucket \
  --dataset-name my-training-v1 \
  --task Isaac-Velocity-Rough-Anymal-C-v0
```

### Dataset Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `dataset_bucket` | `training` | OSMO bucket for training code |
| `dataset_name` | `training-code` | Dataset name (auto-versioned) |
| `training_localpath` | (set by script) | Local path relative to workflow |

The training folder mounts at `/data/<dataset_name>/training` inside the container.

## 📋 Prerequisites

| Requirement | Setup |
|-------------|-------|
| Infrastructure deployed | `deploy/001-iac/` |
| Setup scripts completed | `deploy/002-setup/` |
| Azure CLI authenticated | `az login` |
| OSMO CLI (for OSMO workflows) | Installed and configured |

## ⚙️ Configuration

Scripts resolve values in order:

| Precedence | Source | Example |
|------------|--------|---------|
| 1 (highest) | CLI arguments | `--azure-resource-group rg-custom` |
| 2 | Environment variables | `AZURE_RESOURCE_GROUP=rg-custom` |
| 3 (default) | Terraform outputs | `deploy/001-iac/` |

See individual workflow READMEs for detailed configuration options.
