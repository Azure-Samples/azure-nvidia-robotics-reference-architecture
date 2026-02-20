#!/usr/bin/env bash
# Apply DATASET config with a default_credential (storage account key) so workflow
# uploads to Azure dataset buckets succeed. Use when you see "Credential not set for
# azure://<storage_account>" in osmo-ctrl logs. Requires storage account to have
# shared access keys enabled. Run with port-forward and osmo login.
#
# Usage: ./configure-dataset-credential.sh [-t ../001-iac]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.conf
source "$SCRIPT_DIR/defaults.conf"

tf_dir="${1:-$SCRIPT_DIR/$DEFAULT_TF_DIR}"
require_tools terraform jq az envsubst osmo

az account show &>/dev/null || fatal "Azure CLI not logged in; run 'az login'"
[[ -d "$tf_dir" ]] || fatal "Terraform directory not found: $tf_dir"
[[ -f "$tf_dir/terraform.tfstate" ]] || fatal "terraform.tfstate not found in $tf_dir"

tf_output=$(read_terraform_outputs "$tf_dir")
storage_name=$(tf_get "$tf_output" "storage_account.value.name" "")
rg=$(tf_get "$tf_output" "resource_group.value.name" "")
location=$(tf_get "$tf_output" "resource_group.value.location" "")
[[ -n "$storage_name" ]] || fatal "Storage account name not found in Terraform output"
[[ -n "$rg" ]] || fatal "Resource group not found in Terraform output"

info "Fetching storage account key for $storage_name..."
account_key=$(az storage account keys list -g "$rg" -n "$storage_name" --query '[0].value' -o tsv 2>/dev/null || true)
[[ -n "$account_key" ]] || fatal "Could not get storage account key. Ensure shared_access_key_enabled is true for the storage account."

mkdir -p "$CONFIG_DIR/out"
export DATASET_BUCKET_NAME="${DATASET_BUCKET_NAME:-training}"
export DATASET_CONTAINER_NAME="${DATASET_CONTAINER_NAME:-datasets}"
export STORAGE_ACCOUNT_NAME="$storage_name"
export AZURE_REGION="${location:-eastus}"
# OSMO CLI expects access_key = full Azure connection string (not raw key)
export STORAGE_ACCESS_KEY_ID="$storage_name"
export STORAGE_ACCESS_KEY="DefaultEndpointsProtocol=https;AccountName=${storage_name};AccountKey=${account_key};EndpointSuffix=core.windows.net"

dataset_template="$CONFIG_DIR/dataset-config-access-keys.template.json"
[[ -f "$dataset_template" ]] || fatal "Template not found: $dataset_template"
envsubst < "$dataset_template" > "$CONFIG_DIR/out/dataset-config.json"
# Verify access_key_id is the storage account name (required for Azure Blob)
actual_id=$(jq -r --arg b "$DATASET_BUCKET_NAME" '.buckets[$b].default_credential.access_key_id' "$CONFIG_DIR/out/dataset-config.json")
if [[ "$actual_id" != "$storage_name" ]]; then
  fatal "Generated config has access_key_id=\"$actual_id\"; expected storage account name \"$storage_name\". Check template and env."
fi
info "Applying DATASET config (bucket $DATASET_BUCKET_NAME, access_key=connection string)..."
osmo config update DATASET --file "$CONFIG_DIR/out/dataset-config.json" \
  --description "Dataset bucket with default_credential for uploads"
info "Done. Submit a **new** workflow (new submission); dataset uploads should succeed."
