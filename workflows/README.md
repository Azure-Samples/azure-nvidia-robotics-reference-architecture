---
title: Workflows
description: AzureML and OSMO workflow templates for robotics training and validation jobs
author: Edge AI Team
ms.date: 2025-12-04
ms.topic: reference
---

# Workflows

This directory contains workflow templates for submitting robotics training and validation jobs to Azure infrastructure.

## Directory Structure

```text
workflows/
├── README.md           # This file
├── azureml/            # Azure Machine Learning job templates
│   ├── README.md
│   ├── train.yaml      # Training job specification
│   └── validate.yaml   # Validation job specification
└── osmo/               # NVIDIA OSMO workflow templates
    ├── README.md
    └── train.yaml      # OSMO training workflow specification
```

## Platform Comparison

| Feature | AzureML | OSMO |
|---------|---------|------|
| Orchestration | Azure ML Job Service | OSMO Workflow Engine |
| Scheduling | Azure ML Compute | KAI Scheduler / Volcano |
| Multi-node | Azure ML distributed jobs | OSMO workflow DAGs |
| Checkpointing | MLflow integration | Custom handlers |
| Monitoring | Azure ML Studio | OSMO UI Dashboard |

## Quick Start

### AzureML Workflows

Submit a training job using the provided scripts:

```bash
./scripts/submit-azureml-training.sh
```

Submit a validation job:

```bash
./scripts/submit-azureml-validation.sh
```

### OSMO Workflows

Submit an OSMO training workflow:

```bash
./scripts/submit-osmo-training.sh
```

## Prerequisites

Before using these workflows, ensure:

1. Infrastructure deployed via `deploy/001-iac/`
2. Setup scripts completed via `deploy/002-setup/`
3. Azure CLI authenticated with appropriate permissions
4. For OSMO: OSMO CLI installed and configured

## Configuration

All submission scripts automatically read configuration from Terraform outputs when available. Override any value using:

* **CLI arguments**: Highest precedence
* **Environment variables**: Middle precedence (e.g., `AZURE_RESOURCE_GROUP`)
* **Terraform outputs**: Default values from `deploy/001-iac/`

See individual workflow READMEs for detailed configuration options.
