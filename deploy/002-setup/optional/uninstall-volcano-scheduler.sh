#!/usr/bin/env bash
set -euo pipefail

#######################################
# AzureML Charts Uninstall Script
#
# Removes Volcano scheduler from AKS cluster.
# Note: Does NOT delete azureml namespace - ML extension uses it.
#
# Usage:
#   ./uninstall-azureml-charts.sh
#######################################

echo "Uninstalling AzureML Charts..."

# ============================================================
# Volcano Scheduler
# ============================================================

if helm status volcano -n azureml &>/dev/null; then
  echo "Uninstalling Volcano..."
  helm uninstall volcano -n azureml
else
  echo "Volcano not found, skipping..."
fi

echo ""
echo "============================"
echo "AzureML Charts Uninstalled"
echo "============================"
echo ""
echo "Note: The azureml namespace was NOT deleted."
echo "  - AzureML extension uses this namespace"
echo "  - Other ML workloads may depend on it"
echo ""
echo "To delete the azureml namespace (if safe): kubectl delete namespace azureml"
