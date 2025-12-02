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

if [[ -z "${compute_name}" ]]; then
  compute_name="aks-${aks_name}"
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
# Install AzureML Extension
# ============================================================

echo ""
echo "============================"
echo "Installing AzureML Extension"
echo "============================"
echo "Configuration:"
echo "  Enable Training:             ${enable_training}"
echo "  Enable Inference:            ${enable_inference}"
echo "  Inference Router Type:       ${inference_router_service_type}"
echo "  Inference Router HA:         ${inference_router_ha}"
echo "  Allow Insecure Connections:  ${allow_insecure_connections}"
echo "  Cluster Purpose:             ${cluster_purpose}"
echo ""
echo "Component Installation:"
echo "  Install NVIDIA Device Plugin: ${install_nvidia_device_plugin}"
echo "  Install DCGM Exporter:        ${install_dcgm_exporter}"
echo "  Install Volcano:              ${install_volcano}"
echo "  Install Prometheus Operator:  ${install_prom_op}"
echo ""
echo "GPU Spot Tolerations:          ${enable_gpu_spot_tolerations}"
echo "============================"

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

echo ""
echo "Executing az k8s-extension create..."

# Install the extension
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

# ============================================================
# Attach Cluster as Compute Target
# ============================================================

if [[ "${skip_compute_attach}" != "true" ]]; then
  if [[ -z "${ml_workspace_name}" ]] || [[ -z "${aks_id}" ]]; then
    echo ""
    echo "Warning: ML workspace or AKS ID not found in Terraform outputs."
    echo "Skipping compute attach. You can attach manually with:"
    echo "  az ml compute attach --resource-group <rg> --workspace-name <ws> \\"
    echo "    --type Kubernetes --name ${compute_name} --resource-id <aks-id> \\"
    echo "    --identity-type UserAssigned --user-assigned-identities <identity-id> \\"
    echo "    --namespace azureml"
  else
    echo ""
    echo "============================"
    echo "Attaching Cluster as Compute Target"
    echo "============================"
    echo "Compute Name:  ${compute_name}"
    echo "Namespace:     azureml"

    # Use User Assigned Identity from Terraform if available, otherwise fall back to SystemAssigned
    # The User Assigned Identity has pre-configured role assignments for ACR, Storage, and Key Vault
    if [[ -n "${ml_identity_id}" ]]; then
      echo "Identity:      UserAssigned (${ml_identity_id})"
      az ml compute attach \
        --resource-group "${resource_group}" \
        --workspace-name "${ml_workspace_name}" \
        --type Kubernetes \
        --name "${compute_name}" \
        --resource-id "${aks_id}" \
        --identity-type UserAssigned \
        --user-assigned-identities "${ml_identity_id}" \
        --namespace azureml \
        --no-wait || echo "Warning: Compute attach failed. It may already exist."
    else
      echo "Identity:      SystemAssigned (no user-assigned identity found in Terraform outputs)"
      az ml compute attach \
        --resource-group "${resource_group}" \
        --workspace-name "${ml_workspace_name}" \
        --type Kubernetes \
        --name "${compute_name}" \
        --resource-id "${aks_id}" \
        --identity-type SystemAssigned \
        --namespace azureml \
        --no-wait || echo "Warning: Compute attach failed. It may already exist."
    fi
  fi
else
  echo ""
  echo "Skipping compute attach (--skip-compute-attach)"
fi

# ============================================================
# Create GPU Instance Types
# ============================================================

if [[ "${skip_instance_types}" != "true" ]]; then
  echo ""
  echo "============================"
  echo "Creating GPU Instance Types"
  echo "============================"

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
else
  echo ""
  echo "Skipping instance type creation (--skip-instance-types)"
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
