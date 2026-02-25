---
title: Training Guide
description: Train robotics policies with Isaac Lab and LeRobot using Azure ML and NVIDIA OSMO
author: Microsoft Robotics-AI Team
ms.date: 2026-02-24
ms.topic: overview
keywords:
  - training
  - robotics
  - Isaac Lab
  - LeRobot
  - OSMO
  - Azure ML
  - SKRL
  - MLflow
---

Train reinforcement learning policies for robotics tasks using Isaac Lab with SKRL agents or LeRobot ACT policies. Submit training jobs through Azure ML compute or NVIDIA OSMO workflow orchestration.

## 📖 Training Guides

| Guide                                              | Description                                           |
|----------------------------------------------------|-------------------------------------------------------|
| [LeRobot Training](lerobot-training.md)            | Behavioral cloning with ACT and Diffusion policies    |
| [Azure ML Training](azureml-training.md)           | Submit training jobs to Azure Machine Learning        |
| [OSMO Training](osmo-training.md)                  | Submit training jobs to NVIDIA OSMO                   |
| [MLflow Integration](mlflow-integration.md)        | Automatic metric logging from SKRL agents to Azure ML |
| [Inference Guide](../inference/README.md)          | Deploy trained policies in simulation or on hardware  |

## ⚙️ Training Pipelines

| Pipeline         | Framework | Orchestration | Submission Script                            |
|------------------|-----------|---------------|----------------------------------------------|
| Isaac Lab + SKRL | SKRL      | Azure ML      | `scripts/submit-azureml-training.sh`         |
| Isaac Lab + SKRL | SKRL      | OSMO          | `scripts/submit-osmo-training.sh`            |
| LeRobot ACT      | LeRobot   | Azure ML      | `scripts/submit-azureml-lerobot-training.sh` |
| LeRobot ACT      | LeRobot   | OSMO          | `scripts/submit-osmo-lerobot-training.sh`    |

## 🚀 Quick Start

Isaac Lab SKRL training via Azure ML:

```bash
./scripts/submit-azureml-training.sh \
  --task Isaac-Cartpole-v0 \
  --num-envs 512
```

OSMO training submission:

```bash
./scripts/submit-osmo-training.sh \
  --task Isaac-Cartpole-v0 \
  --num-envs 512
```

LeRobot ACT training via OSMO:

```bash
./scripts/submit-osmo-lerobot-training.sh \
  --dataset-repo-id <repo-id> \
  --training-steps 100000
```

## 📚 Related Documentation

- [LeRobot Training](lerobot-training.md)
- [Azure ML Training](azureml-training.md)
- [OSMO Training](osmo-training.md)
- [MLflow Integration](mlflow-integration.md)
- [Inference Guide](../inference/README.md)
- [Workflow Templates](../../workflows/README.md)
- [Automation Scripts](../../scripts/README.md)

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
