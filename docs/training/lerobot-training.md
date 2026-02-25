---
title: LeRobot Training Guide
description: Train behavioral cloning policies using LeRobot ACT and Diffusion architectures on Azure ML and OSMO
author: Microsoft Robotics-AI Team
ms.date: 2026-02-24
ms.topic: how-to
keywords:
  - lerobot
  - behavioral cloning
  - act policy
  - diffusion policy
---

Train behavioral cloning policies for robotics manipulation tasks using LeRobot ACT and Diffusion architectures. Submit training jobs through Azure ML compute or NVIDIA OSMO workflow orchestration.

## 📋 Prerequisites

| Component           | Requirement                                                                                                            |
|---------------------|------------------------------------------------------------------------------------------------------------------------|
| AKS cluster         | GPU-capable nodes provisioned via Terraform                                                                            |
| Azure ML (optional) | K8s extension deployed, compute target attached (`02-deploy-azureml-extension.sh`)                                     |
| OSMO (optional)     | Control plane and backend deployed, CLI authenticated (`03-deploy-osmo-control-plane.sh`, `04-deploy-osmo-backend.sh`) |
| Storage             | Checkpoint storage configured                                                                                          |
| HuggingFace         | Account with dataset access                                                                                            |

## ⚙️ Supported Policies

| Policy    | Architecture                      | Use Case                                        |
|-----------|-----------------------------------|-------------------------------------------------|
| ACT       | Action Chunking with Transformers | Fine manipulation tasks with sequential actions |
| Diffusion | Diffusion Policy                  | Complex manipulation via denoising diffusion    |

## 🔧 Training Parameters

| Parameter         | Default                                         | Platform | Description                                           |
|-------------------|-------------------------------------------------|----------|-------------------------------------------------------|
| `dataset_repo_id` | (required)                                      | Both     | HuggingFace dataset repository (e.g., `user/dataset`) |
| `policy_type`     | `act`                                           | Both     | Policy architecture: `act`, `diffusion`               |
| `job_name`        | `lerobot-act-training`                          | Both     | Unique job identifier                                 |
| `image`           | `pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime` | Both     | Container image                                       |
| `training_steps`  | (LeRobot default)                               | OSMO     | Total training iterations                             |
| `batch_size`      | (LeRobot default)                               | OSMO     | Training batch size                                   |
| `save_freq`       | `5000`                                          | Both     | Checkpoint save frequency                             |
| `wandb_enable`    | `true`                                          | Both     | Enable WANDB logging                                  |
| `mlflow_enable`   | `false`                                         | OSMO     | Enable Azure ML MLflow logging                        |

## 🚀 Quick Start

Azure ML submission:

```bash
./scripts/submit-azureml-lerobot-training.sh \
  --dataset-repo-id lerobot/aloha_sim_insertion_human \
  --policy-type act
```

OSMO submission:

```bash
# ACT training with WANDB logging
./scripts/submit-osmo-lerobot-training.sh \
  -d lerobot/aloha_sim_insertion_human

# Diffusion policy with MLflow logging
./scripts/submit-osmo-lerobot-training.sh \
  -d user/custom-dataset \
  -p diffusion \
  --mlflow-enable \
  -r my-diffusion-model
```

Fine-tune from an existing policy:

```bash
./scripts/submit-osmo-lerobot-training.sh \
  -d user/dataset \
  --policy-repo-id user/pretrained-act \
  --training-steps 50000
```

## 🔑 Credential Configuration

OSMO workflows use credential injection for authentication:

```bash
# HuggingFace token (required for private datasets)
osmo credential set hf_token --generic --value "hf_..."

# WANDB API key (required when wandb_enable=true)
osmo credential set wandb_api_key --generic --value "..."
```

Azure ML jobs inherit credentials from the AzureML extension service principal.

## 📊 Experiment Tracking

| Backend         | Enable Flag          | Platform | Details                                      |
|-----------------|----------------------|----------|----------------------------------------------|
| WANDB           | `wandb_enable=true`  | Both     | Requires `wandb_api_key` credential          |
| Azure ML MLflow | `mlflow_enable=true` | OSMO     | Logs to Azure ML workspace                   |
| Azure ML MLflow | Automatic            | Azure ML | Enabled by default through AzureML extension |

See [MLflow Integration](mlflow-integration.md) for SKRL metric logging configuration and available metrics.

## 💾 Checkpoint Management

Checkpoints save at intervals defined by `save_freq` (default: every 5000 steps). OSMO workflows register checkpoints to Azure ML model registry when `--register_model` is specified.

```bash
# Register trained model to Azure ML
./scripts/submit-osmo-lerobot-inference.sh \
  --policy-repo-id user/trained-act-policy \
  -r my-registered-model
```

## 📦 Dataset Sources

| Source              | Platform | Description                                          |
|---------------------|----------|------------------------------------------------------|
| HuggingFace Hub     | Both     | Download at runtime via `dataset_repo_id`            |
| OSMO Dataset Bucket | OSMO     | Mount from Azure Blob Storage, versioned across runs |

OSMO dataset mount training:

```bash
./scripts/submit-osmo-lerobot-training.sh \
  -w workflows/osmo/lerobot-train-dataset.yaml \
  -d user/fallback-dataset \
  --dataset-bucket my-bucket \
  --dataset-name my-lerobot-data
```

> [!NOTE]
> OSMO dataset mounts fall back to HuggingFace Hub download if no dataset mount is available.

## 🔄 End-to-End Pipeline

`scripts/run-lerobot-pipeline.sh` orchestrates the full training-to-inference workflow: dataset preparation, training submission, checkpoint extraction, and model evaluation.

```bash
./scripts/run-lerobot-pipeline.sh \
  --dataset-repo-id lerobot/aloha_sim_insertion_human \
  --policy-type act
```

## 📚 Related Documentation

- [Azure ML Training](azureml-training.md)
- [OSMO Training](osmo-training.md)
- [MLflow Integration](mlflow-integration.md)
- [Inference Guide](../inference/README.md)

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
