#!/usr/bin/env bash
set -euo pipefail

#######################################
# Robotics Charts Deployment Script
#
# Installs NVIDIA GPU Operator and KAI Scheduler on AKS cluster.
# Reads Terraform outputs for cluster connection.
#
# Usage:
#   ./deploy-robotics-charts.sh [OPTIONS]
#
# Options:
#   --terraform-dir PATH    Path to terraform directory (default: ../../001-iac)
#   --skip-gpu-operator     Skip NVIDIA GPU Operator installation
#   --skip-kai-scheduler    Skip KAI Scheduler installation
#   --help                  Show this help message
#
# Examples:
#   # Deploy all robotics charts
#   ./deploy-robotics-charts.sh
#
#   # Deploy with custom terraform directory
#   ./deploy-robotics-charts.sh --terraform-dir /path/to/terraform
#
#   # Skip GPU Operator (already installed)
#   ./deploy-robotics-charts.sh --skip-gpu-operator
#######################################

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
terraform_dir="${script_dir}/../../001-iac"
values_dir="${script_dir}/values"
manifests_dir="${script_dir}/manifests"

skip_gpu_operator=false
skip_kai_scheduler=false

help="Usage: deploy-robotics-charts.sh [OPTIONS]

Installs NVIDIA GPU Operator and KAI Scheduler on AKS cluster.

OPTIONS:
  --terraform-dir PATH    Path to terraform directory (default: ../../001-iac)
  --skip-gpu-operator     Skip NVIDIA GPU Operator installation
  --skip-kai-scheduler    Skip KAI Scheduler installation
  --help                  Show this help message

EXAMPLES:
  # Deploy all robotics charts
  ./deploy-robotics-charts.sh

  # Deploy with custom terraform directory
  ./deploy-robotics-charts.sh --terraform-dir /path/to/terraform
"

while [[ $# -gt 0 ]]; do
  case $1 in
    --terraform-dir)
      terraform_dir="$2"
      shift 2
      ;;
    --skip-gpu-operator)
      skip_gpu_operator=true
      shift
      ;;
    --skip-kai-scheduler)
      skip_kai_scheduler=true
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

echo "Creating osmo namespace..."
kubectl create namespace osmo --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount osmo-workload -n osmo --dry-run=client -o yaml | kubectl apply -f -

echo "Adding Helm repositories..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null || true
helm repo update >/dev/null

# ============================================================
# Install GPU Operator
# ============================================================

if [[ "${skip_gpu_operator}" != "true" ]]; then
  echo ""
  echo "Installing NVIDIA GPU Operator..."
  helm upgrade --install gpu-operator nvidia/gpu-operator \
    --namespace gpu-operator \
    --create-namespace \
    --version 24.9.1 \
    --disable-openapi-validation \
    -f "${values_dir}/nvidia-gpu-operator.yaml" \
    --wait \
    --timeout 10m

  # Configure metrics scraping based on available monitoring infrastructure
  if kubectl get crd podmonitors.monitoring.coreos.com &>/dev/null; then
    echo "Applying GPU PodMonitor (Prometheus Operator detected)..."
    kubectl apply -f "${manifests_dir}/gpu-podmonitor.yaml"
  elif kubectl get daemonset ama-metrics -n kube-system &>/dev/null; then
    echo "Configuring Azure Monitor Prometheus to scrape DCGM metrics..."
    kubectl apply -f "${manifests_dir}/ama-metrics-dcgm-scrape.yaml"
    echo "  Metrics will be available in Azure Monitor Workspace after agent restart"
  else
    echo "No Prometheus scraping configured (neither Prometheus Operator nor Azure Monitor agent found)"
    echo "  GPU metrics will still be available via direct pod access on port 9400"
  fi
else
  echo "Skipping GPU Operator installation (--skip-gpu-operator)"
fi

# ============================================================
# Install KAI Scheduler
# ============================================================

if [[ "${skip_kai_scheduler}" != "true" ]]; then
  echo ""
  echo "Installing KAI Scheduler..."

  # Fetch from OCI registry
  helm fetch oci://ghcr.io/nvidia/kai-scheduler/kai-scheduler --version v0.5.5

  helm upgrade --install kai-scheduler kai-scheduler-v0.5.5.tgz \
    --namespace kai-scheduler \
    --create-namespace \
    --values "${values_dir}/kai-scheduler.yaml" \
    --wait \
    --timeout 5m

  # Cleanup fetched chart
  rm -f kai-scheduler-v0.5.5.tgz
else
  echo "Skipping KAI Scheduler installation (--skip-kai-scheduler)"
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo "============================"
echo "Deployment Verification"
echo "============================"

kubectl get pods -n gpu-operator -o wide 2>/dev/null || echo "(gpu-operator namespace not found)"
kubectl get pods -n kai-scheduler -o wide 2>/dev/null || echo "(kai-scheduler namespace not found)"

echo ""
echo "============================"
echo "Robotics Charts Deployment Summary"
echo "============================"
echo "AKS Cluster:       ${aks_name}"
echo "Resource Group:    ${resource_group}"
echo ""
echo "Installed charts:"
helm list -A | grep -E "gpu-operator|kai-scheduler" || true
echo ""
echo "Namespaces created:"
echo "  - osmo (workload namespace)"
echo "  - gpu-operator (GPU Operator)"
echo "  - kai-scheduler (KAI Scheduler)"
echo ""
echo "Next Steps:"
echo "  ./validate-gpu-metrics.sh    - Verify GPU metrics are available"
echo "  kubectl get pods -n osmo     - Check workload namespace"
echo ""
echo "Deployment completed successfully!"
