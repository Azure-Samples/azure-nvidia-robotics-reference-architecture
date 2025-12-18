# Infrastructure as Code

Terraform configuration for the robotics reference architecture. Deploys Azure resources including AKS with GPU node pools, Azure ML workspace, storage, and OSMO backend services (PostgreSQL, Redis).

## Prerequisites

| Tool | Version | Installation |
|------|---------|--------------|
| Azure CLI | Latest | `az login` |
| Terraform | 1.5+ | `terraform version` |
| GPU VM quota | Region-specific | e.g., `Standard_NV36ads_A10_v5` |

## Quick Start

```bash
cd deploy/001-iac
source ../000-prerequisites/az-sub-init.sh
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply -var-file=terraform.tfvars
```

## Configuration

### Core Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `environment` | Deployment environment (dev, test, prod) | Yes |
| `resource_prefix` | Resource naming prefix | Yes |
| `location` | Azure region | Yes |
| `instance` | Instance identifier | No (default: "001") |
| `tags` | Resource group tags | No (default: {}) |

### AKS System Node Pool

| Variable | Description | Default |
|----------|-------------|---------|
| `system_node_pool_vm_size` | VM size for AKS system node pool | `Standard_D8ds_v5` |
| `system_node_pool_node_count` | Number of nodes for AKS system node pool | `1` |
| `system_node_pool_zones` | Availability zones for system node pool | `null` |
| `system_node_pool_enable_auto_scaling` | Enable auto-scaling for system node pool | `false` |
| `system_node_pool_min_count` | Minimum nodes when auto-scaling enabled | `null` |
| `system_node_pool_max_count` | Maximum nodes when auto-scaling enabled | `null` |

### Feature Flags

| Variable | Description | Default |
|----------|-------------|---------|
| `should_enable_nat_gateway` | Deploy NAT Gateway for outbound connectivity | `true` |
| `should_enable_private_endpoint` | Deploy private endpoints and DNS zones | `true` |
| `should_enable_public_network_access` | Allow public access to resources | `true` |
| `should_deploy_postgresql` | Deploy PostgreSQL Flexible Server for OSMO | `true` |
| `should_deploy_redis` | Deploy Azure Managed Redis for OSMO | `true` |

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

See [variables.tf](variables.tf) for all configuration options.

## Architecture

### Module Structure

```text
Root Module (001-iac/)
├── Platform Module         # Shared Azure services
│   ├── Networking          # VNet, subnets, NAT Gateway, DNS resolver
│   ├── Security            # Key Vault (RBAC), managed identities
│   ├── Observability       # Log Analytics, Monitor, Grafana, AMPLS
│   ├── Storage             # Storage Account, ACR
│   ├── Machine Learning    # AzureML Workspace
│   └── OSMO Backend        # PostgreSQL, Redis
│
└── SiL Module              # AKS-specific infrastructure
    ├── AKS Cluster         # Azure CNI Overlay, workload identity
    ├── GPU Node Pools      # Configurable via node_pools variable
    └── Observability       # Container Insights, Prometheus DCRs
```

### Resources by Category

| Category | Resources |
|----------|-----------|
| Networking | VNet, subnets (main, PE, AKS, GPU pools), NSG, NAT Gateway, DNS Private Resolver |
| Security | Key Vault (RBAC mode), ML identity, OSMO identity |
| Observability | Log Analytics, App Insights, Monitor Workspace, Grafana, DCE, AMPLS |
| Storage | Storage Account (blob/file), Container Registry (Premium) |
| Machine Learning | AzureML Workspace |
| AKS | Cluster with Azure CNI Overlay, system pool, GPU node pools |
| Private DNS | 11 core zones (Key Vault, Storage, ACR, ML, AKS, Monitor) |
| OSMO Services | PostgreSQL Flexible Server (HA), Azure Managed Redis |

### Conditional Resources

| Condition | Resources Created |
|-----------|-------------------|
| `should_enable_private_endpoint` | Private endpoints, 11+ DNS zones, DNS resolver, AMPLS |
| `should_enable_nat_gateway` | NAT Gateway, Public IP, subnet associations |
| `should_deploy_postgresql` | PostgreSQL server, databases, delegated subnet, DNS zone |
| `should_deploy_redis` | Redis cache, private endpoint (if PE enabled), DNS zone |

## Modules

| Module | Purpose |
|--------|---------|
| [platform](modules/platform/) | Networking, storage, Key Vault, ML workspace, PostgreSQL, Redis |
| [sil](modules/sil/) | AKS cluster with GPU node pools |
| [vpn](modules/vpn/) | VPN Gateway module (used by vpn/ standalone deployment) |

## Outputs

```bash
terraform output

# AKS cluster details
terraform output -json aks_cluster | jq -r '.name'

# OSMO connection details
terraform output postgresql_connection_info
terraform output managed_redis_connection_info

# Key Vault name (for 002-setup scripts)
terraform output key_vault_name

# DNS server IP (for VPN clients)
terraform output dns_server_ip
```

## Optional Components

Standalone deployments extend the base infrastructure.

### VPN Gateway

Point-to-Site VPN for secure remote access to private endpoints:

```bash
cd vpn
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply -var-file=terraform.tfvars
```

See [vpn/README.md](vpn/README.md) for client setup and AAD authentication.

### Private DNS for OSMO UI

Configure DNS resolution for the OSMO UI LoadBalancer after setup from `deploy/002-setup/03-deploy-osmo-control-plane.sh` (requires VPN):

```bash
cd dns
terraform init
terraform apply -var="osmo_loadbalancer_ip=10.0.x.x"
```

See [dns/README.md](dns/README.md) for details.

### Automation Account

Scheduled startup of AKS and PostgreSQL to reduce costs:

```bash
cd automation
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply -var-file=terraform.tfvars
```

See [automation/README.md](automation/README.md) for schedule configuration.

## Destroy Infrastructure

Remove Azure resources deployed by Terraform. Clean up cluster components first.

### Cleanup Order

```bash
# 1. OSMO Backend
../002-setup/cleanup/uninstall-osmo-backend.sh

# 2. OSMO Control Plane
../002-setup/cleanup/uninstall-osmo-control-plane.sh

# 3. AzureML Extension
../002-setup/cleanup/uninstall-azureml-extension.sh

# 4. GPU Infrastructure
../002-setup/cleanup/uninstall-robotics-charts.sh

# 5. VPN (if deployed)
cd vpn && terraform destroy -var-file=terraform.tfvars

# 6. Main Infrastructure
terraform destroy -var-file=terraform.tfvars
```

### Terraform Destroy

Preserves state and allows redeployment:

```bash
cd deploy/001-iac
terraform plan -destroy -var-file=terraform.tfvars
terraform destroy -var-file=terraform.tfvars
```

### Delete Resource Group

Fastest cleanup method (removes all resources regardless of how they were created):

```bash
terraform output -raw resource_group | jq -r '.name'
az group delete --name <resource-group-name> --yes --no-wait
```

### Troubleshooting Destroy

**Resources stuck deleting**: Some resources (Private Endpoints, AKS) may take 10-15 minutes:

```bash
az resource list --resource-group <rg> --query "[].{name:name, type:type}" -o table
```

**Terraform state mismatch**: If resources were manually deleted:

```bash
terraform refresh -var-file=terraform.tfvars
terraform destroy -var-file=terraform.tfvars
```

**Locks preventing deletion**:

```bash
az lock list --resource-group <rg> -o table
az lock delete --name <lock-name> --resource-group <rg>
```

## Directory Structure

```text
001-iac/
├── main.tf                            # Module composition
├── variables.tf                       # Input variables
├── outputs.tf                         # Output values
├── versions.tf                        # Provider versions
├── terraform.tfvars                   # Configuration (gitignored)
├── modules/
│   ├── platform/                      # Shared Azure services
│   │   ├── networking.tf              # VNet, subnets, NAT Gateway, DNS resolver
│   │   ├── security.tf                # Key Vault, managed identities
│   │   ├── observability.tf           # LAW, Monitor, Grafana, AMPLS
│   │   ├── storage.tf                 # Storage Account
│   │   ├── acr.tf                     # Container Registry
│   │   ├── azureml.tf                 # ML Workspace
│   │   ├── postgresql.tf              # PostgreSQL Flexible Server
│   │   ├── redis.tf                   # Azure Managed Redis
│   │   └── private-dns-zones.tf       # Private DNS zones
│   ├── sil/                           # AKS cluster
│   │   ├── aks.tf                     # AKS cluster, node pools
│   │   ├── networking.tf              # AKS subnets, NAT associations
│   │   ├── observability.tf           # Container Insights, Prometheus DCRs
│   │   └── osmo-federated-credentials.tf  # OSMO workload identity
│   ├── vpn/                           # VPN Gateway module
│   └── automation/                    # Automation Account module
├── vpn/                               # Standalone VPN deployment
├── dns/                               # OSMO UI DNS configuration
└── automation/                        # Scheduled startup deployment
```
