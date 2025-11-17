#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
terraform_dir="${script_dir}/../../001-iac"
container_name="osmo"
auth_mode="login"
config_preview=false

help="Usage: configure-osmo-storage.sh [OPTIONS]

Creates the blob container backing OSMO workflow data.

OPTIONS:
  --terraform-dir PATH      Path to terraform deployment directory (default: ../../001-iac)
  --container-name NAME     Blob container name to ensure (default: osmo)
  --auth-mode MODE          Authentication mode for az storage commands: login|key (default: login)
  --config-preview          Print resolved configuration and exit
  --help                    Show this help message
"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --terraform-dir)
    terraform_dir="$2"
    shift 2
    ;;
  --container-name)
    container_name="$2"
    shift 2
    ;;
  --auth-mode)
    auth_mode="$2"
    shift 2
    ;;
  --config-preview)
    config_preview=true
    shift
    ;;
  --help)
    echo "$help"
    exit 0
    ;;
  *)
    echo "$help"
    echo
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

case "$auth_mode" in
login|key) ;;
*)
  echo "Error: --auth-mode must be either 'login' or 'key'" >&2
  exit 1
  ;;
esac

if [[ -z "$container_name" ]]; then
  echo "Error: --container-name cannot be empty" >&2
  exit 1
fi

required_tools=(terraform az jq)
missing_tools=()
for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    missing_tools+=("$tool")
  fi
done

if [[ ${#missing_tools[@]} -gt 0 ]]; then
  echo "Error: Missing required tools: ${missing_tools[*]}" >&2
  exit 1
fi

if [[ ! -d "$terraform_dir" ]]; then
  echo "Error: Terraform directory not found: $terraform_dir" >&2
  exit 1
fi

if [[ ! -f "${terraform_dir}/terraform.tfstate" ]]; then
  echo "Error: terraform.tfstate not found in $terraform_dir" >&2
  exit 1
fi

echo "Extracting terraform outputs from $terraform_dir..."
if ! tf_output=$(cd "$terraform_dir" && terraform output -json); then
  echo "Error: Unable to read terraform outputs" >&2
  exit 1
fi

storage_account_name=$(echo "$tf_output" | jq -r '.storage_account.value.name // empty')
storage_account_id=$(echo "$tf_output" | jq -r '.storage_account.value.id // empty')
resource_group_name=$(echo "$tf_output" | jq -r '.resource_group.value.name // empty')
primary_blob_endpoint=$(echo "$tf_output" | jq -r '.storage_account.value.primary_blob_endpoint // empty')

if [[ -z "$storage_account_name" || -z "$storage_account_id" ]]; then
  echo "Error: storage_account output not found or incomplete" >&2
  exit 1
fi

if [[ -z "$resource_group_name" ]]; then
  echo "Error: resource_group output not found" >&2
  exit 1
fi

if [[ "$config_preview" == "true" ]]; then
  echo
  echo "Configuration preview"
  echo "---------------------"
  printf 'script_dir=%s\n' "$script_dir"
  printf 'terraform_dir=%s\n' "$terraform_dir"
  printf 'container_name=%s\n' "$container_name"
  printf 'auth_mode=%s\n' "$auth_mode"
  printf 'storage_account_name=%s\n' "$storage_account_name"
  printf 'storage_account_id=%s\n' "$storage_account_id"
  printf 'resource_group_name=%s\n' "$resource_group_name"
  printf 'primary_blob_endpoint=%s\n' "$primary_blob_endpoint"
  exit 0
fi

echo "Ensuring blob container '$container_name' exists in $storage_account_name..."

container_args=(--account-name "$storage_account_name" --name "$container_name")
if [[ "$auth_mode" == "login" ]]; then
  if ! az account show >/dev/null 2>&1; then
    echo "Error: Azure CLI is not logged in; run 'az login' or use --auth-mode key" >&2
    exit 1
  fi
  container_args+=(--auth-mode login)
else
  echo "Retrieving storage account access key..."
  account_key=$(az storage account keys list \
    --resource-group "$resource_group_name" \
    --account-name "$storage_account_name" \
    --query '[0].value' \
    --output tsv)
  if [[ -z "$account_key" ]]; then
    echo "Error: Unable to retrieve storage account key" >&2
    exit 1
  fi
  container_args+=(--account-key "$account_key")
fi

if az storage container show "${container_args[@]}" >/dev/null 2>&1; then
  echo "Container '$container_name' already exists."
else
  echo "Creating container '$container_name'..."
  az storage container create "${container_args[@]}" --public-access off >/dev/null
  echo "Container '$container_name' created."
fi

echo
printf 'Storage account: %s\n' "$storage_account_name"
printf 'Resource group: %s\n' "$resource_group_name"
printf 'Container name: %s\n' "$container_name"
printf 'Blob endpoint: %s\n' "$primary_blob_endpoint"

echo "Ready for workflow-config.yaml generation."
