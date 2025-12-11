# Deploy

Infrastructure deployment and cluster configuration for the robotics reference architecture.

## Deployment Order

| Step | Folder | Description | Time |
|:----:|--------|-------------|------|
| 1 | [000-prerequisites](000-prerequisites/) | Azure CLI login, subscription setup | 2 min |
| 2 | [001-iac](001-iac/) | Terraform: AKS, ML workspace, storage, PostgreSQL, Redis | 15-20 min |
| 3 | [002-setup](002-setup/) | Cluster config: GPU Operator, OSMO, AzureML extension | 10-15 min |

## Quick Path

```bash
# 1. Set subscription
source 000-prerequisites/az-sub-init.sh

# 2. Deploy infrastructure
cd 001-iac
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply

# 3. Configure cluster
cd ../002-setup
./01-deploy-robotics-charts.sh
./02-deploy-azureml-extension.sh
```

For OSMO deployment, see [002-setup/README.md](002-setup/README.md) for authentication scenarios.

## What Gets Deployed

- **AKS Cluster**: System and GPU (Spot) node pools with OIDC enabled
- **Azure ML Workspace**: Attached to AKS for training job submission
- **Storage Account**: Training checkpoints and datasets
- **PostgreSQL + Redis**: OSMO workflow state and caching
- **Container Registry**: Private image storage
- **Optional**: VPN Gateway for private endpoint access

See the [root README](../README.md) for architecture details.
