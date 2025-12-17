# Setup

AKS cluster configuration for robotics workloads with AzureML and NVIDIA OSMO.

## Prerequisites

- Terraform infrastructure deployed (`cd ../001-iac && terraform apply`)
- Azure CLI authenticated (`az login`)
- kubectl, Helm 3.x, jq installed
- OSMO CLI (`osmo`) for backend deployment

## Quick Start

```bash
# Connect to cluster (values from terraform output)
az aks get-credentials --resource-group <rg> --name <aks>

# Deploy GPU infrastructure (required for all paths)
./01-deploy-robotics-charts.sh

# Choose your path:
# - AzureML: ./02-deploy-azureml-extension.sh
# - OSMO:    ./03-deploy-osmo-control-plane.sh && ./04-deploy-osmo-backend.sh
```

## Deployment Scenarios

Three authentication and registry configurations are supported. Choose based on your security requirements.

### Scenario 1: Access Keys

Simplest setup using storage account keys and public NVIDIA registry.

```bash
# terraform.tfvars
osmo_config = {
  should_enable_identity   = false
  should_federate_identity = false
  control_plane_namespace  = "osmo-control-plane"
  operator_namespace       = "osmo-operator"
  workflows_namespace      = "osmo-workflows"
}
```

```bash
./01-deploy-robotics-charts.sh
./02-deploy-azureml-extension.sh
./03-deploy-osmo-control-plane.sh --use-access-keys
./04-deploy-osmo-backend.sh --use-access-keys
```

### Scenario 2: Workload Identity

Secure, key-less authentication via Azure Workload Identity.

```bash
# terraform.tfvars
osmo_config = {
  should_enable_identity   = true
  should_federate_identity = true
  control_plane_namespace  = "osmo-control-plane"
  operator_namespace       = "osmo-operator"
  workflows_namespace      = "osmo-workflows"
}
```

```bash
./01-deploy-robotics-charts.sh
./02-deploy-azureml-extension.sh
./03-deploy-osmo-control-plane.sh
./04-deploy-osmo-backend.sh
```

Scripts auto-detect the OSMO managed identity from Terraform outputs and configure ServiceAccount annotations.

### Scenario 3: Workload Identity + Private ACR (Air-Gapped)

Enterprise deployment using private Azure Container Registry.

**Pre-requisite**: Import images to ACR before deployment.

```bash
# Get ACR name and import images
cd ../001-iac
ACR_NAME=$(terraform output -json container_registry | jq -r '.value.name')
az acr login --name "$ACR_NAME"

# Set versions
OSMO_VERSION="${OSMO_VERSION:-6.0.0}"
CHART_VERSION="${CHART_VERSION:-1.0.0}"

OSMO_IMAGES=(
  service router web-ui worker logger agent
  backend-listener backend-worker client
  delayed-job-monitor init-container
)
for img in "${OSMO_IMAGES[@]}"; do
  az acr import --name "$ACR_NAME" \
    --source "nvcr.io/nvidia/osmo/${img}:${OSMO_VERSION}" \
    --image "osmo/${img}:${OSMO_VERSION}"
done

# Import Helm charts
for chart in osmo router ui backend-operator; do
  helm pull "oci://nvcr.io/nvidia/osmo/${chart}" --version "$CHART_VERSION"
  helm push "${chart}-${CHART_VERSION}.tgz" "oci://${ACR_NAME}.azurecr.io/helm"
  rm "${chart}-${CHART_VERSION}.tgz"
done
```

```bash
cd ../002-setup
./01-deploy-robotics-charts.sh
./02-deploy-azureml-extension.sh
./03-deploy-osmo-control-plane.sh --use-acr
./04-deploy-osmo-backend.sh --use-acr
```

## Scenario Comparison

| | Access Keys | Workload Identity | Workload Identity + ACR |
|---|:---:|:---:|:---:|
| Storage Auth | Access Keys | Workload Identity | Workload Identity |
| Registry | nvcr.io | nvcr.io | Private ACR |
| Air-Gap | ✗ | ✗ | ✓ |

## Scripts

| Script | Purpose |
|--------|---------|
| `01-deploy-robotics-charts.sh` | GPU Operator, KAI Scheduler |
| `02-deploy-azureml-extension.sh` | AzureML K8s extension, compute attach |
| `03-deploy-osmo-control-plane.sh` | OSMO service, router, web-ui |
| `04-deploy-osmo-backend.sh` | Backend operator, workflow storage |

## Script Flags

| Flag | Description |
|------|-------------|
| `--use-access-keys` | Storage account keys instead of workload identity |
| `--use-acr` | Pull from Terraform-deployed ACR |
| `--acr-name NAME` | Specify alternate ACR |
| `--config-preview` | Print config and exit |

## Configuration

Scripts read from Terraform outputs in `../001-iac/`. Override with environment variables:

| Variable | Description |
|----------|-------------|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription |
| `AZURE_RESOURCE_GROUP` | Resource group |
| `AKS_CLUSTER_NAME` | Cluster name |

## Verification

```bash
# Check pods
kubectl get pods -n gpu-operator
kubectl get pods -n azureml
kubectl get pods -n osmo-control-plane
kubectl get pods -n osmo-operator

# OSMO connectivity
osmo info
osmo backend list

# Workload identity (if enabled)
kubectl get sa -n osmo-control-plane osmo-service -o yaml | grep azure.workload.identity
```

## Troubleshooting

```bash
# Workload identity
az identity federated-credential list --identity-name osmo-identity --resource-group <rg>
az aks show -g <rg> -n <aks> --query oidcIssuerProfile.issuerUrl

# ACR pull
az aks check-acr --name <aks> --resource-group <rg> --acr <acr>
az acr repository show-tags --name <acr> --repository osmo/osmo-service

# Storage access
kubectl get secret postgres-secret -n osmo-control-plane
kubectl describe sa osmo-service -n osmo-control-plane
```

## Directory Structure

```
002-setup/
├── 01-deploy-robotics-charts.sh
├── 02-deploy-azureml-extension.sh
├── 03-deploy-osmo-control-plane.sh
├── 04-deploy-osmo-backend.sh
├── cleanup/                    # Uninstall scripts
├── config/                     # OSMO configuration templates
├── lib/                        # Shared functions
├── manifests/                  # Kubernetes manifests
├── optional/                   # Volcano scheduler, validation
└── values/                     # Helm values files
```

## Optional Scripts

| Script | Purpose |
|--------|---------|
| `optional/deploy-volcano-scheduler.sh` | Volcano (alternative to KAI) |
| `optional/validate-gpu-metrics.sh` | GPU metrics verification |

## Cleanup

Uninstall scripts in `cleanup/` remove cluster components in reverse deployment order.

### Cleanup Scripts

| Script | Removes |
|--------|---------|
| `cleanup/uninstall-osmo-backend.sh` | Backend operator, workflow namespaces |
| `cleanup/uninstall-osmo-control-plane.sh` | OSMO service, router, web-ui |
| `cleanup/uninstall-azureml-extension.sh` | ML extension, compute target, FICs |
| `cleanup/uninstall-robotics-charts.sh` | GPU Operator, KAI Scheduler |

### Uninstall Order

Run scripts in this order to avoid dependency issues:

```bash
cd cleanup

# 1. OSMO backend (workflows namespace, operator)
./uninstall-osmo-backend.sh

# 2. OSMO control plane (service, router, UI)
./uninstall-osmo-control-plane.sh

# 3. AzureML extension (extension, compute target)
./uninstall-azureml-extension.sh

# 4. GPU infrastructure (operator, scheduler)
./uninstall-robotics-charts.sh
```

### Data Preservation

By default, uninstall scripts preserve data. Use flags for complete removal:

| Script | Preservation Flag | Description |
|--------|-------------------|-------------|
| `uninstall-osmo-backend.sh` | `--delete-container` | Deletes blob container with workflow artifacts |
| `uninstall-osmo-control-plane.sh` | `--delete-mek` | Removes encryption key ConfigMap |
| `uninstall-osmo-control-plane.sh` | `--purge-postgres` | Drops OSMO tables from PostgreSQL |
| `uninstall-osmo-control-plane.sh` | `--purge-redis` | Flushes OSMO keys from Redis |
| `uninstall-robotics-charts.sh` | `--delete-namespaces` | Removes gpu-operator, kai-scheduler namespaces |
| `uninstall-robotics-charts.sh` | `--delete-crds` | Removes GPU Operator CRDs |

### Full Component Cleanup

Remove everything including data:

```bash
cd cleanup
./uninstall-osmo-backend.sh --delete-container
./uninstall-osmo-control-plane.sh --purge-postgres --purge-redis --delete-mek
./uninstall-azureml-extension.sh --force
./uninstall-robotics-charts.sh --delete-namespaces --delete-crds
```

### Selective Cleanup

Remove only specific components:

```bash
# OSMO only (preserve AzureML and GPU infrastructure)
./uninstall-osmo-backend.sh
./uninstall-osmo-control-plane.sh

# AzureML only (preserve OSMO)
./uninstall-azureml-extension.sh
```

After cluster cleanup, proceed to [001-iac](../001-iac/README.md#destroy-infrastructure) to destroy Azure infrastructure.
