#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
terraform_dir="${script_dir}/../001-iac"
container_name="osmo"
auth_mode="login"
config_preview=false
template_file="${script_dir}/config/workflow-config-example.json"
output_file="${script_dir}/config/out/workflow-config.json"
apply_osmo_update=false
access_key_id="osmo-control-plane-storage"
acr_login_server_override=""
ngc_token=""
osmo_auth_mode="workload-identity"
osmo_identity_client_id=""

help="Usage: configure-osmo-storage.sh [OPTIONS]

Creates the blob container backing OSMO workflow data.

OPTIONS:
  --terraform-dir PATH      Path to terraform deployment directory (default: ../001-iac)
  --container-name NAME     Blob container name to ensure (default: osmo)
  --auth-mode MODE          Authentication mode for az storage commands: login|key (default: login)
  --template PATH           Workflow config template to render (default: ./config/workflow-config-example.json)
  --output-file PATH        Output path for rendered workflow config (default: ./config/out/workflow-config.json)
  --apply-osmo              Run 'osmo config update WORKFLOW --file <output>' after rendering
  --access-key-id VALUE     Override access key identifier in rendered config (default: osmo-control-plane-storage)
  --acr-login-server HOST   Override ACR login server if multiple are present
  --ngc-token TOKEN         NGC API token used for backend image pulls (required)
  --osmo-auth-mode MODE     OSMO storage credential mode: key|workload-identity (default: workload-identity)
  --osmo-identity-client-id Client ID of OSMO managed identity (default: from terraform osmo_workload_identity output)
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
  --template)
    template_file="$2"
    shift 2
    ;;
  --output-file)
    output_file="$2"
    shift 2
    ;;
  --access-key-id)
    access_key_id="$2"
    shift 2
    ;;
  --acr-login-server)
    acr_login_server_override="$2"
    shift 2
    ;;
  --ngc-token)
    ngc_token="$2"
    shift 2
    ;;
  --osmo-auth-mode)
    osmo_auth_mode="$2"
    shift 2
    ;;
  --osmo-identity-client-id)
    osmo_identity_client_id="$2"
    shift 2
    ;;
  --apply-osmo)
    apply_osmo_update=true
    shift
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

case "$osmo_auth_mode" in
key|workload-identity) ;;
*)
  echo "Error: --osmo-auth-mode must be 'key' or 'workload-identity'" >&2
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

if [[ ! -f "$template_file" ]]; then
  echo "Error: Template not found: $template_file" >&2
  exit 1
fi

if [[ -z "$access_key_id" ]]; then
  echo "Error: --access-key-id cannot be empty" >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "Error: Azure CLI is not logged in; run 'az login'" >&2
  exit 1
fi

if [[ -z "$ngc_token" ]]; then
  echo "Error: --ngc-token is required" >&2
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
location=$(echo "$tf_output" | jq -r '.resource_group.value.location // empty')

if [[ "$osmo_auth_mode" == "workload-identity" && -z "$osmo_identity_client_id" ]]; then
  osmo_identity_client_id=$(echo "$tf_output" | jq -r '.osmo_workload_identity.value.client_id // empty')
  if [[ -z "$osmo_identity_client_id" ]]; then
    echo "Error: --osmo-identity-client-id not provided and osmo_workload_identity output not found in terraform state" >&2
    exit 1
  fi
fi

if [[ -z "$storage_account_name" || -z "$storage_account_id" ]]; then
  echo "Error: storage_account output not found or incomplete" >&2
  exit 1
fi

if [[ -z "$resource_group_name" ]]; then
  echo "Error: resource_group output not found" >&2
  exit 1
fi

if [[ -z "$primary_blob_endpoint" ]]; then
  echo "Error: primary blob endpoint not available from terraform outputs" >&2
  exit 1
fi

if [[ -z "$location" ]]; then
  echo "Error: resource group location not available from terraform outputs" >&2
  exit 1
fi

account_fqdn=${primary_blob_endpoint#https://}
account_fqdn=${account_fqdn%%/}
workflow_base_url="https://${account_fqdn}:443/${container_name}"
azure_container_base="azure://${storage_account_name}/${container_name}"
workflow_data_endpoint="${azure_container_base}/workflows/data"
workflow_log_endpoint="${azure_container_base}/workflows/logs"
workflow_app_endpoint="${azure_container_base}/apps"

if [[ "$osmo_auth_mode" == "key" ]]; then
  account_key=$(az storage account keys list \
    --resource-group "$resource_group_name" \
    --account-name "$storage_account_name" \
    --query '[0].value' \
    --output tsv)

  if [[ -z "$account_key" ]]; then
    echo "Error: Unable to retrieve storage account key" >&2
    exit 1
  fi
else
  account_key=""
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
  printf 'resource_group_name=%s\n' "$resource_group_name"
  printf 'primary_blob_endpoint=%s\n' "$primary_blob_endpoint"
  printf 'location=%s\n' "$location"
  printf 'workflow_base_url=%s\n' "$workflow_base_url"
  printf 'azure_container_base=%s\n' "$azure_container_base"
  printf 'workflow_data_endpoint=%s\n' "$workflow_data_endpoint"
  printf 'workflow_log_endpoint=%s\n' "$workflow_log_endpoint"
  printf 'workflow_app_endpoint=%s\n' "$workflow_app_endpoint"
  printf 'account_key(sha1)=%s\n' "$(printf '%s' "$account_key" | shasum | awk '{print $1}')"
  printf 'ngc_token(sha1)=%s\n' "$(printf '%s' "$ngc_token" | shasum | awk '{print $1}')"
  printf 'template_file=%s\n' "$template_file"
  printf 'output_file=%s\n' "$output_file"
  printf 'osmo_auth_mode=%s\n' "$osmo_auth_mode"
  printf 'osmo_identity_client_id=%s\n' "$osmo_identity_client_id"
  exit 0
fi

echo "Ensuring blob container '$container_name' exists in $storage_account_name..."

container_args=(--account-name "$storage_account_name" --name "$container_name")
if [[ "$auth_mode" == "login" ]]; then
  container_args+=(--auth-mode login)
else
  container_args+=(--account-key "$account_key")
fi

if az storage container show "${container_args[@]}" >/dev/null 2>&1; then
  echo "Container '$container_name' already exists."
else
  echo "Creating container '$container_name'..."
  az storage container create "${container_args[@]}" --public-access off >/dev/null
  echo "Container '$container_name' created."
fi

acr_login_server=""
if [[ -n "$acr_login_server_override" ]]; then
  acr_login_server="$acr_login_server_override"
else
  mapfile -t acr_servers < <(az acr list \
    --resource-group "$resource_group_name" \
    --query '[].loginServer' \
    --output tsv)
  if [[ ${#acr_servers[@]} -eq 0 ]]; then
    echo "Error: No Azure Container Registry instances found in resource group ${resource_group_name}" >&2
    exit 1
  fi
  acr_login_server="${acr_servers[0]}"
  if [[ ${#acr_servers[@]} -gt 1 ]]; then
    echo "Warning: Multiple container registries detected; using ${acr_login_server}. Override with --acr-login-server if needed." >&2
  fi
fi

if [[ "$osmo_auth_mode" == "key" ]]; then
  rendered_config=$(jq \
    --arg accessKeyId "$access_key_id" \
    --arg storageAccessKey "$account_key" \
    --arg workflowBaseUrl "$workflow_base_url" \
    --arg workflowDataEndpoint "$workflow_data_endpoint" \
    --arg workflowLogEndpoint "$workflow_log_endpoint" \
    --arg workflowAppEndpoint "$workflow_app_endpoint" \
    --arg region "$location" \
    --arg acr "$acr_login_server" \
    --arg ngcToken "$ngc_token" \
    '(.workflow_data.credential.access_key_id = $accessKeyId)
     | (.workflow_data.credential.access_key = $storageAccessKey)
     | (.workflow_data.credential.endpoint = $workflowDataEndpoint)
     | (.workflow_data.credential.region = $region)
     | (.workflow_data.base_url = $workflowBaseUrl)
     | (.workflow_log.credential.access_key_id = $accessKeyId)
     | (.workflow_log.credential.access_key = $storageAccessKey)
     | (.workflow_log.credential.endpoint = $workflowLogEndpoint)
     | (.workflow_log.credential.region = $region)
     | (.workflow_app.credential.access_key_id = $accessKeyId)
     | (.workflow_app.credential.access_key = $storageAccessKey)
     | (.workflow_app.credential.endpoint = $workflowAppEndpoint)
     | (.workflow_app.credential.region = $region)
     | (.credential_config.disable_registry_validation[1] = $acr)
     | (.backend_images.credential.auth = $ngcToken)
    ' "$template_file")
else
  rendered_config=$(jq \
    --arg accessKeyId "$access_key_id" \
    --arg workflowBaseUrl "$workflow_base_url" \
    --arg workflowDataEndpoint "$workflow_data_endpoint" \
    --arg workflowLogEndpoint "$workflow_log_endpoint" \
    --arg workflowAppEndpoint "$workflow_app_endpoint" \
    --arg region "$location" \
    --arg acr "$acr_login_server" \
    --arg ngcToken "$ngc_token" \
    '(.workflow_data.credential.access_key_id = $accessKeyId)
     | (.workflow_data.credential.endpoint = $workflowDataEndpoint)
     | (.workflow_data.credential.region = $region)
     | (.workflow_data.base_url = $workflowBaseUrl)
     | del(.workflow_data.credential.access_key)
     | (.workflow_log.credential.access_key_id = $accessKeyId)
     | (.workflow_log.credential.endpoint = $workflowLogEndpoint)
     | (.workflow_log.credential.region = $region)
     | del(.workflow_log.credential.access_key)
     | (.workflow_app.credential.access_key_id = $accessKeyId)
     | (.workflow_app.credential.endpoint = $workflowAppEndpoint)
     | (.workflow_app.credential.region = $region)
     | del(.workflow_app.credential.access_key)
     | (.credential_config.disable_registry_validation[1] = $acr)
     | (.backend_images.credential.auth = $ngcToken)
    ' "$template_file")
fi

if [[ -z "$rendered_config" ]]; then
  echo "Error: Failed to render workflow configuration" >&2
  exit 1
fi

output_dir=$(dirname "$output_file")
mkdir -p "$output_dir"

printf '%s\n' "$rendered_config" > "$output_file"

echo
printf 'Storage account: %s\n' "$storage_account_name"
printf 'Resource group: %s\n' "$resource_group_name"
printf 'Container name: %s\n' "$container_name"
printf 'Azure container base: %s\n' "$azure_container_base"
printf 'Workflow config: %s\n' "$output_file"
printf 'ACR login server: %s\n' "$acr_login_server"
printf 'OSMO auth mode: %s\n' "$osmo_auth_mode"
if [[ "$osmo_auth_mode" == "workload-identity" ]]; then
  printf 'Identity client ID: %s\n' "$osmo_identity_client_id"
fi

echo "Workflow configuration rendered successfully."

if [[ "$apply_osmo_update" == "true" ]]; then
  if ! command -v osmo &>/dev/null; then
    echo "Error: osmo CLI not found; install it or rerun without --apply-osmo" >&2
    exit 1
  fi

  echo "Applying workflow configuration via osmo CLI..."
  osmo config update WORKFLOW --file "$output_file"
  echo "osmo workflow configuration updated."
fi
