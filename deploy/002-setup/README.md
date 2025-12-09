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
            ├── AzureML ──► Run: ./02-deploy-azureml-extension.sh
            │               └── Submit jobs via scripts/submit-azureml-*.sh
            │
            └── OSMO ──► Run: ./03-deploy-osmo-control-plane.sh
                         │
                         ▼
                    Run: ./04-deploy-osmo-backend.sh
                         │
                         ▼
                    Run: ./05-configure-osmo.sh
                         │
                         └── Submit jobs via scripts/submit-osmo-training.sh
```

## Script Execution Order

| # | Script | Purpose | Required |
|---|--------|---------|----------|
| 01 | `01-deploy-robotics-charts.sh` | GPU Operator, KAI Scheduler | Always |
| 02 | `02-deploy-azureml-extension.sh` | AzureML K8s extension | AzureML path |
| 03 | `03-deploy-osmo-control-plane.sh` | OSMO control plane | OSMO path |
| 04 | `04-deploy-osmo-backend.sh` | OSMO backend operator | OSMO path |
| 05 | `05-configure-osmo.sh` | OSMO storage and workflow configuration | OSMO path |

## Directory Structure

```text
002-setup/
├── README.md                          # This file
├── 01-deploy-robotics-charts.sh       # GPU Operator, KAI Scheduler
├── 02-deploy-azureml-extension.sh     # AzureML path
├── 03-deploy-osmo-control-plane.sh    # OSMO path
├── 04-deploy-osmo-backend.sh          # OSMO backend
├── 05-configure-osmo.sh               # OSMO storage and workflow config
├── cleanup/                           # Uninstall scripts
│   └── uninstall-azureml-extension.sh
├── config/                            # OSMO configuration templates
│   ├── default-pool-config-example.json
│   ├── pod-template-config-example.json
│   ├── scheduler-config-example.json
│   ├── service-config-example.json
│   ├── workflow-config-example.json
│   └── out/                           # Generated config outputs
├── manifests/                         # Kubernetes manifests
│   ├── ama-metrics-dcgm-scrape.yaml
│   ├── gpu-instance-type.yaml
│   ├── gpu-podmonitor.yaml
│   ├── internal-lb-ingress.yaml
│   └── osmo-workflow-sa.yaml
├── optional/                          # Optional/utility scripts
│   ├── deploy-volcano-scheduler.sh
│   ├── uninstall-robotics-charts.sh
│   ├── uninstall-volcano-scheduler.sh
│   └── validate-gpu-metrics.sh
└── values/                            # Helm values files
    ├── kai-scheduler.yaml
    ├── nvidia-gpu-operator.yaml
    ├── osmo-backend-operator.yaml
    ├── osmo-backend-operator-identity.yaml
    ├── osmo-control-plane.yaml
    ├── osmo-control-plane-identity.yaml
    ├── osmo-router.yaml
    ├── osmo-router-identity.yaml
    ├── osmo-ui.yaml
    └── volcano.yaml
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
./02-deploy-azureml-extension.sh

# Submit training jobs
../scripts/submit-azureml-training.sh
```

## OSMO Path

For NVIDIA OSMO orchestrated workloads:

```bash
# Step 1: Deploy GPU infrastructure
./01-deploy-robotics-charts.sh

# Step 2: Deploy OSMO control plane
./03-deploy-osmo-control-plane.sh

# Step 3: Deploy backend operator
./04-deploy-osmo-backend.sh

# Step 4: Configure storage and workflows
./05-configure-osmo.sh

# Submit training workflows
../scripts/submit-osmo-training.sh
```

### OSMO Service URL Auto-Detection

The backend operator script automatically detects the OSMO service URL:

1. **Primary**: Uses `azureml-ingress-nginx-internal-lb` LoadBalancer IP (deployed by control plane script)
2. **Fallback**: Uses `azureml-ingress-nginx-controller` ClusterIP for internal routing

Override with `--service-url URL` if needed:

```bash
# Use internal nginx controller directly
./04-deploy-osmo-backend.sh --service-url http://azureml-ingress-nginx-controller.azureml.svc.cluster.local
```

> **Note**: The `azureml-fe` LoadBalancer is reserved for AzureML inference endpoints and should not be used for OSMO.

## Optional Scripts

Scripts in `optional/` are not required for standard deployments:

* `deploy-volcano-scheduler.sh` - Volcano scheduler (alternative to KAI)
* `uninstall-volcano-scheduler.sh` - Remove Volcano scheduler
* `uninstall-robotics-charts.sh` - Remove GPU Operator and KAI
* `validate-gpu-metrics.sh` - Verify GPU metrics collection
