# Deploy

Infrastructure deployment and cluster configuration for the robotics reference architecture. See [Terminology Glossary](#-terminology-glossary) for standard deployment terms.

## 📖 Terminology Glossary

| Term | Definition |
| --- | --- |
| Deploy | Provision Azure infrastructure or install cluster components using Terraform or deployment scripts. |
| Setup | Post-deploy configuration and access steps for the cluster and workloads. |
| Install | Install local client tools or CLIs (for example, Azure VPN Client). |
| Cleanup | Remove cluster components while keeping Azure infrastructure intact. |
| Uninstall | Run uninstall scripts that remove deployed cluster components. |
| Destroy | Delete Azure infrastructure (Terraform destroy or resource group deletion). |
| Teardown | Avoid in docs; use Destroy for infrastructure removal. |

## 📋 Deployment Order

| Step | Folder                                  | Description                                              | Time      |
|:----:|-----------------------------------------|----------------------------------------------------------|-----------|
|  1   | [000-prerequisites](000-prerequisites/) | Azure CLI login, subscription setup                      | 2 min     |
|  2   | [001-iac](001-iac/)                     | Terraform: AKS, ML workspace, storage, PostgreSQL, Redis | 30-40 min |
|  3   | [001-iac/vpn](001-iac/vpn/)             | VPN Gateway for private cluster access                   | 20-30 min |
|  4   | [002-setup](002-setup/)                 | Cluster config: GPU Operator, OSMO, AzureML extension    | 30 min    |

> [!IMPORTANT]
> The default configuration deploys a **private AKS cluster**. The cluster API endpoint is not publicly accessible. You must deploy the VPN Gateway (step 3) and connect before running cluster setup scripts (step 4).
>
> **Skip step 3** if you set `should_enable_private_aks_cluster = false` in your Terraform configuration. See [Network Configuration Modes](001-iac/README.md#network-configuration-modes) for options.

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

# 4. Deploy VPN Gateway (required for private cluster access)
cd vpn
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - must match parent deployment values
terraform init && terraform apply
cd ..

# 5. Connect to VPN (see vpn/README.md for client setup)
# Open Azure VPN Client, import configuration, connect

# 6. Configure cluster (requires VPN connection)
cd ../002-setup
az aks get-credentials --resource-group <rg> --name <aks>
kubectl cluster-info  # Verify connectivity before proceeding
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

Point-to-Site VPN enabling secure remote access to the private AKS cluster and Azure services.

> [!IMPORTANT]
> With default settings (`should_enable_private_aks_cluster = true`), VPN is **required** before running any `kubectl` commands or 002-setup scripts. Without VPN, you cannot reach the private cluster endpoint.
>
> To skip VPN, set `should_enable_private_aks_cluster = false` in your `terraform.tfvars` for a public AKS control plane.

Required for:

- Running `kubectl` commands against the private AKS cluster
- Executing 002-setup deployment scripts
- Accessing OSMO UI via private DNS
- Connecting to private PostgreSQL and Redis from local machine

See [001-iac/vpn/README.md](001-iac/vpn/README.md) for deployment and [VPN client setup](001-iac/vpn/README.md#-vpn-client-setup).

See the [root README](../README.md) for architecture details.

## 🗑️ Cleanup

Remove deployed cluster components. Use [Destroy Infrastructure](#destroy-infrastructure) for VPN and Terraform removal.

| Folder                                  | Description                                   | Time      |
|-----------------------------------------|-----------------------------------------------|-----------|
| [002-setup/cleanup](002-setup/cleanup/) | Uninstall Helm charts, extensions, namespaces | 10-15 min |

### Cleanup Steps (Cluster Components)

Clean up OSMO, AzureML, and GPU components while preserving Azure infrastructure:

```bash
cd 002-setup/cleanup

# Uninstall in reverse deployment order
./uninstall-osmo-backend.sh
./uninstall-osmo-control-plane.sh
./uninstall-azureml-extension.sh
./uninstall-robotics-charts.sh
```

See [002-setup/README.md](002-setup/README.md#cleanup) for script options and data preservation.

### Destroy Infrastructure

Destroy all Azure resources after cleanup. This removes VPN and Terraform-managed infrastructure.

**Option A: Terraform Destroy** (recommended if using Terraform state)

```bash
# Clean up cluster components first
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
