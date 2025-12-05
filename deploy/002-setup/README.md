---
title: Setup Scripts
description: Kubernetes cluster setup scripts for robotics workloads with AzureML and OSMO
author: Edge AI Team
ms.date: 2025-12-04
ms.topic: hub-page
---

# Setup Scripts

This directory contains scripts for configuring the AKS cluster after Terraform deployment. Scripts are numbered to indicate execution order.

## Quick Start Decision Tree

```text
Start: Infrastructure deployed via 001-iac?
       │
       ├── No ──► Run: cd ../001-iac && terraform apply
       │
       └── Yes
            │
            ▼
       Run: ./01-deploy-robotics-charts.sh
       (Installs GPU Operator, KAI Scheduler)
            │
            ▼
       Choose Platform:
            │
            ├── AzureML ──► Run: ./02-install-azureml-extension.sh
            │               └── Submit jobs via scripts/submit-azureml-*.sh
            │
            └── OSMO ──► Run: ./02-deploy-osmo-control-plane.sh
                         │
                         ▼
                    Run: ./03-deploy-osmo-backend.sh
                         │
                         ▼
                    Run: ./04-configure-osmo-storage.sh
                         │
                         └── Submit jobs via scripts/submit-osmo-training.sh
```

## Script Execution Order

| # | Script | Purpose | Required |
|---|--------|---------|----------|
| 01 | `01-deploy-robotics-charts.sh` | GPU Operator, KAI Scheduler | Always |
| 02a | `02-install-azureml-extension.sh` | AzureML K8s extension | AzureML path |
| 02b | `02-deploy-osmo-control-plane.sh` | OSMO control plane | OSMO path |
| 03 | `03-deploy-osmo-backend.sh` | OSMO backend operator | OSMO path |
| 04 | `04-configure-osmo-storage.sh` | OSMO storage configuration | OSMO path |

## Directory Structure

```text
002-setup/
├── README.md                          # This file
├── 01-deploy-robotics-charts.sh       # GPU Operator, KAI Scheduler
├── 02-install-azureml-extension.sh    # AzureML path
├── 02-deploy-osmo-control-plane.sh    # OSMO path
├── 03-deploy-osmo-backend.sh          # OSMO backend
├── 04-configure-osmo-storage.sh       # OSMO storage
├── values/                            # Helm values files
│   ├── nvidia-gpu-operator.yaml
│   ├── kai-scheduler.yaml
│   ├── volcano.yaml
│   ├── osmo-control-plane.yaml
│   ├── osmo-router.yaml
│   ├── osmo-ui.yaml
│   └── osmo-backend-operator.yaml
├── manifests/                         # Kubernetes manifests
│   ├── gpu-podmonitor.yaml
│   ├── ama-metrics-dcgm-scrape.yaml
│   ├── internal-lb-ingress.yaml
│   └── gpu-instance-type.yaml
├── config/                            # OSMO configuration templates
│   ├── scheduler-config-example.json
│   ├── pod-template-config-example.json
│   ├── default-pool-config-example.json
│   └── workflow-config-example.json
└── optional/                          # Optional/utility scripts
    ├── deploy-volcano-scheduler.sh
    ├── uninstall-volcano-scheduler.sh
    ├── uninstall-robotics-charts.sh
    └── validate-gpu-metrics.sh
```

## Prerequisites

Before running any setup script:

1. **Terraform deployed**: `cd ../001-iac && terraform apply`
2. **kubectl configured**: `az aks get-credentials --resource-group <rg> --name <aks>`
3. **Helm installed**: Version 3.x required
4. **Azure CLI authenticated**: `az login`

## Configuration

All scripts automatically read configuration from Terraform outputs in `../001-iac/`. Override any value using environment variables:

| Variable | Description |
|----------|-------------|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_RESOURCE_GROUP` | Resource group name |
| `AKS_CLUSTER_NAME` | AKS cluster name |

## AzureML Path

For Azure Machine Learning workloads:

```bash
# Step 1: Deploy GPU infrastructure
./01-deploy-robotics-charts.sh

# Step 2: Install AzureML extension
./02-install-azureml-extension.sh

# Submit training jobs
../scripts/submit-azureml-training.sh
```

## OSMO Path

For NVIDIA OSMO orchestrated workloads:

```bash
# Step 1: Deploy GPU infrastructure
./01-deploy-robotics-charts.sh

# Step 2: Deploy OSMO control plane
./02-deploy-osmo-control-plane.sh

# Step 3: Deploy backend operator
./03-deploy-osmo-backend.sh

# Step 4: Configure storage
./04-configure-osmo-storage.sh

# Submit training workflows
../scripts/submit-osmo-training.sh
```

## Optional Scripts

Scripts in `optional/` are not required for standard deployments:

* `deploy-volcano-scheduler.sh` - Volcano scheduler (alternative to KAI)
* `uninstall-volcano-scheduler.sh` - Remove Volcano scheduler
* `uninstall-robotics-charts.sh` - Remove GPU Operator and KAI
* `validate-gpu-metrics.sh` - Verify GPU metrics collection
