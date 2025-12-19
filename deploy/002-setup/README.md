# Setup

AKS cluster configuration for robotics workloads with AzureML and NVIDIA OSMO.

## 📋 Prerequisites

- Terraform infrastructure deployed (`cd ../001-iac && terraform apply`)
- VPN connected (if using default private AKS cluster)
- Azure CLI authenticated (`az login`)
- kubectl, Helm 3.x, jq installed
- OSMO CLI (`osmo`) for backend deployment

> [!IMPORTANT]
> The default infrastructure deploys a **private AKS cluster**. You must deploy the VPN Gateway and connect before running these scripts. See [VPN setup](../001-iac/vpn/README.md#-vpn-client-setup) for instructions. Without VPN, `kubectl` commands fail with `no such host` errors.
>
> To skip VPN, set `should_enable_private_aks_cluster = false` in your Terraform configuration. See [Network Configuration Modes](../001-iac/README.md#network-configuration-modes).

### Azure RBAC Permissions

For least-privilege access:

| Role | Scope | Purpose |
|------|-------|---------|
| Azure Kubernetes Service Cluster User Role | AKS Cluster | Get cluster credentials |
| Contributor | Resource Group | Extension and FIC creation |
| Key Vault Secrets User | Key Vault | Read PostgreSQL/Redis credentials |
| Storage Blob Data Contributor | Storage Account | Create workflow containers |

## 🚀 Quick Start

```bash
# Connect to cluster (values from terraform output)
az aks get-credentials --resource-group <rg> --name <aks>

# Verify connectivity (requires VPN for private clusters)
kubectl cluster-info
# Expected: Kubernetes control plane is running at https://...
# If you see "no such host" errors, connect to VPN first

# Deploy GPU infrastructure (required for all paths)
./01-deploy-robotics-charts.sh

# Choose your path:
# - AzureML: ./02-deploy-azureml-extension.sh
# - OSMO:    ./03-deploy-osmo-control-plane.sh && ./04-deploy-osmo-backend.sh
```

## 🔐 Deployment Scenarios

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
./03-deploy-osmo-control-plane.sh
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

## ⚖️ Scenario Comparison

| | Access Keys | Workload Identity | Workload Identity + ACR |
|---|:---:|:---:|:---:|
| Storage Auth | Access Keys | Workload Identity | Workload Identity |
| Registry | nvcr.io | nvcr.io | Private ACR |
| Air-Gap | ✗ | ✗ | ✓ |

## 🔒 Security Considerations for Public Deployments

When deploying with `should_enable_private_endpoint = false`, cluster endpoints are publicly accessible. Secure the following components:

### AzureML Extension

The AzureML inference router (`azureml-fe`) handles incoming requests. For public deployments:

- Enable HTTPS with TLS certificates (`allowInsecureConnections=False`)
- Configure `sslSecret` or provide certificate files
- Consider using `internalLoadBalancerProvider=azure` for internal-only access

See [Secure Kubernetes online endpoints](https://learn.microsoft.com/azure/machine-learning/how-to-secure-kubernetes-online-endpoint) and [Inference routing configuration](https://learn.microsoft.com/azure/machine-learning/how-to-kubernetes-inference-routing-azureml-fe).

### OSMO UI

The OSMO web interface requires authentication for public access:

- Enable Keycloak for user authentication and authorization
- Configure OIDC integration with Azure AD or other identity providers

See [OSMO Keycloak configuration](https://nvidia.github.io/OSMO/main/deployment_guide/getting_started/deploy_service.html#step-2-configure-keycloak).

## 📜 Scripts

| Script | Purpose |
|--------|---------|
| `01-deploy-robotics-charts.sh` | GPU Operator, KAI Scheduler |
| `02-deploy-azureml-extension.sh` | AzureML K8s extension, compute attach |
| `03-deploy-osmo-control-plane.sh` | OSMO service, router, web-ui |
| `04-deploy-osmo-backend.sh` | Backend operator, workflow storage |

## 🚩 Script Flags

| Flag | Scripts | Description |
|------|---------|-------------|
| `--use-access-keys` | `04-deploy-osmo-backend.sh` | Storage account keys instead of workload identity |
| `--use-acr` | `03-deploy-osmo-control-plane.sh`, `04-deploy-osmo-backend.sh` | Pull from Terraform-deployed ACR |
| `--acr-name NAME` | `03-deploy-osmo-control-plane.sh`, `04-deploy-osmo-backend.sh` | Specify alternate ACR |
| `--config-preview` | All | Print config and exit |

## ⚙️ Configuration

Scripts read from Terraform outputs in `../001-iac/`. Override with environment variables:

| Variable | Description |
|----------|-------------|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription |
| `AZURE_RESOURCE_GROUP` | Resource group |
| `AKS_CLUSTER_NAME` | Cluster name |

## ✅ Verification

```bash
# Check pods
kubectl get pods -n gpu-operator
kubectl get pods -n azureml
kubectl get pods -n osmo-control-plane
kubectl get pods -n osmo-operator

# Workload identity (if enabled)
kubectl get sa -n osmo-control-plane osmo-service -o yaml | grep azure.workload.identity
```

## 🔌 Accessing OSMO

OSMO services are deployed to the `osmo-control-plane` namespace. Access method depends on your network configuration.

### Via VPN (Default Private Cluster)

When connected to VPN, OSMO services are accessible via the internal load balancer:

| Service | URL |
|---------|-----|
| UI Dashboard | http://10.0.5.7 |
| API Service | http://10.0.5.7/api |

```bash
# Login to OSMO via internal load balancer
osmo login http://10.0.5.7 --method=dev --username=testuser

# Verify connection
osmo info
osmo backend list
```

> [!NOTE]
> The internal load balancer IP (`10.0.5.7`) is assigned by the AzureML nginx ingress controller. Verify the actual IP with: `kubectl get svc -n azureml azureml-nginx-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`

### Via Port-Forward (Public Cluster without VPN)

If `should_enable_private_aks_cluster = false` and you are not using VPN, use `kubectl port-forward`:

| Service | Command | Local URL |
|---------|---------|-----------|
| UI Dashboard | `kubectl port-forward svc/osmo-ui 3000:80 -n osmo-control-plane` | http://localhost:3000 |
| API Service | `kubectl port-forward svc/osmo-service 9000:80 -n osmo-control-plane` | http://localhost:9000 |
| Router | `kubectl port-forward svc/osmo-router 8080:80 -n osmo-control-plane` | http://localhost:8080 |

```bash
# Terminal 1: Start port-forward for API service
kubectl port-forward svc/osmo-service 9000:80 -n osmo-control-plane

# Terminal 2: Login and use OSMO CLI
osmo login http://localhost:9000 --method=dev --username=testuser

# Verify connection
osmo info
osmo backend list
```

For full OSMO functionality (UI + API + Router), run port-forwards in separate terminals:

```bash
# Terminal 1: API service (for osmo CLI)
kubectl port-forward svc/osmo-service 9000:80 -n osmo-control-plane

# Terminal 2: UI dashboard (for web browser)
kubectl port-forward svc/osmo-ui 3000:80 -n osmo-control-plane

# Terminal 3: Router (optional, for workflow exec/port-forward)
kubectl port-forward svc/osmo-router 8080:80 -n osmo-control-plane
```

> [!NOTE]
> When accessing OSMO through port-forwarding, `osmo workflow exec` and `osmo workflow port-forward` commands are not supported. These require the router service to be accessible via ingress.

## 🔍 Troubleshooting

### Private Cluster Connectivity

If you see `no such host` errors when running `kubectl` commands:

```text
E1219 15:11:03.714667 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list:
Get \"https://aks-xxx.privatelink.westus3.azmk8s.io:443/api?timeout=32s\":
dial tcp: lookup aks-xxx.privatelink.westus3.azmk8s.io on 10.255.255.254:53: no such host"
```

This indicates the AKS cluster has a private endpoint and your machine cannot resolve the private DNS name.

**Resolution:**

1. Deploy the VPN Gateway: `cd ../001-iac/vpn && terraform apply`
2. Download and import VPN client configuration (see [VPN client setup](../001-iac/vpn/README.md#-vpn-client-setup))
3. Connect to VPN using Azure VPN Client
4. Verify connectivity: `kubectl cluster-info`

**Alternative:** Redeploy infrastructure with `should_enable_private_aks_cluster = false` in your `terraform.tfvars` for a public AKS control plane. This allows `kubectl` access without VPN while keeping Azure services (Storage, Key Vault, ACR) private if `should_enable_private_endpoint = true`.

### Workload Identity

```bash
az identity federated-credential list --identity-name osmo-identity --resource-group <rg>
az aks show -g <rg> -n <aks> --query oidcIssuerProfile.issuerUrl
```

### ACR Pull

```bash
az aks check-acr --name <aks> --resource-group <rg> --acr <acr>
az acr repository show-tags --name <acr> --repository osmo/osmo-service
```

### Storage Access

```bash
kubectl get secret postgres-secret -n osmo-control-plane
kubectl describe sa osmo-service -n osmo-control-plane
```

## 📁 Directory Structure

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

## 🧩 Optional Scripts

| Script | Purpose |
|--------|---------|
| `optional/deploy-volcano-scheduler.sh` | Volcano (alternative to KAI) |
| `optional/uninstall-volcano-scheduler.sh` | Remove Volcano scheduler |
| `optional/add-user-to-platform.sh` | Add user to OSMO platform |

## 🗑️ Cleanup

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
