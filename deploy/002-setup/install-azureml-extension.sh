#!/usr/bin/env bash
set -euo pipefail

#######################################
# AzureML Extension Installation Script
#
# Installs Azure Machine Learning extension on AKS cluster via Azure CLI,
# attaches the cluster as a compute target, and creates GPU instance types.
# Reads Terraform outputs for cluster and workspace connection.
#
# Usage:
#   ./install-azureml-extension.sh [OPTIONS]
#
# Options:
#   --terraform-dir PATH      Path to terraform directory (default: ../001-iac)
#   --extension-name NAME     Extension name (default: azureml-<cluster_name>)
#   --compute-name NAME       Compute target name (default: aks-<cluster_name>)
#   --cluster-purpose PURPOSE Cluster purpose: DevTest or FastProd (default: DevTest)
#   --inference-router-ha     Enable inference router high availability
#   --secure-connections      Require secure connections (disable insecure)
#   --skip-volcano            Skip Volcano scheduler installation
#   --enable-prom-op          Enable Prometheus Operator (conflicts with Azure Monitor)
#   --skip-gpu-tolerations    Skip GPU spot node tolerations
#   --skip-compute-attach     Skip attaching cluster as compute target
#   --skip-instance-types     Skip creating GPU instance types
#   --help                    Show this help message
#
# Examples:
#   # Deploy with defaults (dev/test mode)
#   ./install-azureml-extension.sh
#
#   # Deploy with custom terraform directory
#   ./install-azureml-extension.sh --terraform-dir /path/to/terraform
#
#   # Production deployment with HA and secure connections
#   ./install-azureml-extension.sh --cluster-purpose FastProd --inference-router-ha --secure-connections
#
#   # Extension only (skip compute attach and instance types)
#   ./install-azureml-extension.sh --skip-compute-attach --skip-instance-types
#######################################

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
terraform_dir="${script_dir}/../001-iac"

# Default configuration
extension_name=""
compute_name=""
cluster_purpose="DevTest"
enable_training="true"
enable_inference="true"
inference_router_service_type="LoadBalancer"
inference_router_ha="false"
allow_insecure_connections="true"
install_nvidia_device_plugin="false"
install_dcgm_exporter="false"
install_volcano="true"
# Prometheus Operator disabled by default - conflicts with Azure Monitor Prometheus
install_prom_op="false"
enable_gpu_spot_tolerations="true"
skip_compute_attach="false"
skip_instance_types="false"

help="Usage: install-azureml-extension.sh [OPTIONS]

Installs Azure Machine Learning extension on AKS cluster via Azure CLI,
attaches the cluster as a compute target, and creates GPU instance types.

OPTIONS:
  --terraform-dir PATH      Path to terraform directory (default: ../001-iac)
  --extension-name NAME     Extension name (default: azureml-<cluster_name>)
  --compute-name NAME       Compute target name (default: aks-<cluster_name>)
  --cluster-purpose PURPOSE Cluster purpose: DevTest or FastProd (default: DevTest)
  --inference-router-ha     Enable inference router high availability
  --secure-connections      Require secure connections (disable insecure)
  --skip-volcano            Skip Volcano scheduler installation
  --enable-prom-op          Enable Prometheus Operator (conflicts with Azure Monitor)
  --skip-gpu-tolerations    Skip GPU spot node tolerations
  --skip-compute-attach     Skip attaching cluster as compute target
  --skip-instance-types     Skip creating GPU instance types
  --help                    Show this help message

EXAMPLES:
  # Deploy with defaults (dev/test mode)
  ./install-azureml-extension.sh

  # Deploy with custom terraform directory
  ./install-azureml-extension.sh --terraform-dir /path/to/terraform

  # Production deployment with HA and secure connections
  ./install-azureml-extension.sh --cluster-purpose FastProd --inference-router-ha --secure-connections
"

while [[ $# -gt 0 ]]; do
  case $1 in
    --terraform-dir)
      terraform_dir="$2"
      shift 2
      ;;
    --extension-name)
      extension_name="$2"
      shift 2
      ;;
    --compute-name)
      compute_name="$2"
      shift 2
      ;;
    --cluster-purpose)
      cluster_purpose="$2"
      shift 2
      ;;
    --inference-router-ha)
      inference_router_ha="true"
      shift
      ;;
    --secure-connections)
      allow_insecure_connections="false"
      shift
      ;;
    --skip-volcano)
      install_volcano="false"
      shift
      ;;
    --enable-prom-op)
      install_prom_op="true"
      shift
      ;;
    --skip-gpu-tolerations)
      enable_gpu_spot_tolerations="false"
      shift
      ;;
    --skip-compute-attach)
      skip_compute_attach="true"
      shift
      ;;
    --skip-instance-types)
      skip_instance_types="true"
      shift
      ;;
    --help)
      echo "${help}"
      exit 0
      ;;
    *)
      echo "${help}"
      echo
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ============================================================
# Prerequisites Check
# ============================================================

echo "Checking prerequisites..."
required_tools=(terraform az kubectl jq)
missing_tools=()
for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" &>/dev/null; then
    missing_tools+=("${tool}")
  fi
done

if [[ ${#missing_tools[@]} -gt 0 ]]; then
  echo "Error: Missing required tools: ${missing_tools[*]}" >&2
  exit 1
fi

if [[ ! -d "${terraform_dir}" ]]; then
  echo "Error: Terraform directory not found: ${terraform_dir}" >&2
  exit 1
fi

if [[ ! -f "${terraform_dir}/terraform.tfstate" ]]; then
  echo "Error: terraform.tfstate not found in ${terraform_dir}" >&2
  exit 1
fi

# ============================================================
# Read Terraform Outputs
# ============================================================

echo "Reading Terraform outputs from ${terraform_dir}..."
if ! tf_output=$(cd "${terraform_dir}" && terraform output -json); then
  echo "Error: Unable to read terraform outputs" >&2
  exit 1
fi

aks_name=$(echo "${tf_output}" | jq -r '.aks_cluster.value.name // empty')
aks_id=$(echo "${tf_output}" | jq -r '.aks_cluster.value.id // empty')
resource_group=$(echo "${tf_output}" | jq -r '.resource_group.value.name // empty')
ml_workspace_name=$(echo "${tf_output}" | jq -r '.azureml_workspace.value.name // empty')
ml_identity_id=$(echo "${tf_output}" | jq -r '.ml_workload_identity.value.id // empty')

if [[ -z "${aks_name}" ]] || [[ -z "${resource_group}" ]]; then
  echo "Error: Could not read AKS cluster info from Terraform outputs" >&2
  exit 1
fi

# Set default names if not provided
if [[ -z "${extension_name}" ]]; then
  extension_name="azureml-${aks_name}"
fi

# Compute name must be 2-16 characters (letters, digits, dashes)
# Use a short prefix instead of duplicating 'aks-'
if [[ -z "${compute_name}" ]]; then
  # Extract the resource suffix (e.g., "osmorobo-tst-001" from "aks-osmorobo-tst-001")
  # and prefix with 'k8s-' to stay under 16 chars
  compute_suffix="${aks_name#aks-}"
  # Truncate to fit within 16 char limit (16 - 4 for "k8s-" = 12 chars max for suffix)
  compute_suffix="${compute_suffix:0:12}"
  compute_name="k8s-${compute_suffix}"
fi

echo "  AKS Cluster:     ${aks_name}"
echo "  Resource Group:  ${resource_group}"
echo "  Extension Name:  ${extension_name}"
echo "  Compute Name:    ${compute_name}"
if [[ -n "${ml_workspace_name}" ]]; then
  echo "  ML Workspace:    ${ml_workspace_name}"
fi
if [[ -n "${ml_identity_id}" ]]; then
  echo "  ML Identity:     ${ml_identity_id}"
fi

# ============================================================
# Connect to AKS Cluster
# ============================================================

echo "Connecting to AKS cluster..."
az aks get-credentials \
  --resource-group "${resource_group}" \
  --name "${aks_name}" \
  --overwrite-existing
kubectl cluster-info &>/dev/null

# ============================================================
# Step 1: Install AzureML Extension
# ============================================================

# Per Microsoft documentation, the extension MUST be installed first via
# az k8s-extension create, then the cluster is attached via az ml compute attach.
# Reference: https://learn.microsoft.com/en-us/azure/machine-learning/how-to-deploy-kubernetes-extension

echo ""
echo "============================"
echo "Step 1: Install AzureML Extension"
echo "============================"
echo "Configuration:"
echo "  Enable Training:             ${enable_training}"
echo "  Enable Inference:            ${enable_inference}"
echo "  Inference Router Type:       ${inference_router_service_type}"
echo "  Inference Router HA:         ${inference_router_ha}"
echo "  Allow Insecure Connections:  ${allow_insecure_connections}"
echo "  Cluster Purpose:             ${cluster_purpose}"

# Build configuration arguments array
config_args=(
  "enableTraining=${enable_training}"
  "enableInference=${enable_inference}"
  "inferenceRouterServiceType=${inference_router_service_type}"
  "inferenceRouterHA=${inference_router_ha}"
  "allowInsecureConnections=${allow_insecure_connections}"
  "clusterPurpose=${cluster_purpose}"
  "installNvidiaDevicePlugin=${install_nvidia_device_plugin}"
  "installDcgmExporter=${install_dcgm_exporter}"
  "installVolcano=${install_volcano}"
  "installPromOp=${install_prom_op}"
  # AKS-specific settings (disable Arc-only features)
  "servicebus.enabled=false"
  "relayserver.enabled=false"
)

# Add GPU spot tolerations if enabled
if [[ "${enable_gpu_spot_tolerations}" == "true" ]]; then
  echo "Adding GPU spot node tolerations..."
  config_args+=(
    "workLoadToleration[0].key=nvidia.com/gpu"
    "workLoadToleration[0].operator=Exists"
    "workLoadToleration[0].effect=NoSchedule"
    "workLoadToleration[1].key=kubernetes.azure.com/scalesetpriority"
    "workLoadToleration[1].operator=Equal"
    "workLoadToleration[1].value=spot"
    "workLoadToleration[1].effect=NoSchedule"
  )
fi

# Build the --config string for az CLI
config_string=""
for arg in "${config_args[@]}"; do
  config_string+="${arg} "
done

# Check if extension already exists
existing_extension=$(az k8s-extension show \
  --name "${extension_name}" \
  --cluster-type managedClusters \
  --cluster-name "${aks_name}" \
  --resource-group "${resource_group}" \
  --query "name" -o tsv 2>/dev/null || true)

if [[ -n "${existing_extension}" ]]; then
  echo ""
  echo "AzureML extension '${extension_name}' already exists. Skipping installation."
else
  echo ""
  echo "Installing AzureML extension on AKS cluster..."
  # shellcheck disable=SC2086
  az k8s-extension create \
    --name "${extension_name}" \
    --extension-type Microsoft.AzureML.Kubernetes \
    --cluster-type managedClusters \
    --cluster-name "${aks_name}" \
    --resource-group "${resource_group}" \
    --scope cluster \
    --release-namespace azureml \
    --release-train stable \
    --config ${config_string}

  echo ""
  echo "Extension installation initiated. Waiting for pods to start..."
  sleep 30
fi

# ============================================================
# Step 2: Create GPU Instance Types
# ============================================================
# Instance types MUST be created BEFORE attaching compute target.
# AzureML syncs instance types during the attach operation, so they
# must exist in the cluster beforehand.

if [[ "${skip_instance_types}" != "true" ]]; then
  echo ""
  echo "============================"
  echo "Step 2: Create GPU Instance Types"
  echo "============================"

  # Wait for InstanceType CRD to be available (extension needs time to install CRDs)
  echo "Waiting for InstanceType CRD to be available..."
  for i in {1..30}; do
    if kubectl get crd instancetypes.amlarc.azureml.com &>/dev/null; then
      echo "InstanceType CRD is available."
      break
    fi
    if [[ $i -eq 30 ]]; then
      echo "Warning: InstanceType CRD not available after 5 minutes. Skipping instance type creation."
      echo "You can create instance types later and re-attach the compute target."
      skip_instance_types="true"
    else
      echo "  Waiting for CRD... (${i}/30)"
      sleep 10
    fi
  done

  if [[ "${skip_instance_types}" != "true" ]]; then
    # Create instance types for GPU spot nodes
    # These allow ML jobs to be scheduled on GPU nodes with spot pricing
    # Note: Only nodeSelector and resources are officially supported fields
    # Tolerations must be configured at the extension level via workLoadToleration
    kubectl apply -f - <<EOF
apiVersion: amlarc.azureml.com/v1alpha1
kind: InstanceTypeList
items:
  # Default instance type for CPU workloads
  - metadata:
      name: defaultinstancetype
    spec:
      resources:
        requests:
          cpu: "1"
          memory: "4Gi"
        limits:
          cpu: "2"
          memory: "8Gi"

  # GPU instance type for spot nodes with NVIDIA GPU
  - metadata:
      name: gpuspot
    spec:
      nodeSelector:
        accelerator: nvidia
        kubernetes.azure.com/scalesetpriority: spot
      resources:
        requests:
          cpu: "4"
          memory: "16Gi"
        limits:
          cpu: "8"
          memory: "32Gi"
          nvidia.com/gpu: 1
EOF

    echo "Instance types created:"
    kubectl get instancetype 2>/dev/null || echo "(InstanceType CRD not yet available)"
  fi
else
  echo ""
  echo "Skipping instance type creation (--skip-instance-types)"
fi

# ============================================================
# Step 3: Create Federated Identity Credentials
# ============================================================
# Federated Identity Credentials (FICs) enable the ML workload identity to
# authenticate as Kubernetes service accounts in the azureml namespace.
# Required for workload identity-based access to storage, ACR, and Key Vault.
#
# When should_integrate_aks_cluster=true in Terraform, these are created by
# the SiL module. When false (script-based deployment), we create them here.

if [[ "${skip_compute_attach}" != "true" ]] && [[ -n "${ml_identity_id}" ]]; then
  echo ""
  echo "============================"
  echo "Step 3: Create Federated Identity Credentials"
  echo "============================"

  # Extract identity name from the full resource ID
  # Format: /subscriptions/.../resourceGroups/.../providers/Microsoft.ManagedIdentity/userAssignedIdentities/<name>
  ml_identity_name="${ml_identity_id##*/}"

  # Get AKS OIDC issuer URL
  oidc_issuer=$(az aks show \
    --resource-group "${resource_group}" \
    --name "${aks_name}" \
    --query "oidcIssuerProfile.issuerUrl" -o tsv)

  if [[ -z "${oidc_issuer}" ]]; then
    echo "Error: Could not retrieve OIDC issuer URL from AKS cluster" >&2
    echo "Ensure OIDC issuer is enabled on the cluster." >&2
    exit 1
  fi

  echo "Identity Name:  ${ml_identity_name}"
  echo "OIDC Issuer:    ${oidc_issuer}"

  # Create FIC for default service account in azureml namespace
  # This is used by the AzureML extension for system operations
  existing_fic_default=$(az identity federated-credential show \
    --identity-name "${ml_identity_name}" \
    --resource-group "${resource_group}" \
    --name "aml-default-fic" \
    --query "name" -o tsv 2>/dev/null || true)

  if [[ -z "${existing_fic_default}" ]]; then
    echo "Creating federated credential for azureml:default service account..."
    az identity federated-credential create \
      --identity-name "${ml_identity_name}" \
      --resource-group "${resource_group}" \
      --name "aml-default-fic" \
      --issuer "${oidc_issuer}" \
      --subject "system:serviceaccount:azureml:default" \
      --audiences "api://AzureADTokenExchange"
  else
    echo "Federated credential 'aml-default-fic' already exists."
  fi

  # Create FIC for training service account in azureml namespace
  # This is used by training jobs to access datastores and ACR
  existing_fic_training=$(az identity federated-credential show \
    --identity-name "${ml_identity_name}" \
    --resource-group "${resource_group}" \
    --name "aml-training-fic" \
    --query "name" -o tsv 2>/dev/null || true)

  if [[ -z "${existing_fic_training}" ]]; then
    echo "Creating federated credential for azureml:training service account..."
    az identity federated-credential create \
      --identity-name "${ml_identity_name}" \
      --resource-group "${resource_group}" \
      --name "aml-training-fic" \
      --issuer "${oidc_issuer}" \
      --subject "system:serviceaccount:azureml:training" \
      --audiences "api://AzureADTokenExchange"
  else
    echo "Federated credential 'aml-training-fic' already exists."
  fi

  echo "Federated identity credentials configured."
else
  if [[ -z "${ml_identity_id}" ]]; then
    echo ""
    echo "Warning: ML identity not found in Terraform outputs."
    echo "Federated identity credentials will not be created."
    echo "Compute attach will use SystemAssigned identity instead."
  fi
fi

# ============================================================
# Step 4: Attach Cluster as Compute Target
# ============================================================
# Attach AFTER instance types are created so AzureML syncs them properly.

if [[ "${skip_compute_attach}" != "true" ]]; then
  if [[ -z "${ml_workspace_name}" ]] || [[ -z "${aks_id}" ]]; then
    echo ""
    echo "Error: ML workspace or AKS ID not found in Terraform outputs."
    echo "Cannot proceed with compute attach."
    exit 1
  fi

  echo ""
  echo "============================"
  echo "Step 4: Attach Compute Target"
  echo "============================"
  echo "Compute Name:  ${compute_name}"
  echo "Namespace:     azureml"

  # Check if compute target already exists
  existing_compute=$(az ml compute show \
    --name "${compute_name}" \
    --resource-group "${resource_group}" \
    --workspace-name "${ml_workspace_name}" \
    --query "name" -o tsv 2>/dev/null || true)

  if [[ -n "${existing_compute}" ]]; then
    echo ""
    echo "Compute target '${compute_name}' already exists."
    echo "To sync new instance types, detach and re-attach the compute:"
    echo "  az ml compute detach --name ${compute_name} --resource-group ${resource_group} --workspace-name ${ml_workspace_name} --yes"
    echo "  Then re-run this script."
  else
    echo ""
    echo "Attaching AKS cluster as compute target..."

    # Use User Assigned Identity from Terraform if available
    if [[ -n "${ml_identity_id}" ]]; then
      echo "Identity: UserAssigned (${ml_identity_id})"
      az ml compute attach \
        --resource-group "${resource_group}" \
        --workspace-name "${ml_workspace_name}" \
        --type Kubernetes \
        --name "${compute_name}" \
        --resource-id "${aks_id}" \
        --identity-type UserAssigned \
        --user-assigned-identities "${ml_identity_id}" \
        --namespace azureml
    else
      echo "Identity: SystemAssigned"
      az ml compute attach \
        --resource-group "${resource_group}" \
        --workspace-name "${ml_workspace_name}" \
        --type Kubernetes \
        --name "${compute_name}" \
        --resource-id "${aks_id}" \
        --identity-type SystemAssigned \
        --namespace azureml
    fi

    echo ""
    echo "Compute target attached successfully."
  fi
else
  echo ""
  echo "Skipping compute attach (--skip-compute-attach)"
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo "============================"
echo "Deployment Verification"
echo "============================"

echo ""
echo "AzureML Extension pods:"
kubectl get pods -n azureml -o wide 2>/dev/null || echo "(azureml namespace not yet created)"

echo ""
echo "Instance Types:"
kubectl get instancetype 2>/dev/null || echo "(InstanceType CRD not yet available)"

echo ""
echo "============================"
echo "AzureML Deployment Summary"
echo "============================"
echo "AKS Cluster:      ${aks_name}"
echo "Resource Group:   ${resource_group}"
echo "Extension Name:   ${extension_name}"
echo "Compute Target:   ${compute_name}"
echo "Cluster Purpose:  ${cluster_purpose}"
echo ""
echo "Check extension status:"
echo "  az k8s-extension show \\"
echo "    --name ${extension_name} \\"
echo "    --cluster-type managedClusters \\"
echo "    --cluster-name ${aks_name} \\"
echo "    --resource-group ${resource_group}"
echo ""
if [[ -n "${ml_workspace_name}" ]]; then
  echo "Check compute target:"
  echo "  az ml compute show --name ${compute_name} \\"
  echo "    --resource-group ${resource_group} \\"
  echo "    --workspace-name ${ml_workspace_name}"
  echo ""
fi
echo "Available instance types for training jobs:"
echo "  - defaultinstancetype: CPU workloads (2 CPU, 8Gi memory)"
echo "  - gpuspot: GPU on spot nodes (4-8 CPU, 16-32Gi memory, 1 GPU)"
echo ""
echo "Example training job with GPU spot instance:"
echo "  az ml job create --file job.yml"
echo "  # In job.yml, specify: resources.instance_type: gpuspot"
echo ""
echo "Next Steps:"
echo "  kubectl get pods -n azureml                              - Check pod status"
echo "  kubectl get events -n azureml --sort-by='.lastTimestamp' - Check events"
echo "  kubectl describe configmap -n azureml arcml-healthcheck  - Check health report"
echo "  kubectl get instancetype                                 - List instance types"
echo ""
echo "Deployment completed successfully!"
