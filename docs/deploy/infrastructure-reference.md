---
title: Infrastructure Reference
description: Architecture, module structure, outputs, and troubleshooting for the Terraform deployment
author: Microsoft Robotics-AI Team
ms.date: 2026-02-22
ms.topic: reference
keywords:
  - architecture
  - modules
  - terraform
  - troubleshooting
---

Architecture details, module structure, Terraform outputs, and troubleshooting for the infrastructure deployment.

> [!NOTE]
> This page is part of the [deployment guide](README.md). Return there for the full deployment sequence.

## 🏗️ Architecture

### Directory Structure

```text
001-iac/
├── main.tf                            # Module composition
├── variables.tf                       # Input variables
├── outputs.tf                         # Output values
├── versions.tf                        # Provider versions
├── terraform.tfvars                   # Configuration (gitignored)
├── modules/
│   ├── platform/
│   │   ├── networking.tf              # VNet, subnets, NAT Gateway, DNS resolver
│   │   ├── security.tf                # Key Vault, managed identities
│   │   ├── observability.tf           # LAW, Monitor, Grafana, AMPLS
│   │   ├── storage.tf                 # Storage Account
│   │   ├── acr.tf                     # Container Registry
│   │   ├── azureml.tf                 # ML Workspace
│   │   ├── postgresql.tf              # PostgreSQL Flexible Server
│   │   ├── redis.tf                   # Azure Managed Redis
│   │   └── private-dns-zones.tf       # Private DNS zones
│   ├── sil/
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

| Category         | Resources                                                                        |
|------------------|----------------------------------------------------------------------------------|
| Networking       | VNet, subnets (main, PE, AKS, GPU pools), NSG, NAT Gateway, DNS Private Resolver |
| Security         | Key Vault (RBAC mode), ML identity, OSMO identity                                |
| Observability    | Log Analytics, App Insights, Monitor Workspace, Grafana, DCE, AMPLS              |
| Storage          | Storage Account (blob/file), Container Registry (Premium)                        |
| Machine Learning | AzureML Workspace                                                                |
| AKS              | Cluster with Azure CNI Overlay, system pool, GPU node pools                      |
| Private DNS      | 11 core zones (Key Vault, Storage, ACR, ML, AKS, Monitor)                        |
| OSMO Services    | PostgreSQL Flexible Server (HA), Azure Managed Redis                             |

### Conditional Resources

| Condition                        | Resources Created                                        |
|----------------------------------|----------------------------------------------------------|
| `should_enable_private_endpoint` | Private endpoints, 11+ DNS zones, DNS resolver, AMPLS    |
| `should_enable_nat_gateway`      | NAT Gateway, Public IP, subnet associations              |
| `should_deploy_postgresql`       | PostgreSQL server, databases, delegated subnet, DNS zone |
| `should_deploy_redis`            | Redis cache, private endpoint (if PE enabled), DNS zone  |

## 📦 Modules

| Module                                             | Purpose                                                         |
|----------------------------------------------------|-----------------------------------------------------------------|
| [platform](../../deploy/001-iac/modules/platform/) | Networking, storage, Key Vault, ML workspace, PostgreSQL, Redis |
| [sil](../../deploy/001-iac/modules/sil/)           | AKS cluster with GPU node pools                                 |
| [vpn](../../deploy/001-iac/modules/vpn/)           | VPN Gateway module (used by vpn/ standalone deployment)         |

## 📤 Outputs

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

## 🔧 Optional Components

Standalone deployments extend the base infrastructure.

### VPN Gateway

Point-to-Site VPN for secure remote access to the private AKS cluster and Azure services.

> [!IMPORTANT]
> **Required for default configuration.** With `should_enable_private_aks_cluster = true`, you cannot run `kubectl` commands or cluster setup scripts without VPN connectivity. To skip VPN, set `should_enable_private_aks_cluster = false` in your `terraform.tfvars`.

```bash
cd vpn
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply -var-file=terraform.tfvars
```

See [VPN Gateway](vpn.md) for configuration options and VPN client setup.

### Private DNS for OSMO UI

Configure DNS resolution for the OSMO UI LoadBalancer after setup from `deploy/002-setup/03-deploy-osmo-control-plane.sh` (requires VPN):

```bash
cd dns
terraform init
terraform apply -var="osmo_loadbalancer_ip=10.0.x.x"
```

See [dns/README.md](../../deploy/001-iac/dns/README.md) for details.

### Automation Account

Scheduled startup of AKS and PostgreSQL to reduce costs:

```bash
cd automation
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply -var-file=terraform.tfvars
```

See [automation/README.md](../../deploy/001-iac/automation/README.md) for schedule configuration.

## 🔍 Troubleshooting

Issues and resolutions encountered during infrastructure deployment and destroy.

### Destroy Takes a Long Time

Terraform destroy removes resources in dependency order. Private Endpoints, AKS clusters, and PostgreSQL servers commonly take 5-10 minutes each. Full destruction typically takes 20-30 minutes.

Monitor remaining resources during destruction:

```bash
az resource list --resource-group <resource-group> --query "[].{name:name, type:type}" -o table
```

### Soft-Deleted Resources Block Redeployment

Azure retains certain deleted resources in a soft-deleted state. Redeployment fails when Terraform attempts to create a resource with the same name as a soft-deleted one.

| Resource           | Soft Delete      | Retention Period         | Blocks Redeployment             |
|--------------------|------------------|--------------------------|---------------------------------|
| Key Vault          | Mandatory        | 7-90 days (configurable) | Yes                             |
| Azure ML Workspace | Mandatory        | 14 days (fixed)          | Yes                             |
| Container Registry | Opt-in (preview) | 1-90 days (configurable) | No (disabled by default)        |
| Storage Account    | Recovery only    | 14 days                  | No (same-name creation allowed) |

#### Purge Soft-Deleted Key Vault

```bash
az keyvault list-deleted --subscription <subscription-id> --resource-type vault -o table
az keyvault purge --subscription <subscription-id> --name <key-vault-name>
```

> [!NOTE]
> Key Vaults with `purge_protection_enabled = true` cannot be purged and must wait for retention expiry. This configuration defaults to `should_enable_purge_protection = false`.

#### Purge Soft-Deleted Azure ML Workspace

Azure ML workspaces enter soft-delete for 14 days after deletion. List via Azure Portal under **Azure Machine Learning > Manage deleted workspaces**.

```bash
az ml workspace delete \
  --name <workspace-name> \
  --resource-group <resource-group> \
  --permanently-delete
```

### Terraform State Mismatch

Resources manually deleted or created outside Terraform cause state mismatches.

#### Refresh State for Deleted Resources

```bash
terraform refresh -var-file=terraform.tfvars
terraform plan -var-file=terraform.tfvars
```

#### Import Existing Resources

```bash
terraform plan -var-file=terraform.tfvars

terraform import -var-file=terraform.tfvars '<resource_address>' '<azure_resource_id>'

# Example: Import a resource group
terraform import -var-file=terraform.tfvars \
  'module.platform.azurerm_resource_group.main' \
  '/subscriptions/<sub-id>/resourceGroups/<rg-name>'

# Example: Import an AKS cluster
terraform import -var-file=terraform.tfvars \
  'module.sil.azurerm_kubernetes_cluster.main' \
  '/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.ContainerService/managedClusters/<aks-name>'
```

After import, run `terraform plan` to verify the imported resource matches the configuration.

### Resource Locks Prevent Deletion

```bash
az lock list --resource-group <resource-group> -o table
az lock delete --name <lock-name> --resource-group <resource-group>
```

## 🔗 Related

- [Infrastructure Deployment](infrastructure.md) — deploy and configure Terraform resources

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
