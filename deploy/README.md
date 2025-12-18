# Deploy

Infrastructure deployment and cluster configuration for the robotics reference architecture.

## 📋 Deployment Order

| Step | Folder | Description | Time |
|:----:|--------|-------------|------|
| 1 | [000-prerequisites](000-prerequisites/) | Azure CLI login, subscription setup | 2 min |
| 2 | [001-iac](001-iac/) | Terraform: AKS, ML workspace, storage, PostgreSQL, Redis | 30-40 min |
| 2b | [001-iac/vpn](001-iac/vpn/) | Optional: VPN Gateway for private endpoint access | 20-30 min |
| 3 | [002-setup](002-setup/) | Cluster config: GPU Operator, OSMO, AzureML extension | 30 min |

## 🚀 Quick Path

```bash
# 1. Set subscription
source 000-prerequisites/az-sub-init.sh

# 2. Register providers (new subscriptions only)
./000-prerequisites/register-azure-providers.sh

# 3. Deploy infrastructure
cd 001-iac
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply

# 4. Deploy VPN Gateway (optional, for private endpoint access)
cd vpn
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - must match parent deployment values
terraform init && terraform apply
cd ..

# 5. Configure cluster
cd ../002-setup
./01-deploy-robotics-charts.sh
./02-deploy-azureml-extension.sh
```

For OSMO deployment, see [002-setup/README.md](002-setup/README.md) for authentication scenarios.

## 📦 What Gets Deployed

### Core Infrastructure (001-iac)

- **AKS Cluster**: System and GPU (Spot) node pools with OIDC enabled
- **Azure ML Workspace**: Attached to AKS for training job submission
- **Storage Account**: Training checkpoints and datasets
- **PostgreSQL + Redis**: OSMO workflow state and caching
- **Container Registry**: Private image storage

### VPN Gateway (001-iac/vpn)

Point-to-Site VPN enabling secure remote access to private endpoints. Required for:

- Accessing OSMO UI via private DNS
- Connecting to private PostgreSQL and Redis from local machine
- Debugging workloads over private network

See [001-iac/vpn/README.md](001-iac/vpn/README.md) for deployment and [VPN client setup](001-iac/vpn/README.md#-vpn-client-setup).

See the [root README](../README.md) for architecture details.

## 🗑️ Cleanup

Remove deployed components in reverse order. Cluster components must be removed before infrastructure.

| Step | Folder | Description | Time |
|:----:|--------|-------------|------|
| 1 | [002-setup/cleanup](002-setup/cleanup/) | Uninstall Helm charts, extensions, namespaces | 10-15 min |
| 2 | [001-iac/vpn](001-iac/vpn/) | Destroy VPN Gateway (if deployed) | 10-15 min |
| 3 | [001-iac](001-iac/) | Terraform destroy or resource group deletion | 20-30 min |

### Partial Cleanup (Cluster Components Only)

Remove OSMO, AzureML, and GPU components while preserving Azure infrastructure:

```bash
cd 002-setup/cleanup

# Uninstall in reverse deployment order
./uninstall-osmo-backend.sh
./uninstall-osmo-control-plane.sh
./uninstall-azureml-extension.sh
./uninstall-robotics-charts.sh
```

See [002-setup/README.md](002-setup/README.md#cleanup) for script options and data preservation.

### Full Teardown

Remove all Azure resources. Choose based on how infrastructure was created.

**Option A: Terraform Destroy** (recommended if using Terraform state)

```bash
# Remove cluster components first
cd 002-setup/cleanup
./uninstall-osmo-backend.sh --delete-container
./uninstall-osmo-control-plane.sh --purge-postgres --purge-redis --delete-mek
./uninstall-azureml-extension.sh
./uninstall-robotics-charts.sh --delete-namespaces --delete-crds

# Destroy infrastructure
cd ../../001-iac
terraform destroy -var-file=terraform.tfvars

# Optional: destroy VPN if deployed
cd vpn && terraform destroy -var-file=terraform.tfvars
```

**Option B: Delete Resource Group** (fastest, deletes everything)

```bash
# Get resource group name from terraform or Azure portal
az group delete --name <resource-group-name> --yes --no-wait
```

This deletes all resources in the group immediately. Use when:
- Terraform created the resource group
- You want to remove everything without preserving state
- Terraform state is corrupted or unavailable

See [001-iac/README.md](001-iac/README.md#destroy-infrastructure) for detailed options.
