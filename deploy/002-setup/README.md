# 002-setup

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

### Scenario 1: Access Keys + NGC (Development)

Simplest setup using storage account keys and NVIDIA NGC registry.

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
export NGC_API_KEY="your-ngc-token"

./01-deploy-robotics-charts.sh
./02-deploy-azureml-extension.sh
./03-deploy-osmo-control-plane.sh --ngc-token "$NGC_API_KEY" --use-access-keys
./04-deploy-osmo-backend.sh --ngc-token "$NGC_API_KEY" --use-access-keys
```

### Scenario 2: Workload Identity + NGC (Production)

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
export NGC_API_KEY="your-ngc-token"

./01-deploy-robotics-charts.sh
./02-deploy-azureml-extension.sh
./03-deploy-osmo-control-plane.sh --ngc-token "$NGC_API_KEY"
./04-deploy-osmo-backend.sh --ngc-token "$NGC_API_KEY"
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

# Set versions (check NGC for latest: https://catalog.ngc.nvidia.com/orgs/nvidia/teams/osmo)
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
    --image "osmo/${img}:${OSMO_VERSION}" \
    --username '$oauthtoken' --password "$NGC_API_KEY"
done

# Import Helm charts
helm registry login nvcr.io --username '$oauthtoken' --password "$NGC_API_KEY"
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

| | Access Keys + NGC | Workload Identity + NGC | Workload Identity + ACR |
|---|:---:|:---:|:---:|
| Storage Auth | Access Keys | Workload Identity | Workload Identity |
| Registry | NGC | NGC | Private ACR |
| NGC Token | Required | Required | Import only |
| Security | Development | Production | Enterprise |
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
| `--ngc-token TOKEN` | NGC API token (required unless `--use-acr`) |
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
| `cleanup/uninstall-azureml-extension.sh` | Remove AzureML extension |
