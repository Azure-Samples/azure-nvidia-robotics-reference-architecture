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
