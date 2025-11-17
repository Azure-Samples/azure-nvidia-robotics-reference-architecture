#!/usr/bin/env bash
set -euo pipefail

export EDITOR="${EDITOR:-vim}"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
values_dir="${script_dir}/values"
config_dir="${script_dir}/config"
scheduler_example="${config_dir}/scheduler-config-example.json"
scheduler_tmp="/tmp/scheduler_settings.json"
pool_config="${config_dir}/out/pool_config.json"
values_file="${values_dir}/backend-operator.yaml"

chart_version="1.0.0"
osmo_image_tag="6.0.0"
backend_name="default"
backend_description="Default backend pool"
service_url=""
image_pull_secret="nvcr-secret"
agent_namespace="osmo-operator"
backend_namespace="osmo-workflows"
account_secret="osmo-operator-token"
login_method="token"
config_preview=false
custom_expiry=""
regenerate_token=false

help="Usage: deploy-backend-operator.sh [OPTIONS]

Deploy the OSMO backend operator and configure backend scheduling.

REQUIRED:
  --service-url URL         External URL for the OSMO control plane service

OPTIONS:
  --chart-version VERSION   Helm chart version (default: 1.0.0)
  --osmo-image-tag TAG      OSMO image tag (default: 6.0.0)
  --backend-name NAME       Backend identifier (default: default)
  --backend-description TXT Description for pool configuration (default: Default backend pool)
  --image-pull-secret NAME  Image pull secret in target namespace (default: nvcr-secret)
  --agent-namespace NAME    Namespace for backend operator (default: osmo-operator)
  --backend-namespace NAME  Namespace for backend workloads (default: osmo-workflows)
  --account-secret NAME     Secret containing OSMO token (default: osmo-operator-token)
  --login-method METHOD     Backend login method (default: token)
  --expires-at DATE         Service token expiry date (YYYY-MM-DD, default: now + 1 year)
  --values-file PATH        Override path for generated values file
  --regenerate-token        Force creation of a fresh service token and update the secret
  --config-preview          Print configuration preview and exit
  --help                    Show this help message
"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --chart-version)
    chart_version="$2"
    shift 2
    ;;
  --osmo-image-tag)
    osmo_image_tag="$2"
    shift 2
    ;;
  --backend-name)
    backend_name="$2"
    shift 2
    ;;
  --backend-description)
    backend_description="$2"
    shift 2
    ;;
  --service-url)
    service_url="$2"
    shift 2
    ;;
  --image-pull-secret)
    image_pull_secret="$2"
    shift 2
    ;;
  --agent-namespace)
    agent_namespace="$2"
    shift 2
    ;;
  --backend-namespace)
    backend_namespace="$2"
    shift 2
    ;;
  --account-secret)
    account_secret="$2"
    shift 2
    ;;
  --login-method)
    login_method="$2"
    shift 2
    ;;
  --expires-at)
    custom_expiry="$2"
    shift 2
    ;;
  --values-file)
    values_file="$2"
    shift 2
    ;;
  --regenerate-token)
    regenerate_token=true
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

values_dir=$(dirname "$values_file")

if [[ -z "$service_url" ]]; then
  echo "Error: --service-url is required" >&2
  echo
  echo "$help"
  exit 1
fi

required_tools=(osmo kubectl helm jq date base64)
missing_tools=()
for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing_tools+=("$tool")
  fi
done

if [[ ${#missing_tools[@]} -gt 0 ]]; then
  echo "Error: Missing required tools: ${missing_tools[*]}" >&2
  exit 1
fi

expiry_date=""
if [[ -n "$custom_expiry" ]]; then
  if expiry_date=$(date -u -d "$custom_expiry" +%F 2>/dev/null); then
    :
  elif expiry_date=$(date -u -j -f "%Y-%m-%d" "$custom_expiry" +%F 2>/dev/null); then
    :
  else
    echo "Error: --expires-at must be a valid date in YYYY-MM-DD format" >&2
    exit 1
  fi
elif expiry_date=$(date -u -d "+1 year" +%F 2>/dev/null); then
  :
elif expiry_date=$(date -u -v+1y +%F 2>/dev/null); then
  :
else
  echo "Error: Unable to compute token expiry date" >&2
  exit 1
fi

if [[ "$config_preview" == true ]]; then
  echo
  echo "Configuration preview"
  echo "---------------------"
  printf 'script_dir=%s\n' "$script_dir"
  printf 'values_file=%s\n' "$values_file"
  printf 'scheduler_example=%s\n' "$scheduler_example"
  printf 'pool_config=%s\n' "$pool_config"
  printf 'chart_version=%s\n' "$chart_version"
  printf 'osmo_image_tag=%s\n' "$osmo_image_tag"
  printf 'backend_name=%s\n' "$backend_name"
  printf 'backend_description=%s\n' "$backend_description"
  printf 'service_url=%s\n' "$service_url"
  printf 'image_pull_secret=%s\n' "$image_pull_secret"
  printf 'agent_namespace=%s\n' "$agent_namespace"
  printf 'backend_namespace=%s\n' "$backend_namespace"
  printf 'account_secret=%s\n' "$account_secret"
  printf 'login_method=%s\n' "$login_method"
  printf 'computed_expiry_date=%s\n' "$expiry_date"
  exit 0
fi

mkdir -p "$values_dir" "$config_dir" "$config_dir/out"

cleanup() {
  if [[ -f "$scheduler_tmp" ]]; then
    rm -f "$scheduler_tmp"
  fi
}

trap cleanup EXIT

if [[ ! -f "$values_file" ]]; then
  echo "Error: Values file not found: $values_file" >&2
  exit 1
fi

if [[ ! -f "$scheduler_example" ]]; then
  echo "Error: Scheduler example not found: $scheduler_example" >&2
  exit 1
fi

scheduler_payload=$(cat "$scheduler_example")
for namespace in "$agent_namespace" "$backend_namespace"; do
  echo "Ensuring namespace $namespace exists..."
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
token_secret_exists=false
if kubectl get secret "$account_secret" -n "$agent_namespace" >/dev/null 2>&1; then
  token_secret_exists=true
fi

if [[ "$regenerate_token" == true || "$token_secret_exists" == false ]]; then
  timestamp=$(date -u +%Y%m%d%H%M%S)
  token_name="backend-token-${timestamp}"

  if [[ "$regenerate_token" == true ]]; then
    echo "Regenerating OSMO service token ${token_name}..."
  else
    echo "Generating OSMO service token ${token_name}..."
  fi

  token_json=$(osmo token set "$token_name" \
    --expires-at "$expiry_date" \
    --description "Backend Operator Token" \
    --service \
    --roles osmo-backend \
    -t json)

  OSMO_SERVICE_TOKEN=$(echo "$token_json" | jq -r '.token // empty')
  if [[ -z "$OSMO_SERVICE_TOKEN" || "$OSMO_SERVICE_TOKEN" == "null" ]]; then
    echo "Error: Failed to obtain service token" >&2
    exit 1
  fi
  export OSMO_SERVICE_TOKEN

  echo "Applying OSMO operator token secret ${account_secret}..."
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: ${account_secret}
  namespace: ${agent_namespace}
type: Opaque
data:
  token: $(printf '%s' "$OSMO_SERVICE_TOKEN" | base64)
EOF
else
  echo "Secret ${account_secret} already exists in namespace ${agent_namespace}; skipping token generation."
fi
echo "Ensuring OSMO Helm repository is configured..."
if ! helm repo list -o json | jq -e '.[] | select(.name == "osmo")' >/dev/null; then
  helm repo add osmo https://helm.ngc.nvidia.com/nvidia/osmo >/dev/null
fi
helm repo update >/dev/null

echo "Deploying backend operator chart..."
set -x
helm upgrade -i osmo-operator osmo/backend-operator \
  --values "$values_file" \
  --version "$chart_version" \
  --namespace "$agent_namespace" \
  --set-string global.osmoImageTag="${osmo_image_tag}" \
  --set-string global.imagePullSecret="${image_pull_secret}" \
  --set-string global.serviceUrl="${service_url}" \
  --set-string global.agentNamespace="${agent_namespace}" \
  --set-string global.backendNamespace="${backend_namespace}" \
  --set-string global.backendName="${backend_name}" \
  --set-string global.accountTokenSecret="${account_secret}" \
  --set-string global.loginMethod="${login_method}" \
  --wait \
  --timeout 10m
set +x

printf '%s\n' "$scheduler_payload" >"$scheduler_tmp"

echo "Updating backend configuration..."
osmo config update BACKEND "$backend_name" --file "$scheduler_tmp"

pool_json=$(jq -n --arg backend "$backend_name" --arg desc "$backend_description" '{default: {backend: $backend, description: $desc}}')
printf '%s\n' "$pool_json" >"$pool_config"

echo "Updating pool configuration..."
osmo config update POOL --file "$pool_config"

echo
printf 'Backend operator deployed with chart version %s\n' "$chart_version"
printf 'Backend name: %s\n' "$backend_name"
printf 'Backend namespace: %s\n' "$backend_namespace"
printf 'Agent namespace: %s\n' "$agent_namespace"
printf 'Service URL: %s\n' "$service_url"
printf 'Values file: %s\n' "$values_file"
printf 'Pool config: %s\n' "$pool_config"
