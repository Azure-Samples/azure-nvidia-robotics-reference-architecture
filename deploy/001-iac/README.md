# Infrastructure as Code

Terraform configuration for the robotics reference architecture. Deploys Azure resources including AKS with GPU node pools, Azure ML workspace, storage, and OSMO backend services (PostgreSQL, Redis).

## Prerequisites

- Azure CLI authenticated (`az login`)
- Terraform 1.5+ (`terraform version`)
- GPU VM quota in target region (e.g., `Standard_NV36ads_A10_v5`)
- Subscription initialized (`source ../000-prerequisites/az-sub-init.sh`)

## Quick Start

```bash
cd deploy/001-iac

# Initialize subscription
source ../000-prerequisites/az-sub-init.sh

# Configure (edit values as needed)
cp terraform.tfvars.example terraform.tfvars

# Deploy
terraform init && terraform apply
```

## Configuration

Key variables in `terraform.tfvars`:

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Deployment environment | - |
| `resource_prefix` | Resource naming prefix | - |
| `location` | Azure region | - |
| `node_pools.gpu.vm_size` | GPU VM SKU | `Standard_NV36ads_A10_v5` |
| `should_deploy_postgresql` | Deploy PostgreSQL for OSMO | `true` |
| `should_deploy_redis` | Deploy Redis for OSMO | `true` |

See [variables.tf](variables.tf) for all configuration options.

### OSMO Workload Identity

Enable managed identity for OSMO services (recommended for production):

```hcl
osmo_config = {
  should_enable_identity   = true
  should_federate_identity = true
  control_plane_namespace  = "osmo-control-plane"
  operator_namespace       = "osmo-operator"
  workflows_namespace      = "osmo-workflows"
}
```

## Modules

| Module | Purpose |
|--------|---------|
| [platform](modules/platform/) | Networking, storage, Key Vault, ML workspace, PostgreSQL, Redis |
| [sil](modules/sil/) | AKS cluster with GPU node pools and AzureML extension |
| [vpn](modules/vpn/) | VPN Gateway module (used by vpn/ standalone deployment) |

## Outputs

```bash
# View all outputs
terraform output

# Get AKS cluster name
terraform output -json aks_cluster | jq -r '.name'

# OSMO connection details (PostgreSQL, Redis)
terraform output postgresql_connection_info
terraform output managed_redis_connection_info
```

## Optional Components

These standalone deployments extend the base infrastructure.

### VPN Gateway

Point-to-Site VPN for secure remote access to private endpoints:

```bash
cd vpn
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

See [vpn/README.md](vpn/README.md) for client setup and AAD authentication.

### Private DNS for OSMO UI

Configure DNS resolution for the OSMO UI LoadBalancer (requires VPN):

```bash
cd dns
terraform apply -var="osmo_loadbalancer_ip=10.0.x.x"
```

See [dns/README.md](dns/README.md) for details.

### Automation Account

Azure Automation resources for scheduled operations:

```bash
cd automation
terraform init && terraform apply
```

See [automation/README.md](automation/README.md) for runbook configuration.

## Destroy Infrastructure

Remove Azure resources deployed by Terraform. Clean up cluster components first.

### Prerequisites

- Cluster components uninstalled (see [002-setup/README.md](../002-setup/README.md#cleanup))
- Terraform state accessible
- Azure CLI authenticated

### Option A: Terraform Destroy

Preserves Terraform state and allows redeployment:

```bash
cd deploy/001-iac

# Preview resources to be destroyed
terraform plan -destroy -var-file=terraform.tfvars

# Destroy infrastructure
terraform destroy -var-file=terraform.tfvars
```

If VPN was deployed separately:

```bash
cd vpn
terraform destroy -var-file=terraform.tfvars
```

### Option B: Delete Resource Group

Fastest cleanup method (completely deletes the resource group):

```bash
# Get resource group name
terraform output -raw resource_group | jq -r '.name'

# Or check Azure portal / terraform.tfvars for naming pattern
# Default: <resource_prefix>-<environment>-rg

# Delete entire resource group
az group delete --name <resource-group-name> --yes

# For async deletion (returns immediately)
az group delete --name <resource-group-name> --yes --no-wait
```

Resource group deletion removes all contained resources regardless of how they were created.

### Cleanup Order

Follow this order to avoid dependency failures:

| Order | Component | Command |
|:-----:|-----------|--------|
| 1 | OSMO Backend | `../002-setup/cleanup/uninstall-osmo-backend.sh` |
| 2 | OSMO Control Plane | `../002-setup/cleanup/uninstall-osmo-control-plane.sh` |
| 3 | AzureML Extension | `../002-setup/cleanup/uninstall-azureml-extension.sh` |
| 4 | GPU Infrastructure | `../002-setup/cleanup/uninstall-robotics-charts.sh` |
| 5 | VPN (if deployed) | `cd vpn && terraform destroy -var-file=terraform.tfvars` |
| 6 | Main Infrastructure | `terraform destroy -var-file=terraform.tfvars` |

### Troubleshooting Destroy

**Resources stuck deleting**: Some resources (Private Endpoints, AKS) may take 10-15 minutes. Check status:

```bash
az resource list --resource-group <rg> --query "[].{name:name, type:type}" -o table
```

**Terraform state mismatch**: If resources were manually deleted:

```bash
# Refresh state to match Azure
terraform refresh -var-file=terraform.tfvars

# Then destroy
terraform destroy -var-file=terraform.tfvars
```

**Locks preventing deletion**: Remove resource locks if present:

```bash
az lock list --resource-group <rg> -o table
az lock delete --name <lock-name> --resource-group <rg>
```

## Directory Structure

```
001-iac/
├── main.tf                 # Module composition
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── versions.tf             # Provider versions
├── terraform.tfvars        # Configuration (gitignored)
├── modules/
│   ├── platform/           # Shared Azure services
│   ├── sil/                # AKS + ML extension
│   └── vpn/                # VPN Gateway module
├── vpn/                    # Standalone VPN deployment
├── dns/                    # OSMO UI DNS configuration
└── automation/             # Automation account
```
