#!/usr/bin/env bash
# Check if a VM size (SKU) is supported for your subscription in a given Azure region.
# Usage: check-vm-sku.sh <location> [size]
#   location  e.g. eastus, westus3
#   size      optional; if omitted, lists all GPU-related SKUs in the region
set -e

LOCATION="${1:?Usage: $0 <location> [size]   e.g. $0 eastus Standard_ND96isr_H100_v5}"
SIZE="${2:-}"

if command -v az &>/dev/null; then
  : # ok
else
  echo "Azure CLI (az) is required. Install: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
  exit 1
fi

az account show &>/dev/null || { echo "Run 'az login' first."; exit 1; }

if [[ -n "$SIZE" ]]; then
  echo "Checking SKU '$SIZE' in region '$LOCATION' for current subscription..."
  echo ""
  if az vm list-skus --location "$LOCATION" --resource-type virtualMachines --size "$SIZE" -o table 2>/dev/null | grep -q .; then
    echo "Supported: '$SIZE' is available in $LOCATION."
    az vm list-skus --location "$LOCATION" --resource-type virtualMachines --size "$SIZE" -o table
  else
    echo "Not supported: '$SIZE' is not available in $LOCATION for this subscription."
    echo "Try another region (e.g. eastus, westus2) or run without size to list GPU SKUs: $0 $LOCATION"
    exit 2
  fi
else
  echo "Listing GPU-related VM SKUs in '$LOCATION' (subscription: $(az account show -o tsv --query name))..."
  echo ""
  az vm list-skus --location "$LOCATION" --resource-type virtualMachines -o table 2>/dev/null | grep -iE 'standard_n[cvd]|gpu' || true
  echo ""
  echo "To check a specific size: $0 $LOCATION Standard_<Name>"
fi
