#!/usr/bin/env bash
# Deploy OSMO Backend Operator and configure backend scheduling
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.conf
source "$SCRIPT_DIR/defaults.conf"

VALUES_DIR="$SCRIPT_DIR/values"
CONFIG_DIR="$SCRIPT_DIR/config"
export EDITOR="${EDITOR:-vim}"

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy OSMO Backend Operator and configure backend scheduling.

OPTIONS:
    -h, --help              Show this help message
    -t, --tf-dir DIR        Terraform directory (default: $DEFAULT_TF_DIR)
    --service-url URL       OSMO control plane URL (default: auto-detect)
    --chart-version VER     Helm chart version (default: $OSMO_CHART_VERSION)
    --image-version TAG     OSMO image tag (default: $OSMO_IMAGE_VERSION)
    --backend-name NAME     Backend identifier (default: default)
    --use-acr               Pull from ACR deployed by 001-iac
    --acr-name NAME         Pull from specified ACR
    --use-access-keys       Use storage access keys instead of workload identity
    --regenerate-token      Force creation of a fresh service token
    --expires-at DATE       Token expiry date YYYY-MM-DD (default: +1 year)
    --config-preview        Print configuration and exit

EXAMPLES:
    $(basename "$0")
    $(basename "$0") --use-acr --backend-name gpu-pool
    $(basename "$0") --service-url http://10.0.0.1
EOF
}

tf_dir="$SCRIPT_DIR/$DEFAULT_TF_DIR"
chart_version="$OSMO_CHART_VERSION"
image_version="$OSMO_IMAGE_VERSION"
backend_name="default"
backend_description="Default backend pool"
service_url=""
use_acr=false
acr_name=""
use_access_keys=false
osmo_identity_client_id=""
regenerate_token=false
custom_expiry=""
config_preview=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)            show_help; exit 0 ;;
    -t|--tf-dir)          tf_dir="$2"; shift 2 ;;
    --service-url)        service_url="$2"; shift 2 ;;
    --chart-version)      chart_version="$2"; shift 2 ;;
    --image-version)      image_version="$2"; shift 2 ;;
    --backend-name)       backend_name="$2"; shift 2 ;;
    --backend-description) backend_description="$2"; shift 2 ;;
    --use-acr)            use_acr=true; shift ;;
    --acr-name)           acr_name="$2"; use_acr=true; shift 2 ;;
    --use-access-keys)    use_access_keys=true; shift ;;
    --osmo-identity-client-id) osmo_identity_client_id="$2"; shift 2 ;;
    --regenerate-token)   regenerate_token=true; shift ;;
    --expires-at)         custom_expiry="$2"; shift 2 ;;
    --config-preview)     config_preview=true; shift ;;
    *)                    fatal "Unknown option: $1" ;;
  esac
done

require_tools terraform osmo kubectl helm jq date base64

# Auto-detect service URL if not provided
if [[ -z "$service_url" ]]; then
  info "Auto-detecting OSMO service URL..."
  service_url=$(detect_service_url)
  [[ -z "$service_url" ]] && fatal "Could not detect service URL. Run 03-deploy-osmo-control-plane.sh first or provide --service-url"
  info "Detected: $service_url"
fi

# Read terraform outputs for ACR and identity
tf_output=""
if [[ "$use_acr" == "true" || "$use_access_keys" == "false" ]]; then
  info "Reading terraform outputs from $tf_dir..."
  tf_output=$(read_terraform_outputs "$tf_dir")
fi

[[ "$use_acr" == "true" && -z "$acr_name" ]] && acr_name=$(detect_acr_name "$tf_output")

if [[ "$use_access_keys" == "false" && -z "$osmo_identity_client_id" ]]; then
  osmo_identity_client_id=$(detect_osmo_identity "$tf_output")
fi

# Compute token expiry
expiry_date=""
if [[ -n "$custom_expiry" ]]; then
  expiry_date=$(date -u -d "$custom_expiry" +%F 2>/dev/null) || \
    expiry_date=$(date -u -j -f "%Y-%m-%d" "$custom_expiry" +%F 2>/dev/null) || \
    fatal "--expires-at must be YYYY-MM-DD format"
else
  expiry_date=$(date -u -d "+1 year" +%F 2>/dev/null) || \
    expiry_date=$(date -u -v+1y +%F 2>/dev/null) || \
    fatal "Unable to compute token expiry date"
fi

if [[ "$config_preview" == "true" ]]; then
  section "Configuration Preview"
  print_kv "Service URL" "$service_url"
  print_kv "Backend Name" "$backend_name"
  print_kv "Chart Version" "$chart_version"
  print_kv "Image Version" "$image_version"
  print_kv "ACR" "$([[ $use_acr == true ]] && echo "$acr_name" || echo 'NGC')"
  print_kv "Auth Mode" "$([[ $use_access_keys == true ]] && echo 'access-keys' || echo 'workload-identity')"
  print_kv "Token Expiry" "$expiry_date"
  exit 0
fi

# Config file paths
values_file="$VALUES_DIR/osmo-backend-operator.yaml"
identity_values="$VALUES_DIR/osmo-backend-operator-identity.yaml"
scheduler_template="$CONFIG_DIR/scheduler-config.template.json"
pod_template_file="$CONFIG_DIR/pod-template-config.template.json"
default_pool_template="$CONFIG_DIR/default-pool-config.template.json"
pod_template_output="$CONFIG_DIR/out/pod-template-config.json"
default_pool_output="$CONFIG_DIR/out/default-pool-config.json"
scheduler_output="$CONFIG_DIR/out/scheduler-config.json"
account_secret="osmo-operator-token"

for f in "$values_file" "$scheduler_template" "$pod_template_file" "$default_pool_template"; do
  [[ -f "$f" ]] || fatal "Required file not found: $f"
done

mkdir -p "$CONFIG_DIR/out"

section "Prepare Namespaces and Token"

ensure_namespace "$NS_OSMO_OPERATOR"
ensure_namespace "$NS_OSMO_WORKFLOWS"

token_exists=false
kubectl get secret "$account_secret" -n "$NS_OSMO_OPERATOR" &>/dev/null && token_exists=true

if [[ "$regenerate_token" == "true" || "$token_exists" == "false" ]]; then
  token_name="backend-token-$(date -u +%Y%m%d%H%M%S)"
  info "Generating OSMO service token $token_name..."

  token_json=$(osmo token set "$token_name" \
    --expires-at "$expiry_date" \
    --description "Backend Operator Token" \
    --service --roles osmo-backend -t json)

  OSMO_SERVICE_TOKEN=$(echo "$token_json" | jq -r '.token // empty')
  [[ -z "$OSMO_SERVICE_TOKEN" ]] && fatal "Failed to obtain service token"
  export OSMO_SERVICE_TOKEN

  kubectl create secret generic "$account_secret" \
    --namespace="$NS_OSMO_OPERATOR" \
    --from-literal=token="$OSMO_SERVICE_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
else
  info "Token secret $account_secret already exists"
fi

section "Render Pool Configuration"

export GPU_INSTANCE_TYPE
export WORKFLOW_SERVICE_ACCOUNT
envsubst < "$pod_template_file" > "$pod_template_output"

export BACKEND_NAME="$backend_name"
export BACKEND_DESCRIPTION="$backend_description"
envsubst < "$default_pool_template" > "$default_pool_output"

section "Deploy Backend Operator"

if [[ "$use_acr" == "true" ]]; then
  login_acr "$acr_name"
else
  helm repo list -o json | jq -e '.[] | select(.name == "osmo")' >/dev/null 2>&1 || \
    helm repo add osmo https://helm.ngc.nvidia.com/nvidia/osmo >/dev/null
  helm repo update >/dev/null
fi

helm_args=(
  --values "$values_file"
  --version "$chart_version"
  --namespace "$NS_OSMO_OPERATOR"
  --set-string "global.osmoImageTag=$image_version"
  --set-string "global.serviceUrl=$service_url"
  --set-string "global.agentNamespace=$NS_OSMO_OPERATOR"
  --set-string "global.backendNamespace=$NS_OSMO_WORKFLOWS"
  --set-string "global.backendName=$backend_name"
  --set-string "global.accountTokenSecret=$account_secret"
  --set-string "global.loginMethod=token"
)

if [[ "$use_acr" == "true" ]]; then
  helm_args+=(
    --set "global.osmoImageLocation=${acr_name}.azurecr.io/osmo"
    --set "global.imagePullSecret="
  )
else
  helm_args+=(--set-string "global.imagePullSecret=$SECRET_NGC")
fi

if [[ "$use_access_keys" == "false" ]]; then
  helm_args+=(
    -f "$identity_values"
    --set "serviceAccount.annotations.azure\.workload\.identity/client-id=$osmo_identity_client_id"
  )
fi

if [[ "$use_acr" == "true" ]]; then
  helm upgrade -i osmo-operator "oci://${acr_name}.azurecr.io/helm/backend-operator" "${helm_args[@]}" --wait --timeout "$TIMEOUT_DEPLOY"
else
  helm upgrade -i osmo-operator osmo/backend-operator "${helm_args[@]}" --wait --timeout "$TIMEOUT_DEPLOY"
fi

section "Configure OSMO Backend"

export K8S_NAMESPACE="$NS_OSMO_WORKFLOWS"
export CONTROL_PLANE_NAMESPACE="$NS_OSMO_CONTROL_PLANE"
envsubst < "$scheduler_template" > "$scheduler_output"

info "Updating pod template configuration..."
osmo config update POD_TEMPLATE --file "$pod_template_output" --description "Pod template configuration"

info "Updating backend configuration..."
osmo config update BACKEND "$backend_name" --file "$scheduler_output" --description "Backend $backend_name configuration"

info "Updating pool configuration..."
osmo config update POOL "$backend_name" --file "$default_pool_output" --description "Pool $backend_name configuration"

info "Setting default pool profile..."
osmo profile set pool "$backend_name"

section "Deployment Summary"
print_kv "Backend Name" "$backend_name"
print_kv "Service URL" "$service_url"
print_kv "Chart Version" "$chart_version"
print_kv "Image Version" "$image_version"
print_kv "Agent Namespace" "$NS_OSMO_OPERATOR"
print_kv "Backend Namespace" "$NS_OSMO_WORKFLOWS"
print_kv "Auth Mode" "$([[ $use_access_keys == true ]] && echo 'access-keys' || echo 'workload-identity')"
echo
kubectl get pods -n "$NS_OSMO_OPERATOR" --no-headers | head -5

info "Backend operator deployment complete"
