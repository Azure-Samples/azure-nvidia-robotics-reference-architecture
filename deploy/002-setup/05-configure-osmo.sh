#!/usr/bin/env bash
# Configure OSMO workflow storage and workload identity
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.conf
source "$SCRIPT_DIR/defaults.conf"

CONFIG_DIR="$SCRIPT_DIR/config"

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create blob container for OSMO workflow data and configure storage credentials.

OPTIONS:
    -h, --help              Show this help message
    -t, --tf-dir DIR        Terraform directory (default: $DEFAULT_TF_DIR)
    --container-name NAME   Blob container name (default: osmo)
    --use-acr               Use ACR for backend images (auto-detect from terraform)
    --acr-name NAME         Specify ACR name explicitly
    --ngc-token TOKEN       NGC API token (required when not using --use-acr)
    --use-access-keys       Use storage access keys instead of workload identity
    --skip-osmo-update      Skip running osmo config update
    --skip-workflow-sa      Skip creating workflow ServiceAccount
    --config-preview        Print configuration and exit

EXAMPLES:
    $(basename "$0") --use-acr
    $(basename "$0") --ngc-token YOUR_TOKEN
    $(basename "$0") --use-acr --use-access-keys
EOF
}

tf_dir="$SCRIPT_DIR/$DEFAULT_TF_DIR"
container_name="osmo"
use_acr=false
acr_name=""
ngc_token=""
use_access_keys=false
osmo_identity_client_id=""
skip_osmo_update=false
skip_workflow_sa=false
config_preview=false
output_file="$CONFIG_DIR/out/workflow-config.json"
access_key_id="osmo-control-plane-storage"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)            show_help; exit 0 ;;
    -t|--tf-dir)          tf_dir="$2"; shift 2 ;;
    --container-name)     container_name="$2"; shift 2 ;;
    --use-acr)            use_acr=true; shift ;;
    --acr-name)           acr_name="$2"; use_acr=true; shift 2 ;;
    --ngc-token)          ngc_token="$2"; shift 2 ;;
    --use-access-keys)    use_access_keys=true; shift ;;
    --osmo-identity-client-id) osmo_identity_client_id="$2"; shift 2 ;;
    --skip-osmo-update)   skip_osmo_update=true; shift ;;
    --skip-workflow-sa)   skip_workflow_sa=true; shift ;;
    --config-preview)     config_preview=true; shift ;;
    --output-file)        output_file="$2"; shift 2 ;;
    *)                    fatal "Unknown option: $1" ;;
  esac
done

[[ "$use_acr" == "false" && -z "$ngc_token" ]] && fatal "--ngc-token required when not using --use-acr"

require_tools terraform az kubectl envsubst

az account show &>/dev/null || fatal "Azure CLI not logged in; run 'az login'"

info "Reading terraform outputs from $tf_dir..."
tf_output=$(read_terraform_outputs "$tf_dir")
storage_name=$(tf_require "$tf_output" "storage_account.value.name" "Storage account name")
rg=$(tf_require "$tf_output" "resource_group.value.name" "Resource group")
location=$(tf_require "$tf_output" "resource_group.value.location" "Location")

[[ "$use_acr" == "true" && -z "$acr_name" ]] && acr_name=$(detect_acr_name "$tf_output")

if [[ "$use_access_keys" == "false" && -z "$osmo_identity_client_id" ]]; then
  osmo_identity_client_id=$(detect_osmo_identity "$tf_output")
fi

# Compute endpoints
account_fqdn="${storage_name}.blob.core.windows.net"
workflow_base_url="https://${account_fqdn}:443/${container_name}"
azure_container="azure://${storage_name}/${container_name}"
workflow_data="${azure_container}/workflows/data"
workflow_log="${azure_container}/workflows/logs"
workflow_app="${azure_container}/apps"
acr_login_server="${acr_name}.azurecr.io"

account_key=""
if [[ "$use_access_keys" == "true" ]]; then
  account_key=$(az storage account keys list --resource-group "$rg" --account-name "$storage_name" --query '[0].value' -o tsv)
  [[ -z "$account_key" ]] && fatal "Unable to retrieve storage account key"
fi

if [[ "$config_preview" == "true" ]]; then
  section "Configuration Preview"
  print_kv "Storage Account" "$storage_name"
  print_kv "Container" "$container_name"
  print_kv "Workflow Base URL" "$workflow_base_url"
  print_kv "ACR" "$([[ $use_acr == true ]] && echo "$acr_login_server" || echo 'NGC')"
  print_kv "Auth Mode" "$([[ $use_access_keys == true ]] && echo 'access-keys' || echo 'workload-identity')"
  exit 0
fi

section "Configure Blob Container"

if az storage container show --account-name "$storage_name" --name "$container_name" --auth-mode login &>/dev/null; then
  info "Container '$container_name' already exists"
else
  info "Creating container '$container_name'..."
  az storage container create --account-name "$storage_name" --name "$container_name" --auth-mode login --public-access off >/dev/null
fi

section "Render Workflow Configuration"

# Select template based on auth mode
auth_mode="workload-identity"
[[ "$use_access_keys" == "true" ]] && auth_mode="access-keys"
template_file="$CONFIG_DIR/workflow-config-${auth_mode}.template.json"
ngc_template_file="$CONFIG_DIR/workflow-backend-images-ngc.template.json"
ngc_output_file="$CONFIG_DIR/out/workflow-backend-images.json"

[[ -f "$template_file" ]] || fatal "Template not found: $template_file"
info "Using template: $(basename "$template_file")"

mkdir -p "$(dirname "$output_file")"

# Export variables for envsubst
export STORAGE_ACCESS_KEY_ID="$access_key_id"
export STORAGE_ACCESS_KEY="$account_key"
export WORKFLOW_BASE_URL="$workflow_base_url"
export WORKFLOW_DATA_ENDPOINT="$workflow_data"
export WORKFLOW_LOG_ENDPOINT="$workflow_log"
export WORKFLOW_APP_ENDPOINT="$workflow_app"
export AZURE_REGION="$location"
export ACR_LOGIN_SERVER="$acr_login_server"
export NGC_TOKEN="$ngc_token"

envsubst < "$template_file" > "$output_file"
info "Workflow config written to $output_file"

if [[ "$skip_osmo_update" == "false" ]]; then
  require_tools osmo
  info "Applying workflow storage configuration..."
  osmo config update WORKFLOW --file "$output_file" --description "Workflow storage configuration"

  # Apply NGC backend images config if not using ACR
  if [[ "$use_acr" == "false" ]]; then
    envsubst < "$ngc_template_file" > "$ngc_output_file"
    info "Applying NGC backend images configuration..."
    osmo config update WORKFLOW --file "$ngc_output_file" --description "NGC backend images"
  fi
fi

if [[ "$use_access_keys" == "false" && "$skip_workflow_sa" == "false" ]]; then
  section "Configure Workload Identity"

  ensure_namespace "$NS_OSMO_WORKFLOWS"

  info "Creating workflow ServiceAccount..."
  WORKFLOWS_NAMESPACE="$NS_OSMO_WORKFLOWS" \
  OSMO_IDENTITY_CLIENT_ID="$osmo_identity_client_id" \
    envsubst < "$SCRIPT_DIR/manifests/osmo-workflow-sa.yaml" | kubectl apply -f -
fi

section "Configuration Summary"
print_kv "Storage Account" "$storage_name"
print_kv "Container" "$container_name"
print_kv "Workflow Config" "$output_file"
print_kv "ACR" "$([[ $use_acr == true ]] && echo "$acr_login_server" || echo 'NGC')"
print_kv "Auth Mode" "$([[ $use_access_keys == true ]] && echo 'access-keys' || echo 'workload-identity')"

info "OSMO workflow configuration complete"
