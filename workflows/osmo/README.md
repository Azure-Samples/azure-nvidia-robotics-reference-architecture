---
title: OSMO Workflows
description: NVIDIA OSMO workflow templates for distributed robotics training
author: Edge AI Team
ms.date: 2025-12-04
ms.topic: reference
---

# OSMO Workflows

NVIDIA OSMO workflow templates for distributed Isaac Lab training on Azure Kubernetes Service.

## Available Templates

| Template | Purpose | Submission Script |
|----------|---------|-------------------|
| [train.yaml](train.yaml) | Distributed training workflows | `scripts/submit-osmo-training.sh` |

## Training Workflow (`train.yaml`)

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

## Environment Variables

| Variable | Description |
|----------|-------------|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_RESOURCE_GROUP` | Resource group name |
| `WORKFLOW_TEMPLATE` | Path to workflow template |
| `OSMO_CONFIG_DIR` | OSMO configuration directory |

## Prerequisites

1. OSMO control plane deployed (`02-deploy-osmo-control-plane.sh`)
2. OSMO backend operator installed (`03-deploy-osmo-backend.sh`)
3. Storage configured for checkpoints (`04-configure-osmo-storage.sh`)
4. OSMO CLI installed and authenticated

## Monitoring

Access the OSMO UI dashboard to monitor workflow execution:

```bash
kubectl port-forward svc/osmo-ui 8080:80 -n osmo-system
```

Then open `http://localhost:8080` in your browser.
