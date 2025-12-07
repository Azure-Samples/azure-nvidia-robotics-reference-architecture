#!/usr/bin/env bash
set -euo pipefail

#######################################
# AzureML Extension Uninstall Script
#
# Removes Azure Machine Learning extension from AKS cluster,
# detaches the compute target from the workspace, and cleans up
# federated identity credentials.
#
# Usage:
#   ./uninstall-azureml-extension.sh [OPTIONS]
#
# Options:
#   --terraform-dir PATH      Path to terraform directory (default: ../../001-iac)
#   --extension-name NAME     Extension name (default: azureml-<cluster_name>)
#   --compute-name NAME       Compute target name (default: k8s-<cluster_suffix>)
#   --skip-compute-detach     Skip detaching compute target
#   --skip-fic-delete         Skip deleting federated identity credentials
#   --skip-k8s-cleanup        Skip cleaning up K8s resources
#   --force                   Force deletion of extension
#   --help                    Show this help message
#
# Examples:
#   # Uninstall with defaults
#   ./uninstall-azureml-extension.sh
#
#   # Uninstall with custom terraform directory
#   ./uninstall-azureml-extension.sh --terraform-dir /path/to/terraform
#
#   # Force deletion when extension is stuck
#   ./uninstall-azureml-extension.sh --force
#######################################

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
terraform_dir="${script_dir}/../../001-iac"

extension_name=""
compute_name=""
skip_compute_detach="false"
skip_fic_delete="false"
skip_k8s_cleanup="false"
force_delete="false"

help="Usage: uninstall-azureml-extension.sh [OPTIONS]

Removes Azure Machine Learning extension from AKS cluster,
detaches the compute target, and cleans up federated identity credentials.

OPTIONS:
  --terraform-dir PATH      Path to terraform directory (default: ../../001-iac)
  --extension-name NAME     Extension name (default: azureml-<cluster_name>)
  --compute-name NAME       Compute target name (default: k8s-<cluster_suffix>)
  --skip-compute-detach     Skip detaching compute target
  --skip-fic-delete         Skip deleting federated identity credentials
  --skip-k8s-cleanup        Skip cleaning up K8s resources
  --force                   Force deletion of extension
  --help                    Show this help message

EXAMPLES:
  # Uninstall with defaults
  ./uninstall-azureml-extension.sh

  # Force deletion when extension is stuck
  ./uninstall-azureml-extension.sh --force
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
    --skip-compute-detach)
      skip_compute_detach="true"
      shift
      ;;
    --skip-fic-delete)
      skip_fic_delete="true"
      shift
      ;;
    --skip-k8s-cleanup)
      skip_k8s_cleanup="true"
      shift
      ;;
    --force)
      force_delete="true"
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
resource_group=$(echo "${tf_output}" | jq -r '.resource_group.value.name // empty')
ml_workspace_name=$(echo "${tf_output}" | jq -r '.azureml_workspace.value.name // empty')
ml_identity_id=$(echo "${tf_output}" | jq -r '.ml_workload_identity.value.id // empty')

if [[ -z "${aks_name}" ]] || [[ -z "${resource_group}" ]]; then
  echo "Error: Could not read AKS cluster info from Terraform outputs" >&2
  exit 1
fi

# Set default names if not provided (must match install script logic)
if [[ -z "${extension_name}" ]]; then
  extension_name="azureml-${aks_name}"
fi

if [[ -z "${compute_name}" ]]; then
  compute_suffix="${aks_name#aks-}"
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
# Step 1: Detach Compute Target
# ============================================================

if [[ "${skip_compute_detach}" != "true" ]]; then
  echo ""
  echo "============================"
  echo "Step 1: Detach Compute Target"
  echo "============================"

  if [[ -z "${ml_workspace_name}" ]]; then
    echo "ML workspace not found in Terraform outputs, skipping compute detach..."
  else
    existing_compute=$(az ml compute show \
        --name "${compute_name}" \
        --resource-group "${resource_group}" \
        --workspace-name "${ml_workspace_name}" \
        --query "name" -o tsv 2>/dev/null || true)

    if [[ -n "${existing_compute}" ]]; then
      echo "Detaching compute target '${compute_name}'..."
      az ml compute detach \
        --name "${compute_name}" \
        --resource-group "${resource_group}" \
        --workspace-name "${ml_workspace_name}" \
        --yes
      echo "Compute target detached."
    else
      echo "Compute target '${compute_name}' not found, skipping..."
    fi
  fi
else
  echo ""
  echo "Skipping compute detach (--skip-compute-detach)"
fi

# ============================================================
# Step 2: Delete Federated Identity Credentials
# ============================================================

if [[ "${skip_fic_delete}" != "true" ]]; then
  echo ""
  echo "============================"
  echo "Step 2: Delete Federated Identity Credentials"
  echo "============================"

  if [[ -z "${ml_identity_id}" ]]; then
    echo "ML identity not found in Terraform outputs, skipping FIC deletion..."
  else
    ml_identity_name="${ml_identity_id##*/}"
    echo "Identity Name: ${ml_identity_name}"

    for fic_name in "aml-default-fic" "aml-training-fic"; do
      existing_fic=$(az identity federated-credential show \
          --identity-name "${ml_identity_name}" \
          --resource-group "${resource_group}" \
          --name "${fic_name}" \
          --query "name" -o tsv 2>/dev/null || true)

      if [[ -n "${existing_fic}" ]]; then
        echo "Deleting federated credential '${fic_name}'..."
        az identity federated-credential delete \
          --identity-name "${ml_identity_name}" \
          --resource-group "${resource_group}" \
          --name "${fic_name}" \
          --yes
      else
        echo "Federated credential '${fic_name}' not found, skipping..."
      fi
    done
    echo "Federated identity credentials cleanup complete."
  fi
else
  echo ""
  echo "Skipping FIC deletion (--skip-fic-delete)"
fi

# ============================================================
# Step 3: Delete AzureML Extension
# ============================================================

echo ""
echo "============================"
echo "Step 3: Delete AzureML Extension"
echo "============================"

existing_extension=$(az k8s-extension show \
    --name "${extension_name}" \
    --cluster-type managedClusters \
    --cluster-name "${aks_name}" \
    --resource-group "${resource_group}" \
    --query "name" -o tsv 2>/dev/null || true)

if [[ -n "${existing_extension}" ]]; then
  echo "Deleting AzureML extension '${extension_name}'..."

  delete_args=(
    --name "${extension_name}"
    --cluster-type managedClusters
    --cluster-name "${aks_name}"
    --resource-group "${resource_group}"
    --yes
  )

  if [[ "${force_delete}" == "true" ]]; then
    echo "Using --force flag for deletion..."
    delete_args+=(--force)
  fi

  az k8s-extension delete "${delete_args[@]}"
  echo "Extension deletion initiated."
else
  echo "Extension '${extension_name}' not found, skipping..."
fi

# ============================================================
# Step 4: Cleanup Kubernetes Resources
# ============================================================

if [[ "${skip_k8s_cleanup}" != "true" ]]; then
  echo ""
  echo "============================"
  echo "Step 4: Cleanup Kubernetes Resources"
  echo "============================"

  echo "Waiting for extension deletion to propagate..."
  sleep 30

  # Delete InstanceType resources and CRD if they persist
  if kubectl get crd instancetypes.amlarc.azureml.com &>/dev/null; then
    echo "Cleaning up InstanceType resources..."
    kubectl delete instancetype --all --ignore-not-found 2>/dev/null || true
    echo "Cleaning up InstanceType CRD..."
    kubectl delete crd instancetypes.amlarc.azureml.com --ignore-not-found
  else
    echo "InstanceType CRD not found, skipping..."
  fi

  # Delete azureml namespace if it persists
  if kubectl get namespace azureml &>/dev/null; then
    echo "Cleaning up azureml namespace..."
    kubectl delete namespace azureml --ignore-not-found --timeout=60s || true
  else
    echo "azureml namespace not found, skipping..."
  fi

  echo "Kubernetes resource cleanup complete."
else
  echo ""
  echo "Skipping K8s cleanup (--skip-k8s-cleanup)"
fi

# ============================================================
# Verification
# ============================================================

echo ""
echo "============================"
echo "Verification"
echo "============================"

echo ""
echo "Checking extension status..."
remaining_extension=$(az k8s-extension show \
    --name "${extension_name}" \
    --cluster-type managedClusters \
    --cluster-name "${aks_name}" \
    --resource-group "${resource_group}" \
    --query "name" -o tsv 2>/dev/null || true)

if [[ -n "${remaining_extension}" ]]; then
  echo "  WARNING: Extension '${extension_name}' still exists (may be deleting)"
else
  echo "  OK: Extension removed"
fi

echo ""
echo "Checking azureml namespace..."
if kubectl get namespace azureml &>/dev/null; then
  echo "  WARNING: azureml namespace still exists (may be terminating)"
else
  echo "  OK: azureml namespace removed"
fi

echo ""
echo "Checking InstanceType CRD..."
if kubectl get crd instancetypes.amlarc.azureml.com &>/dev/null; then
  echo "  WARNING: InstanceType CRD still exists"
else
  echo "  OK: InstanceType CRD removed"
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo "============================"
echo "AzureML Extension Uninstall Summary"
echo "============================"
echo "AKS Cluster:      ${aks_name}"
echo "Resource Group:   ${resource_group}"
echo "Extension Name:   ${extension_name}"
echo "Compute Target:   ${compute_name}"
echo ""
echo "To reinstall the AzureML extension, run:"
echo "  ../02-install-azureml-extension.sh"
echo ""
echo "Uninstall completed."
