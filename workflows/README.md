---
title: Workflows
description: AzureML and OSMO workflow templates for robotics training and validation jobs
author: Edge AI Team
ms.date: 2025-12-14
ms.topic: reference
---

Workflow templates for submitting robotics training and validation jobs to Azure infrastructure.

## 📁 Directory Structure

```text
workflows/
├── README.md
├── azureml/
│   ├── README.md
│   ├── train.yaml           # Training job specification
│   └── validate.yaml        # Validation job specification
└── osmo/
    ├── README.md
    ├── train.yaml           # OSMO training (base64 payload)
    ├── train-dataset.yaml   # OSMO training (dataset folder upload)
    └── infer.yaml           # OSMO inference workflow
```

## ⚖️ Platform Comparison

| Feature        | AzureML                   | OSMO                     |
|----------------|---------------------------|--------------------------|
| Orchestration  | Azure ML Job Service      | OSMO Workflow Engine     |
| Scheduling     | Azure ML Compute          | KAI Scheduler / Volcano  |
| Multi-node     | Azure ML distributed jobs | OSMO workflow DAGs       |
| Checkpointing  | MLflow integration        | MLflow + custom handlers |
| Monitoring     | Azure ML Studio           | OSMO UI Dashboard        |

## 🚀 Quick Start

### AzureML Workflows

```bash
# Training job
./scripts/submit-azureml-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0

# Validation job (model name derived from task by default)
./scripts/submit-azureml-validation.sh --task Isaac-Velocity-Rough-Anymal-C-v0
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

| Aspect         | train.yaml             | train-dataset.yaml        |
|----------------|------------------------|---------------------------|
| Payload method | Base64-encoded archive | Dataset folder upload     |
| Size limit     | ~1MB                   | Unlimited                 |
| Versioning     | None                   | Automatic                 |
| Reusability    | Per-run                | Across runs               |

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

| Parameter          | Default         | Description                    |
|--------------------|-----------------|--------------------------------|
| `--dataset-bucket` | `training`      | OSMO bucket for training code  |
| `--dataset-name`   | `training-code` | Dataset name (auto-versioned)  |
| `--training-path`  | `src/training`  | Local folder to upload         |

The training folder mounts at `/data/<dataset_name>/training` inside the container.

## 🔮 OSMO Inference Workflow

The inference workflow exports trained checkpoints to deployment-ready formats (ONNX, TorchScript) and validates them in simulation.

### Supported Model Formats

| Format      | Extension | Use Case                                   |
|-------------|-----------|--------------------------------------------|
| ONNX        | `.onnx`   | Cross-platform deployment, ONNX Runtime    |
| TorchScript | `.pt`     | PyTorch-native deployment, JIT compilation |
| Both        | —         | Export and validate both formats (default) |

### Checkpoint URI Formats

The workflow accepts checkpoints from multiple sources:

| Source       | URI Format                                                   | Example                                                                       |
|--------------|--------------------------------------------------------------|-------------------------------------------------------------------------------|
| MLflow run   | `runs:/<run_id>/<artifact_path>`                             | `runs:/b906b426-078e-4539-b907-aecb3121a76d/checkpoints/final/model_99.pt`    |
| MLflow model | `models:/<model_name>/<version>`                             | `models:/anymal-rough-terrain/1`                                              |
| Azure Blob   | `https://<account>.blob.core.windows.net/<container>/<path>` | `https://stosmorbt3dev001.blob.core.windows.net/azureml/checkpoints/model.pt` |
| HTTP(S)      | Direct URL                                                   | `https://example.com/models/policy.pt`                                        |

### Basic Usage

```bash
./scripts/submit-osmo-inference.sh \
    --checkpoint-uri "runs:/abc123/checkpoints/final/model_999.pt" \
    --task Isaac-Ant-v0
```

### Inference Parameters

| Parameter          | Default        | Description                  |
|--------------------|----------------|------------------------------|
| `--checkpoint-uri` | (required)     | URI to training checkpoint   |
| `--task`           | `Isaac-Ant-v0` | Isaac Lab task name          |
| `--format`         | `both`         | `onnx`, `jit`, or `both`     |
| `--num-envs`       | `4`            | Number of environments       |
| `--max-steps`      | `500`          | Maximum inference steps      |
| `--video-length`   | `200`          | Video recording length       |

### Examples

```bash
# ONNX-only inference with custom parameters
./scripts/submit-osmo-inference.sh \
    --checkpoint-uri "models:/my-model/1" \
    --task Isaac-Velocity-Rough-Anymal-C-v0 \
    --format onnx \
    --num-envs 8 \
    --max-steps 1000 \
    --video-length 300

# TorchScript-only inference
./scripts/submit-osmo-inference.sh \
    --checkpoint-uri "runs:/abc123/checkpoints/final/model_99.pt" \
    --task Isaac-Ant-v0 \
    --format jit

# With explicit Azure context
./scripts/submit-osmo-inference.sh \
    --checkpoint-uri "runs:/abc123/checkpoints/model_999.pt" \
    --task Isaac-Ant-v0 \
    --azure-subscription-id "00000000-0000-0000-0000-000000000000" \
    --azure-resource-group "rg-robotics" \
    --azure-workspace-name "aml-robotics"
```

### Locating Checkpoints from Training Runs

Training workflows upload checkpoints to Azure ML as MLflow artifacts. To find checkpoint URIs from completed training runs:

```bash
# List recent OSMO workflows
osmo workflow list

# View logs from a completed training run
osmo workflow logs isaaclab-inline-training-55 | grep -E "checkpoint|\.pt|mlflow"
```

Training logs display the MLflow run ID and artifact paths:

```text
INFO | MLflow tracking configured: experiment=isaaclab-rsl-rl-Isaac-Velocity-Rough-Anymal-C-v0
INFO | Found final model: /workspace/isaaclab/logs/rsl_rl/anymal_c_rough/2026-02-03_15-37-23/model_99.pt
View run at: .../runs/b906b426-078e-4539-b907-aecb3121a76d
```

Construct the checkpoint URI from the run ID and artifact path:

```text
runs:/b906b426-078e-4539-b907-aecb3121a76d/checkpoints/final/model_99.pt
```

### Workflow Outputs

The inference workflow produces:

| Artifact                    | Description                               |
|-----------------------------|-------------------------------------------|
| `exported/policy.onnx`      | ONNX-exported policy model                |
| `exported/policy.pt`        | TorchScript-exported policy model         |
| `metrics/onnx_metrics.json` | ONNX inference performance metrics        |
| `metrics/jit_metrics.json`  | TorchScript inference performance metrics |
| `videos/onnx_play/`         | ONNX inference video recordings           |
| `videos/jit_play/`          | TorchScript inference video recordings    |

## 📋 Prerequisites

| Requirement                         | Setup                    |
|-------------------------------------|--------------------------|
| Infrastructure deployed             | `deploy/001-iac/`        |
| Setup scripts completed             | `deploy/002-setup/`      |
| Azure CLI authenticated             | `az login`               |
| OSMO CLI (for OSMO workflows)       | Installed and configured |

## ⚙️ Configuration

Scripts resolve values in order:

| Precedence  | Source                | Example                          |
|-------------|-----------------------|----------------------------------|
| 1 (highest) | CLI arguments         | `--resource-group rg-custom`     |
| 2           | Environment variables | `AZURE_RESOURCE_GROUP=rg-custom` |
| 3 (default) | Terraform outputs     | `deploy/001-iac/`                |

See individual workflow READMEs for detailed configuration options.
