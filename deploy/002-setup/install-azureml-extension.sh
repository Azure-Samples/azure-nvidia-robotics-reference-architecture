#!/bin/bash
# =============================================================================
# install-azureml-extension.sh
# =============================================================================
# Installs Azure Machine Learning extension on AKS cluster via Azure CLI.
# Alternative to Terraform-based deployment for manual or troubleshooting scenarios.
#
# Usage:
#   # Set required environment variables
#   export EXTENSION_NAME="azureml-sil-dev-001"
#   export CLUSTER_NAME="aks-sil-dev-001"
#   export RESOURCE_GROUP="rg-sil-dev-001"
#
#   # Run the script
#   ./install-azureml-extension.sh
#
# Examples:
#   # Basic installation with defaults (dev/test mode)
#   EXTENSION_NAME="azureml-sil-dev-001" \
#   CLUSTER_NAME="aks-sil-dev-001" \
#   RESOURCE_GROUP="rg-sil-dev-001" \
#   ./install-azureml-extension.sh
#
#   # Production installation with HA enabled
#   EXTENSION_NAME="azureml-sil-prod-001" \
#   CLUSTER_NAME="aks-sil-prod-001" \
#   RESOURCE_GROUP="rg-sil-prod-001" \
#   INFERENCE_ROUTER_HA="true" \
#   ALLOW_INSECURE_CONNECTIONS="false" \
#   CLUSTER_PURPOSE="FastProd" \
#   ./install-azureml-extension.sh
#
#   # Bring your own components (existing Volcano, Prometheus, GPU Operator)
#   EXTENSION_NAME="azureml-sil-prod-001" \
#   CLUSTER_NAME="aks-sil-prod-001" \
#   RESOURCE_GROUP="rg-sil-prod-001" \
#   INSTALL_VOLCANO="false" \
#   INSTALL_PROM_OP="false" \
#   INFERENCE_ROUTER_HA="true" \
#   CLUSTER_PURPOSE="FastProd" \
#   ./install-azureml-extension.sh
# =============================================================================

set -euo pipefail

# =============================================================================
# Required Parameters
# =============================================================================
EXTENSION_NAME="${EXTENSION_NAME:?EXTENSION_NAME is required}"
CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME is required}"
RESOURCE_GROUP="${RESOURCE_GROUP:?RESOURCE_GROUP is required}"

# =============================================================================
# Optional Parameters with Defaults (matching Terraform defaults)
# =============================================================================

# Training and inference settings
ENABLE_TRAINING="${ENABLE_TRAINING:-true}"
ENABLE_INFERENCE="${ENABLE_INFERENCE:-true}"
INFERENCE_ROUTER_SERVICE_TYPE="${INFERENCE_ROUTER_SERVICE_TYPE:-LoadBalancer}"
INFERENCE_ROUTER_HA="${INFERENCE_ROUTER_HA:-false}"
ALLOW_INSECURE_CONNECTIONS="${ALLOW_INSECURE_CONNECTIONS:-true}"
CLUSTER_PURPOSE="${CLUSTER_PURPOSE:-DevTest}"

# Component installation toggles
# Set to true: Extension installs and manages the component
# Set to false: Use existing component already installed on cluster
INSTALL_NVIDIA_DEVICE_PLUGIN="${INSTALL_NVIDIA_DEVICE_PLUGIN:-false}"
INSTALL_DCGM_EXPORTER="${INSTALL_DCGM_EXPORTER:-false}"
INSTALL_VOLCANO="${INSTALL_VOLCANO:-true}"
INSTALL_PROM_OP="${INSTALL_PROM_OP:-true}"

# GPU spot node tolerations (enabled by default for scheduling on GPU/spot nodes)
ENABLE_GPU_SPOT_TOLERATIONS="${ENABLE_GPU_SPOT_TOLERATIONS:-true}"

# =============================================================================
# Script Execution
# =============================================================================

echo "============================================================"
echo "Installing AzureML Extension"
echo "============================================================"
echo "Extension Name: ${EXTENSION_NAME}"
echo "Cluster:        ${CLUSTER_NAME}"
echo "Resource Group: ${RESOURCE_GROUP}"
echo ""
echo "Configuration:"
echo "  Enable Training:             ${ENABLE_TRAINING}"
echo "  Enable Inference:            ${ENABLE_INFERENCE}"
echo "  Inference Router Type:       ${INFERENCE_ROUTER_SERVICE_TYPE}"
echo "  Inference Router HA:         ${INFERENCE_ROUTER_HA}"
echo "  Allow Insecure Connections:  ${ALLOW_INSECURE_CONNECTIONS}"
echo "  Cluster Purpose:             ${CLUSTER_PURPOSE}"
echo ""
echo "Component Installation:"
echo "  Install NVIDIA Device Plugin: ${INSTALL_NVIDIA_DEVICE_PLUGIN}"
echo "  Install DCGM Exporter:        ${INSTALL_DCGM_EXPORTER}"
echo "  Install Volcano:              ${INSTALL_VOLCANO}"
echo "  Install Prometheus Operator:  ${INSTALL_PROM_OP}"
echo ""
echo "GPU Spot Tolerations:          ${ENABLE_GPU_SPOT_TOLERATIONS}"
echo "============================================================"

# Build configuration arguments array
CONFIG_ARGS=(
  "enableTraining=${ENABLE_TRAINING}"
  "enableInference=${ENABLE_INFERENCE}"
  "inferenceRouterServiceType=${INFERENCE_ROUTER_SERVICE_TYPE}"
  "inferenceRouterHA=${INFERENCE_ROUTER_HA}"
  "allowInsecureConnections=${ALLOW_INSECURE_CONNECTIONS}"
  "clusterPurpose=${CLUSTER_PURPOSE}"
  "installNvidiaDevicePlugin=${INSTALL_NVIDIA_DEVICE_PLUGIN}"
  "installDcgmExporter=${INSTALL_DCGM_EXPORTER}"
  "installVolcano=${INSTALL_VOLCANO}"
  "installPromOp=${INSTALL_PROM_OP}"
  # AKS-specific settings (disable Arc-only features)
  "servicebus.enabled=false"
  "relayserver.enabled=false"
)

# Add GPU spot tolerations if enabled
if [[ "${ENABLE_GPU_SPOT_TOLERATIONS}" == "true" ]]; then
  echo "Adding GPU spot node tolerations..."
  CONFIG_ARGS+=(
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
CONFIG_STRING=""
for arg in "${CONFIG_ARGS[@]}"; do
  CONFIG_STRING+="${arg} "
done

echo ""
echo "Executing az k8s-extension create..."
echo ""

# Install the extension
# shellcheck disable=SC2086
az k8s-extension create \
  --name "${EXTENSION_NAME}" \
  --extension-type Microsoft.AzureML.Kubernetes \
  --cluster-type managedClusters \
  --cluster-name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --scope cluster \
  --release-namespace azureml \
  --release-train stable \
  --config ${CONFIG_STRING}

echo ""
echo "============================================================"
echo "Extension installation initiated successfully!"
echo "============================================================"
echo ""
echo "Check extension status:"
echo "  az k8s-extension show \\"
echo "    --name ${EXTENSION_NAME} \\"
echo "    --cluster-type managedClusters \\"
echo "    --cluster-name ${CLUSTER_NAME} \\"
echo "    --resource-group ${RESOURCE_GROUP}"
echo ""
echo "Check pod status:"
echo "  kubectl get pods -n azureml"
echo ""
echo "Check events:"
echo "  kubectl get events -n azureml --sort-by='.lastTimestamp'"
echo ""
echo "Check HealthCheck report:"
echo "  kubectl describe configmap -n azureml arcml-healthcheck"
echo ""
