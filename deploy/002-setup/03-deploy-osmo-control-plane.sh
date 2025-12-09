#!/usr/bin/env bash
# Deploy OSMO Control Plane components (service, router, web-ui)
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.conf
source "$SCRIPT_DIR/defaults.conf"

VALUES_DIR="$SCRIPT_DIR/values"
CONFIG_DIR="$SCRIPT_DIR/config"

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy OSMO Control Plane components to AKS.

REGISTRY OPTIONS (one required):
    --ngc-token TOKEN       NGC API token (required for NGC registry)
    --use-acr               Pull from ACR deployed by 001-iac
    --acr-name NAME         Pull from specified ACR

OPTIONS:
    -h, --help              Show this help message
    -t, --tf-dir DIR        Terraform directory (default: $DEFAULT_TF_DIR)
    --chart-version VER     Helm chart version (default: $OSMO_CHART_VERSION)
    --image-version TAG     OSMO image tag (default: $OSMO_IMAGE_VERSION)
    --use-access-keys       Use storage access keys instead of workload identity
    --skip-mek              Skip MEK configuration
    --force-mek             Replace existing MEK (data loss warning)
    --mek-config-file PATH  Use existing MEK config file
    --use-incluster-redis   Use in-cluster Redis instead of Azure Managed Redis
    --skip-service-config   Skip service_base_url configuration
    --config-preview        Print configuration and exit

EXAMPLES:
    $(basename "$0") --ngc-token YOUR_TOKEN
    $(basename "$0") --use-acr
    $(basename "$0") --use-acr --use-access-keys
EOF
}

tf_dir="$SCRIPT_DIR/$DEFAULT_TF_DIR"
ngc_token=""
use_acr=false
acr_name=""
chart_version="$OSMO_CHART_VERSION"
image_version="$OSMO_IMAGE_VERSION"
use_access_keys=false
osmo_identity_client_id=""
skip_mek=false
force_mek=false
mek_config_file=""
use_incluster_redis=false
skip_service_config=false
config_preview=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)            show_help; exit 0 ;;
    -t|--tf-dir)          tf_dir="$2"; shift 2 ;;
    --ngc-token)          ngc_token="$2"; shift 2 ;;
    --use-acr)            use_acr=true; shift ;;
    --acr-name)           acr_name="$2"; use_acr=true; shift 2 ;;
    --chart-version)      chart_version="$2"; shift 2 ;;
    --image-version)      image_version="$2"; shift 2 ;;
    --use-access-keys)    use_access_keys=true; shift ;;
    --osmo-identity-client-id) osmo_identity_client_id="$2"; shift 2 ;;
    --skip-mek)           skip_mek=true; shift ;;
    --force-mek)          force_mek=true; shift ;;
    --mek-config-file)    mek_config_file="$2"; shift 2 ;;
    --use-incluster-redis) use_incluster_redis=true; shift ;;
    --skip-service-config) skip_service_config=true; shift ;;
    --config-preview)     config_preview=true; shift ;;
    *)                    fatal "Unknown option: $1" ;;
  esac
done

[[ "$use_acr" == "false" && -z "$ngc_token" ]] && fatal "--ngc-token required when not using ACR"

require_tools az terraform kubectl helm jq base64 openssl

info "Reading terraform outputs from $tf_dir..."
tf_output=$(read_terraform_outputs "$tf_dir")
cluster=$(tf_require "$tf_output" "aks_cluster.value.name" "AKS cluster name")
rg=$(tf_require "$tf_output" "resource_group.value.name" "Resource group")
pg_fqdn=$(tf_require "$tf_output" "postgresql_connection_info.value.fqdn" "PostgreSQL FQDN")
pg_user=$(tf_require "$tf_output" "postgresql_connection_info.value.admin_username" "PostgreSQL user")
keyvault=$(tf_require "$tf_output" "key_vault_name.value" "Key Vault name")
redis_hostname=$(tf_get "$tf_output" "managed_redis_connection_info.value.hostname")
redis_port=$(tf_get "$tf_output" "managed_redis_connection_info.value.port" "6380")

[[ "$use_acr" == "true" && -z "$acr_name" ]] && acr_name=$(detect_acr_name "$tf_output")

if [[ "$use_access_keys" == "false" && -z "$osmo_identity_client_id" ]]; then
  osmo_identity_client_id=$(detect_osmo_identity "$tf_output")
fi

[[ "$use_incluster_redis" == "false" && -z "$redis_hostname" ]] && \
  fatal "Redis not deployed. Use --use-incluster-redis or ensure should_deploy_redis is true."

if [[ "$config_preview" == "true" ]]; then
  section "Configuration Preview"
  print_kv "Cluster" "$cluster"
  print_kv "Resource Group" "$rg"
  print_kv "PostgreSQL" "$pg_fqdn"
  print_kv "Redis" "$([[ $use_incluster_redis == true ]] && echo 'in-cluster' || echo "$redis_hostname:$redis_port")"
  print_kv "ACR" "$([[ $use_acr == true ]] && echo "$acr_name" || echo 'NGC')"
  print_kv "Auth Mode" "$([[ $use_access_keys == true ]] && echo 'access-keys' || echo 'workload-identity')"
  print_kv "Chart Version" "$chart_version"
  print_kv "Image Version" "$image_version"
  exit 0
fi

connect_aks "$rg" "$cluster"
ensure_namespace "$NS_OSMO_CONTROL_PLANE"

info "Retrieving PostgreSQL password from Key Vault..."
pg_password=$(az keyvault secret show --vault-name "$keyvault" --name "psql-admin-password" --query value -o tsv)

redis_key=""
if [[ "$use_incluster_redis" == "false" ]]; then
  info "Retrieving Redis access key from Key Vault..."
  redis_key=$(az keyvault secret show --vault-name "$keyvault" --name "redis-primary-key" --query value -o tsv)
fi

generate_mek_config() {
  local key jwk encoded
  key="$(openssl rand -base64 32 | tr -d '\n')"
  jwk="{\"k\":\"${key}\",\"kid\":\"key1\",\"kty\":\"oct\"}"
  encoded="$(echo -n "$jwk" | base64 | tr -d '\n')"
  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: $SECRET_MEK
data:
  mek.yaml: |
    currentMek: key1
    meks:
      key1: ${encoded}
EOF
}

if [[ "$skip_mek" == "false" ]]; then
  section "Configure MEK"
  mek_exists=false
  kubectl get configmap "$SECRET_MEK" -n "$NS_OSMO_CONTROL_PLANE" &>/dev/null && mek_exists=true

  if [[ "$mek_exists" == "true" && "$force_mek" == "false" ]]; then
    info "MEK ConfigMap already exists; skipping (use --force-mek to replace)"
  elif [[ -n "$mek_config_file" ]]; then
    [[ -f "$mek_config_file" ]] || fatal "MEK config file not found: $mek_config_file"
    info "Applying MEK from $mek_config_file..."
    kubectl apply -f "$mek_config_file" -n "$NS_OSMO_CONTROL_PLANE"
  else
    [[ "$mek_exists" == "true" ]] && warn "Replacing existing MEK - encrypted data will be unrecoverable!"
    info "Generating and applying MEK ConfigMap..."
    generate_mek_config | kubectl apply -n "$NS_OSMO_CONTROL_PLANE" -f -
    warn "Back up MEK for production: kubectl get configmap $SECRET_MEK -n $NS_OSMO_CONTROL_PLANE -o yaml > mek-backup.yaml"
  fi
fi

section "Configure Registry and Secrets"

if [[ "$use_acr" == "true" ]]; then
  login_acr "$acr_name"
else
  setup_ngc_repo "$ngc_token"
  create_ngc_secret "$NS_OSMO_CONTROL_PLANE" "$ngc_token"
fi

info "Creating database secret..."
kubectl create secret generic "$SECRET_POSTGRES" \
  --namespace="$NS_OSMO_CONTROL_PLANE" \
  --from-literal=db-password="$pg_password" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ "$use_incluster_redis" == "false" ]]; then
  info "Creating Redis secret..."
  kubectl create secret generic "$SECRET_REDIS" \
    --namespace="$NS_OSMO_CONTROL_PLANE" \
    --from-literal=redis-password="$redis_key" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

ingress_manifest="$SCRIPT_DIR/manifests/internal-lb-ingress.yaml"
[[ -f "$ingress_manifest" ]] && kubectl apply -f "$ingress_manifest"

service_values="$VALUES_DIR/osmo-control-plane.yaml"
router_values="$VALUES_DIR/osmo-router.yaml"
ui_values="$VALUES_DIR/osmo-ui.yaml"
service_identity_values="$VALUES_DIR/osmo-control-plane-identity.yaml"
router_identity_values="$VALUES_DIR/osmo-router-identity.yaml"

for f in "$service_values" "$router_values" "$ui_values"; do
  [[ -f "$f" ]] || fatal "Values file not found: $f"
done

section "Deploy OSMO Charts"

build_helm_args() {
  local chart="$1"
  local args=(
    --version "$chart_version"
    --namespace "$NS_OSMO_CONTROL_PLANE"
    --set-string "global.osmoImageTag=$image_version"
  )
  if [[ "$use_acr" == "true" ]]; then
    args+=(
      --set "global.osmoImageLocation=${acr_name}.azurecr.io/osmo"
      --set "global.imagePullSecret="
    )
  fi
  echo "${args[@]}"
}

info "Deploying osmo/service..."
helm_args=($(build_helm_args service))
helm_args+=(
  -f "$service_values"
  --set "services.postgres.serviceName=$pg_fqdn"
  --set "services.postgres.user=$pg_user"
)
[[ "$use_incluster_redis" == "false" ]] && helm_args+=(
  --set "services.redis.serviceName=$redis_hostname"
  --set "services.redis.port=$redis_port"
)
if [[ "$use_access_keys" == "false" ]]; then
  helm_args+=(
    -f "$service_identity_values"
    --set "serviceAccount.annotations.azure\.workload\.identity/client-id=$osmo_identity_client_id"
  )
fi

if [[ "$use_acr" == "true" ]]; then
  helm upgrade -i service "oci://${acr_name}.azurecr.io/helm/osmo" "${helm_args[@]}" --wait --timeout "$TIMEOUT_DEPLOY"
else
  helm upgrade -i service osmo/service "${helm_args[@]}" --wait --timeout "$TIMEOUT_DEPLOY"
fi

info "Deploying osmo/router..."
helm_args=($(build_helm_args router))
helm_args+=(
  -f "$router_values"
  --set "services.postgres.serviceName=$pg_fqdn"
  --set "services.postgres.user=$pg_user"
)
if [[ "$use_access_keys" == "false" ]]; then
  helm_args+=(
    -f "$router_identity_values"
    --set "serviceAccount.annotations.azure\.workload\.identity/client-id=$osmo_identity_client_id"
  )
fi

if [[ "$use_acr" == "true" ]]; then
  helm upgrade -i router "oci://${acr_name}.azurecr.io/helm/router" "${helm_args[@]}" --wait --timeout "$TIMEOUT_DEPLOY"
else
  helm upgrade -i router osmo/router "${helm_args[@]}" --wait --timeout "$TIMEOUT_DEPLOY"
fi

info "Deploying osmo/web-ui..."
helm_args=($(build_helm_args ui))
helm_args+=(-f "$ui_values")

if [[ "$use_acr" == "true" ]]; then
  helm upgrade -i ui "oci://${acr_name}.azurecr.io/helm/ui" "${helm_args[@]}" --wait --timeout "$TIMEOUT_DEPLOY"
else
  helm upgrade -i ui osmo/web-ui "${helm_args[@]}" --wait --timeout "$TIMEOUT_DEPLOY"
fi

if [[ "$skip_service_config" == "false" ]]; then
  section "Configure OSMO Service"

  kubectl wait --for=condition=available deployment/osmo-service -n "$NS_OSMO_CONTROL_PLANE" --timeout=120s

  service_url=$(detect_service_url)
  if [[ -n "$service_url" ]]; then
    service_config_template="$CONFIG_DIR/service-config-example.json"
    service_config_output="$CONFIG_DIR/out/service-config.json"

    [[ -f "$service_config_template" ]] || fatal "Service config template not found: $service_config_template"
    mkdir -p "$(dirname "$service_config_output")"

    jq --arg url "$service_url" '.service_base_url = $url' "$service_config_template" > "$service_config_output"
    info "Applying service configuration (service_base_url: $service_url)..."
    osmo config update SERVICE --file "$service_config_output" --description "Set service base URL for UI"
  else
    warn "Could not determine service base URL - OSMO UI may show errors"
  fi
fi

section "Deployment Summary"
print_kv "Namespace" "$NS_OSMO_CONTROL_PLANE"
print_kv "Chart Version" "$chart_version"
print_kv "Image Version" "$image_version"
print_kv "Registry" "$([[ $use_acr == true ]] && echo "${acr_name}.azurecr.io" || echo 'nvcr.io/nvidia/osmo')"
print_kv "PostgreSQL" "$pg_fqdn"
print_kv "Redis" "$([[ $use_incluster_redis == true ]] && echo 'in-cluster' || echo "$redis_hostname:$redis_port")"
print_kv "Auth Mode" "$([[ $use_access_keys == true ]] && echo 'access-keys' || echo 'workload-identity')"
echo
kubectl get pods -n "$NS_OSMO_CONTROL_PLANE" --no-headers | head -5
echo
helm list -n "$NS_OSMO_CONTROL_PLANE"

info "OSMO Control Plane deployment complete"
