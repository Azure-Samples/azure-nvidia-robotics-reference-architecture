# Scripts

Submission scripts for training and validation workflows on Azure ML and OSMO platforms.

## Submission Scripts

| Script | Purpose | Platform |
|--------|---------|----------|
| `submit-azureml-training.sh` | Package code and submit Azure ML training job | Azure ML |
| `submit-azureml-validation.sh` | Submit model validation job | Azure ML |
| `submit-osmo-training.sh` | Package code and submit OSMO workflow (base64) | OSMO |
| `submit-osmo-dataset-training.sh` | Submit OSMO workflow using dataset folder injection | OSMO |

## Quick Start

Scripts auto-detect Azure context from Terraform outputs in `deploy/001-iac/`:

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

## Configuration

Scripts resolve values in order: CLI arguments → environment variables → Terraform outputs.

| Variable | Description |
|----------|-------------|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription |
| `AZURE_RESOURCE_GROUP` | Resource group name |
| `AZUREML_WORKSPACE_NAME` | ML workspace name |
| `TASK` | IsaacLab task name |
| `NUM_ENVS` | Number of parallel environments |

## Library

| File | Purpose |
|------|---------|
| `lib/terraform-outputs.sh` | Shared functions for reading Terraform outputs |

Source the library to use helper functions:

```bash
source lib/terraform-outputs.sh
read_terraform_outputs ../deploy/001-iac
get_aks_cluster_name   # Returns AKS cluster name
get_azureml_workspace  # Returns ML workspace name
```

## Related Documentation

- [workflows/](../workflows/) - YAML templates for training and validation jobs
- [deploy/002-setup/](../deploy/002-setup/) - Cluster configuration and OSMO deployment
