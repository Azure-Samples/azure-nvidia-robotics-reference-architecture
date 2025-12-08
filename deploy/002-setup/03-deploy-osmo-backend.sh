#!/usr/bin/env bash
set -euo pipefail

export EDITOR="${EDITOR:-vim}"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
terraform_dir="${script_dir}/../001-iac"
values_dir="${script_dir}/values"
config_dir="${script_dir}/config"
scheduler_example="${config_dir}/scheduler-config-example.json"
scheduler_tmp="/tmp/scheduler_settings.json"
values_file="${values_dir}/osmo-backend-operator.yaml"
identity_values="${values_dir}/osmo-backend-operator-identity.yaml"
pod_template_example="${config_dir}/pod-template-config-example.json"
pod_template_output="${config_dir}/out/pod-template-config.json"
default_pool_example="${config_dir}/default-pool-config-example.json"
default_pool_output="${config_dir}/out/default-pool-config.json"

chart_version="1.0.0"
osmo_image_tag="6.0.0"
use_acr=false
acr_name=""
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
osmo_auth_mode="workload-identity"
osmo_identity_client_id=""

help="Usage: deploy-backend-operator.sh [OPTIONS]

Deploy the OSMO backend operator and configure backend scheduling.
By default, images and helm charts are pulled from NVIDIA NGC.
Use --use-acr or --acr-name to pull from Azure Container Registry instead.

OPTIONS:
  --service-url URL         URL for the OSMO control plane service (default: auto-detect from azureml-ingress-nginx-internal-lb)
  --terraform-dir PATH      Path to terraform directory for identity lookup (default: ../001-iac)
  --chart-version VERSION   Helm chart version (default: 1.0.0)
  --image-version TAG       OSMO image tag (default: 6.0.0)
  --backend-name NAME       Backend identifier (default: default)
  --backend-description TXT Description for pool configuration (default: Default backend pool)
  --use-acr                 Pull images/charts from ACR deployed by 001-iac (auto-detects ACR name)
  --acr-name NAME           Pull images/charts from specified ACR (implies --use-acr)
  --image-pull-secret NAME  Image pull secret in target namespace (default: nvcr-secret, ignored when using ACR)
  --agent-namespace NAME    Namespace for backend operator (default: osmo-operator)
  --backend-namespace NAME  Namespace for backend workloads (default: osmo-workflows)
  --account-secret NAME     Secret containing OSMO token (default: osmo-operator-token)
  --login-method METHOD     Backend login method (default: token)
  --expires-at DATE         Service token expiry date (YYYY-MM-DD, default: now + 1 year)
  --values-file PATH        Override path for generated values file
  --regenerate-token        Force creation of a fresh service token and update the secret
  --osmo-auth-mode MODE     OSMO storage authentication mode: key|workload-identity (default: workload-identity)
  --osmo-identity-client-id Client ID of OSMO managed identity (default: from terraform osmo_workload_identity output)
  --config-preview          Print configuration preview and exit
  --help                    Show this help message
"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --terraform-dir)
    terraform_dir="$2"
    shift 2
    ;;
  --chart-version)
    chart_version="$2"
    shift 2
    ;;
  --image-version | --osmo-image-tag)
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
  --use-acr)
    use_acr=true
    shift
    ;;
  --acr-name)
    acr_name="$2"
    use_acr=true
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
  --osmo-auth-mode)
    osmo_auth_mode="$2"
    shift 2
    ;;
  --osmo-identity-client-id)
    osmo_identity_client_id="$2"
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

values_dir=$(dirname "$values_file")

# Auto-detect service URL from internal load balancer if not provided
if [[ -z "$service_url" ]]; then
  echo "Auto-detecting OSMO service URL from azureml-ingress-nginx-internal-lb..."

  # Try azureml-ingress-nginx-internal-lb LoadBalancer (deployed by 02-deploy-osmo-control-plane.sh)
  lb_ip=$(kubectl get svc azureml-ingress-nginx-internal-lb -n azureml -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "$lb_ip" ]]; then
    service_url="http://${lb_ip}"
    echo "Detected service URL: ${service_url}"
  else
    # Fallback to azureml-ingress-nginx-controller ClusterIP (internal routing)
    cluster_ip=$(kubectl get svc azureml-ingress-nginx-controller -n azureml -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
    if [[ -n "$cluster_ip" && "$cluster_ip" != "None" ]]; then
      service_url="http://${cluster_ip}"
      echo "Detected service URL from azureml-ingress-nginx-controller ClusterIP: ${service_url}"
    else
      echo "Error: --service-url not provided and unable to detect from azureml-ingress-nginx-internal-lb or controller" >&2
      echo "Ensure 02-deploy-osmo-control-plane.sh has been run or provide --service-url manually" >&2
      exit 1
    fi
  fi
fi

case "$osmo_auth_mode" in
key|workload-identity) ;;
*)
  echo "Error: --osmo-auth-mode must be 'key' or 'workload-identity'" >&2
  exit 1
  ;;
esac

required_tools=(terraform osmo kubectl helm jq date base64)
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

if [[ "$osmo_auth_mode" == "workload-identity" && -z "$osmo_identity_client_id" ]]; then
  if [[ ! -d "$terraform_dir" ]]; then
    echo "Error: Terraform directory not found: $terraform_dir" >&2
    exit 1
  fi
  if [[ ! -f "${terraform_dir}/terraform.tfstate" ]]; then
    echo "Error: terraform.tfstate not found in $terraform_dir" >&2
    exit 1
  fi
  if ! tf_output=$(cd "$terraform_dir" && terraform output -json); then
    echo "Error: Unable to read terraform outputs" >&2
    exit 1
  fi
  osmo_identity_client_id=$(echo "$tf_output" | jq -r '.osmo_workload_identity.value.client_id // empty')
  if [[ -z "$osmo_identity_client_id" ]]; then
    echo "Error: --osmo-identity-client-id not provided and osmo_workload_identity output not found in terraform state" >&2
    exit 1
  fi
fi

if [[ "${use_acr}" == "true" && -z "${acr_name}" ]]; then
  if [[ ! -d "$terraform_dir" ]]; then
    echo "Error: Terraform directory not found: $terraform_dir" >&2
    exit 1
  fi
  if [[ ! -f "${terraform_dir}/terraform.tfstate" ]]; then
    echo "Error: terraform.tfstate not found in $terraform_dir" >&2
    exit 1
  fi
  if ! tf_output=$(cd "$terraform_dir" && terraform output -json); then
    echo "Error: Unable to read terraform outputs" >&2
    exit 1
  fi
  acr_name=$(echo "$tf_output" | jq -r '.container_registry.value.name // empty')
  if [[ -z "$acr_name" ]]; then
    echo "Error: --use-acr specified but container_registry output not found in terraform state" >&2
    exit 1
  fi
fi

if [[ "${use_acr}" == "true" ]]; then
  image_pull_secret=""
fi

if [[ "$config_preview" == true ]]; then
  echo
  echo "Configuration preview"
  echo "---------------------"
  printf 'script_dir=%s\n' "$script_dir"
  printf 'terraform_dir=%s\n' "$terraform_dir"
  printf 'values_file=%s\n' "$values_file"
  printf 'scheduler_example=%s\n' "$scheduler_example"
  printf 'pod_template_example=%s\n' "$pod_template_example"
  printf 'default_pool_example=%s\n' "$default_pool_example"
  printf 'pod_template_output=%s\n' "$pod_template_output"
  printf 'default_pool_output=%s\n' "$default_pool_output"
  printf 'chart_version=%s\n' "$chart_version"
  printf 'osmo_image_tag=%s\n' "$osmo_image_tag"
  printf 'use_acr=%s\n' "$use_acr"
  printf 'acr_name=%s\n' "$acr_name"
  printf 'backend_name=%s\n' "$backend_name"
  printf 'backend_description=%s\n' "$backend_description"
  printf 'service_url=%s\n' "$service_url"
  printf 'image_pull_secret=%s\n' "$image_pull_secret"
  printf 'agent_namespace=%s\n' "$agent_namespace"
  printf 'backend_namespace=%s\n' "$backend_namespace"
  printf 'account_secret=%s\n' "$account_secret"
  printf 'login_method=%s\n' "$login_method"
  printf 'computed_expiry_date=%s\n' "$expiry_date"
  printf 'osmo_auth_mode=%s\n' "$osmo_auth_mode"
  printf 'osmo_identity_client_id=%s\n' "$osmo_identity_client_id"
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

if [[ ! -f "$pod_template_example" ]]; then
  echo "Error: Pod template example not found: $pod_template_example" >&2
  exit 1
fi

if [[ ! -f "$default_pool_example" ]]; then
  echo "Error: Default pool example not found: $default_pool_example" >&2
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

echo "Writing pod template configuration to ${pod_template_output}..."
cp "$pod_template_example" "$pod_template_output"

echo "Rendering default pool configuration..."
default_pool_payload=$(jq --arg backend "$backend_name" --arg desc "$backend_description" '
  .name = $backend
  | .backend = $backend
  | .description = $desc
' "$default_pool_example")

if [[ -z "$default_pool_payload" ]]; then
  echo "Error: Failed to render default pool configuration" >&2
  exit 1
fi

printf '%s\n' "$default_pool_payload" >"$default_pool_output"

if [[ "${use_acr}" == "true" ]]; then
  echo "Logging into Azure Container Registry ${acr_name}..."
  az acr login --name "${acr_name}"
else
  echo "Ensuring OSMO Helm repository is configured..."
  if ! helm repo list -o json | jq -e '.[] | select(.name == "osmo")' >/dev/null; then
    helm repo add osmo https://helm.ngc.nvidia.com/nvidia/osmo >/dev/null
  fi
  helm repo update >/dev/null
fi

echo "Deploying backend operator chart..."
set -x
helm_backend_args=(
  --values "$values_file"
  --version "$chart_version"
  --namespace "$agent_namespace"
  --set-string "global.osmoImageTag=${osmo_image_tag}"
  --set-string "global.serviceUrl=${service_url}"
  --set-string "global.agentNamespace=${agent_namespace}"
  --set-string "global.backendNamespace=${backend_namespace}"
  --set-string "global.backendName=${backend_name}"
  --set-string "global.accountTokenSecret=${account_secret}"
  --set-string "global.loginMethod=${login_method}"
)

if [[ "${use_acr}" == "true" ]]; then
  helm_backend_args+=(
    --set "global.osmoImageLocation=${acr_name}.azurecr.io/osmo"
    --set "global.imagePullSecret="
  )
else
  helm_backend_args+=(
    --set-string "global.imagePullSecret=${image_pull_secret}"
  )
fi

if [[ "$osmo_auth_mode" == "workload-identity" ]]; then
  helm_backend_args+=(
    -f "$identity_values"
    --set "serviceAccount.annotations.azure\.workload\.identity/client-id=${osmo_identity_client_id}"
  )
fi

if [[ "${use_acr}" == "true" ]]; then
  helm upgrade -i osmo-operator "oci://${acr_name}.azurecr.io/helm/backend-operator" "${helm_backend_args[@]}" --wait --timeout 10m
else
  helm upgrade -i osmo-operator osmo/backend-operator "${helm_backend_args[@]}" --wait --timeout 10m
fi
set +x

printf '%s\n' "$scheduler_payload" >"$scheduler_tmp"

echo "Updating pod template configuration..."
osmo config update POD_TEMPLATE --file "$pod_template_output" --description "Pod template configuration"

echo "Updating backend configuration..."
osmo config update BACKEND "$backend_name" --file "$scheduler_tmp" --description "Backend ${backend_name} configuration"

echo "Updating pool configuration..."
osmo config update POOL "$backend_name" --file "$default_pool_output" --description "Pool ${backend_name} configuration"

echo "Setting default pool profile to ${backend_name}..."
osmo profile set pool "$backend_name"

echo
printf 'Backend operator deployed with chart version %s\n' "$chart_version"
printf 'Backend name: %s\n' "$backend_name"
printf 'Backend namespace: %s\n' "$backend_namespace"
printf 'Agent namespace: %s\n' "$agent_namespace"
printf 'Service URL: %s\n' "$service_url"
printf 'Values file: %s\n' "$values_file"
printf 'Scheduler config example: %s\n' "$scheduler_example"
printf 'Default pool config: %s\n' "$default_pool_output"
printf 'Pod template config: %s\n' "$pod_template_output"
printf 'Auth mode: %s\n' "$osmo_auth_mode"
if [[ "$osmo_auth_mode" == "workload-identity" ]]; then
  printf 'Identity client ID: %s\n' "$osmo_identity_client_id"
fi
