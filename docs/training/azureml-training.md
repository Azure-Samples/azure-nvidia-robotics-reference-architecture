---
title: Azure ML Training Workflows
description: Submit Isaac Lab and LeRobot training jobs to Azure Machine Learning
author: Microsoft Robotics-AI Team
ms.date: 2026-02-24
ms.topic: how-to
keywords:
  - azure ml
  - training
  - isaac lab
  - lerobot
---

Submit Isaac Lab reinforcement learning and LeRobot behavioral cloning training jobs to Azure Machine Learning using Kubernetes compute targets.

## 📋 Prerequisites

| Component          | Requirement                                                    |
|--------------------|----------------------------------------------------------------|
| AzureML extension  | Deployed via `02-deploy-azureml-extension.sh`                  |
| Kubernetes compute | GPU-capable compute target attached to AzureML workspace       |
| Azure subscription | Subscription ID, resource group, and workspace name configured |

## 📦 Available Templates

| Template             | Purpose                    | Submission Script                            |
|----------------------|----------------------------|----------------------------------------------|
| `train.yaml`         | Isaac Lab SKRL training    | `scripts/submit-azureml-training.sh`         |
| `validate.yaml`      | Isaac Lab validation       | `scripts/submit-azureml-validation.sh`       |
| `lerobot-train.yaml` | LeRobot behavioral cloning | `scripts/submit-azureml-lerobot-training.sh` |

## ⚙️ Isaac Lab Training Parameters

| Parameter         | Description                                         |
|-------------------|-----------------------------------------------------|
| `mode`            | Train or retrain (default: `train`)                 |
| `checkpoint_mode` | Checkpoint strategy: `from-scratch`, `from-trained` |
| `task`            | Isaac Lab task name (e.g., `Isaac-Cartpole-v0`)     |
| `num_envs`        | Number of parallel environments                     |
| `headless`        | Run without rendering (default: `true`)             |
| `max_iterations`  | Maximum training iterations                         |

## 🤖 LeRobot Training Parameters

| Parameter         | Default                                         | Description                             |
|-------------------|-------------------------------------------------|-----------------------------------------|
| `dataset_repo_id` | (required)                                      | HuggingFace dataset repository          |
| `policy_type`     | `act`                                           | Policy architecture: `act`, `diffusion` |
| `job_name`        | `lerobot-act-training`                          | Unique job identifier                   |
| `image`           | `pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime` | Container image                         |
| `wandb_enable`    | `true`                                          | Enable WANDB logging                    |
| `save_freq`       | `5000`                                          | Checkpoint save frequency               |

## 🔧 Environment Variables

| Variable                 | Description                    |
|--------------------------|--------------------------------|
| `AZURE_SUBSCRIPTION_ID`  | Azure subscription ID          |
| `AZURE_RESOURCE_GROUP`   | Resource group name            |
| `AZUREML_WORKSPACE_NAME` | Azure ML workspace name        |
| `AZUREML_COMPUTE`        | Kubernetes compute target name |

Scripts auto-detect these values from Terraform outputs. Override using CLI arguments or environment variables.

## 🚀 Quick Start

Isaac Lab SKRL training:

```bash
# Default configuration from Terraform outputs
./scripts/submit-azureml-training.sh

# Custom task and environment count
./scripts/submit-azureml-training.sh \
  --task Isaac-Cartpole-v0 \
  --num-envs 512 \
  --max-iterations 1000
```

Isaac Lab validation:

```bash
./scripts/submit-azureml-validation.sh \
  --task Isaac-Cartpole-v0 \
  --checkpoint-mode from-trained
```

LeRobot training:

```bash
./scripts/submit-azureml-lerobot-training.sh \
  --dataset-repo-id lerobot/aloha_sim_insertion_human \
  --policy-type act
```

## 💾 Checkpoint Management

| Mode           | Behavior                                  |
|----------------|-------------------------------------------|
| `from-scratch` | Start training from random initialization |
| `from-trained` | Resume from an existing checkpoint        |

Specify the checkpoint mode with `--checkpoint-mode`:

```bash
./scripts/submit-azureml-training.sh \
  --checkpoint-mode from-trained \
  --task Isaac-Cartpole-v0
```

## 📚 Related Documentation

- [LeRobot Training](lerobot-training.md)
- [OSMO Training](osmo-training.md)
- [MLflow Integration](mlflow-integration.md)
- [Training Guide](README.md)

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
