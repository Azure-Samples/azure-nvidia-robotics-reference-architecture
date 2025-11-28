#!/usr/bin/env bash
set -euo pipefail

#######################################
# AzureML Charts Deployment Script
#
# Installs Volcano scheduler for advanced ML job scheduling.
# Optional component - only needed for complex batch scheduling.
#
# Usage:
#   ./deploy-azureml-charts.sh [OPTIONS]
#
# Options:
#   --terraform-dir PATH    Path to terraform directory (default: ../../001-iac)
#   --help                  Show this help message
#
# Examples:
#   # Deploy Volcano scheduler
#   ./deploy-azureml-charts.sh
#
#   # Deploy with custom terraform directory
#   ./deploy-azureml-charts.sh --terraform-dir /path/to/terraform
#######################################

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
terraform_dir="${script_dir}/../../001-iac"
values_dir="${script_dir}/values"

help="Usage: deploy-azureml-charts.sh [OPTIONS]

Installs Volcano scheduler for advanced ML job scheduling.

OPTIONS:
  --terraform-dir PATH    Path to terraform directory (default: ../../001-iac)
  --help                  Show this help message

EXAMPLES:
  # Deploy Volcano scheduler
  ./deploy-azureml-charts.sh

  # Deploy with custom terraform directory
  ./deploy-azureml-charts.sh --terraform-dir /path/to/terraform
"

while [[ $# -gt 0 ]]; do
  case $1 in
    --terraform-dir)
      terraform_dir="$2"
      shift 2
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

echo "Checking prerequisites..."
required_tools=(terraform az kubectl helm jq)
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

echo "Reading Terraform outputs from ${terraform_dir}..."
if ! tf_output=$(cd "${terraform_dir}" && terraform output -json); then
  echo "Error: Unable to read terraform outputs" >&2
  exit 1
fi

aks_name=$(echo "${tf_output}" | jq -r '.aks_cluster.value.name // empty')
resource_group=$(echo "${tf_output}" | jq -r '.resource_group.value.name // empty')

if [[ -z "${aks_name}" ]] || [[ -z "${resource_group}" ]]; then
  echo "Error: Could not read AKS cluster info from Terraform outputs" >&2
  exit 1
fi

echo "  AKS Cluster: ${aks_name}"
echo "  Resource Group: ${resource_group}"

echo "Connecting to AKS cluster..."
az aks get-credentials \
  --resource-group "${resource_group}" \
  --name "${aks_name}" \
  --overwrite-existing
kubectl cluster-info &>/dev/null

echo "Creating azureml namespace..."
kubectl create namespace azureml --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount azureml-workload -n azureml --dry-run=client -o yaml | kubectl apply -f -

echo "Adding Volcano Helm repository..."
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts 2>/dev/null || true
helm repo update >/dev/null

# ============================================================
# Install Volcano Scheduler
# ============================================================

echo ""
echo "Installing Volcano Scheduler..."
helm upgrade --install volcano volcano-sh/volcano \
  --namespace azureml \
  --version 1.12.2 \
  -f "${values_dir}/volcano-sh-values.yaml" \
  --wait \
  --timeout 5m

# ============================================================
# Summary
# ============================================================

echo ""
echo "============================"
echo "Deployment Verification"
echo "============================"

kubectl get pods -n azureml -o wide

echo ""
echo "============================"
echo "AzureML Charts Deployment Summary"
echo "============================"
echo "AKS Cluster:       ${aks_name}"
echo "Resource Group:    ${resource_group}"
echo ""
echo "Installed charts:"
helm list -n azureml || true
echo ""
echo "Namespace created:"
echo "  - azureml (ML workloads and Volcano)"
echo ""
echo "Next Steps:"
echo "  kubectl get pods -n azureml      - Check Volcano pods"
echo "  kubectl get queues -n azureml    - List Volcano queues (if created)"
echo ""
echo "Deployment completed successfully!"
