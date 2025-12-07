#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ngc_token=""
terraform_dir="${script_dir}/../001-iac"
values_dir="${script_dir}/values"
namespace="osmo-control-plane"
chart_version="1.0.0"
image_version="6.0.0"
use_acr=false
acr_name=""
config_preview=false
osmo_auth_mode="workload-identity"
osmo_identity_client_id=""
mek_config_file=""
skip_mek=false
force_mek=false
mek_configmap_name="mek-config"

help="Usage: deploy-osmo-control-plane.sh [OPTIONS]

Deploys OSMO Control Plane components to Azure Kubernetes Service.
By default, images and helm charts are pulled from NVIDIA NGC.
Use --use-acr or --acr-name to pull from Azure Container Registry instead.

REQUIRED (when using NGC):
  --ngc-token TOKEN         NGC API token for pulling OSMO images

OPTIONS:
  --terraform-dir PATH      Path to terraform directory (default: ../001-iac)
  --values-dir PATH         Path to values directory (default: ./values)
  --namespace NAME          Target Kubernetes namespace (default: osmo-control-plane)
  --chart-version VERSION   Helm chart version (default: 1.0.0)
  --image-version TAG       OSMO image tag (default: 6.0.0)
  --use-acr                 Pull images/charts from ACR deployed by 001-iac (auto-detects ACR name)
  --acr-name NAME           Pull images/charts from specified ACR (implies --use-acr)
  --osmo-auth-mode MODE     OSMO storage authentication mode: key|workload-identity (default: workload-identity)
  --osmo-identity-client-id Client ID of OSMO managed identity (default: from terraform osmo_workload_identity output)
  --mek-config-file PATH    Use existing MEK config file instead of generating (for key recovery/rotation)
  --skip-mek                Skip MEK configuration entirely (use if already applied)
  --force-mek               Force MEK replacement even if one already exists (use with caution)
  --config-preview          Print configuration details and exit before deployment
  --help                    Show this help message

MEK (Master Encryption Key):
  OSMO uses MEK to encrypt sensitive data (credentials, secrets) stored in PostgreSQL.
  By default, a new MEK is generated and applied. For production, back up the MEK
  securely - if lost, encrypted database data cannot be recovered.

EXAMPLES:
  # Deploy with NGC (default)
  ./deploy-osmo-control-plane.sh --ngc-token YOUR_NGC_TOKEN

  # Deploy with ACR from terraform
  ./deploy-osmo-control-plane.sh --use-acr

  # Deploy with ACR and specific versions
  ./deploy-osmo-control-plane.sh --use-acr --chart-version 1.0.0 --image-version v2025.12.05

  # Deploy with existing MEK config (disaster recovery)
  ./deploy-osmo-control-plane.sh --use-acr --mek-config-file ./backup/mek-config.yaml

  # Deploy without MEK (already applied separately)
  ./deploy-osmo-control-plane.sh --use-acr --skip-mek
"

while [[ $# -gt 0 ]]; do
  case $1 in
  --ngc-token)
    ngc_token="$2"
    shift 2
    ;;
  --terraform-dir)
    terraform_dir="$2"
    shift 2
    ;;
  --values-dir)
    values_dir="$2"
    shift 2
    ;;
  --namespace)
    namespace="$2"
    shift 2
    ;;
  --chart-version)
    chart_version="$2"
    shift 2
    ;;
  --image-version)
    image_version="$2"
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
  --config-preview)
    config_preview=true
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
  --mek-config-file)
    mek_config_file="$2"
    shift 2
    ;;
  --skip-mek)
    skip_mek=true
    shift
    ;;
  --force-mek)
    force_mek=true
    shift
    ;;
  --help)
    echo "${help}"
    exit 0
    ;;
  *)
    echo "${help}"
    echo
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

if [[ "${use_acr}" == "false" && -z "${ngc_token}" ]]; then
  echo "Error: --ngc-token is required when not using ACR"
  echo
  echo "${help}"
  exit 1
fi

case "$osmo_auth_mode" in
key|workload-identity) ;;
*)
  echo "Error: --osmo-auth-mode must be 'key' or 'workload-identity'" >&2
  exit 1
  ;;
esac

required_tools=(terraform az kubectl helm jq base64 openssl)
missing_tools=()
for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" &>/dev/null; then
    missing_tools+=("${tool}")
  fi
done

if [[ ${#missing_tools[@]} -gt 0 ]]; then
  echo "Error: Missing required tools: ${missing_tools[*]}" >&2
  exit 1
fi

if [[ ! -d "${terraform_dir}" ]]; then
  echo "Error: Terraform directory not found: ${terraform_dir}" >&2
  exit 1
fi

if [[ ! -f "${terraform_dir}/terraform.tfstate" ]]; then
  echo "Error: terraform.tfstate not found in ${terraform_dir}" >&2
  exit 1
fi

echo "Extracting terraform outputs from ${terraform_dir}..."
if ! tf_output=$(cd "${terraform_dir}" && terraform output -json); then
  echo "Error: Unable to read terraform outputs" >&2
  exit 1
fi

aks_name=$(echo "${tf_output}" | jq -r '.aks_cluster.value.name')
resource_group=$(echo "${tf_output}" | jq -r '.resource_group.value.name')
pg_fqdn=$(echo "${tf_output}" | jq -r '.postgresql_connection_info.value.fqdn // empty')
pg_user=$(echo "${tf_output}" | jq -r '.postgresql_connection_info.value.admin_username // empty')
redis_hostname=$(echo "${tf_output}" | jq -r '.managed_redis_connection_info.value.hostname // empty')
redis_port=$(echo "${tf_output}" | jq -r '.managed_redis_connection_info.value.port // empty')
keyvault_name=$(echo "${tf_output}" | jq -r '.key_vault_name.value // empty')

if [[ "${use_acr}" == "true" && -z "${acr_name}" ]]; then
  acr_name=$(echo "${tf_output}" | jq -r '.container_registry.value.name // empty')
  if [[ -z "${acr_name}" ]]; then
    echo "Error: --use-acr specified but container_registry output not found in terraform state" >&2
    exit 1
  fi
fi

if [[ "$osmo_auth_mode" == "workload-identity" && -z "$osmo_identity_client_id" ]]; then
  osmo_identity_client_id=$(echo "${tf_output}" | jq -r '.osmo_workload_identity.value.client_id // empty')
  if [[ -z "$osmo_identity_client_id" ]]; then
    echo "Error: --osmo-identity-client-id not provided and osmo_workload_identity output not found in terraform state" >&2
    exit 1
  fi
fi

postgres_server_name=${pg_fqdn%%.*}
redis_cluster=${redis_hostname%%.*}
postgres_secret_name="db-secret"
redis_secret_name="redis-secret"
ingress_manifest="${script_dir}/manifests/internal-lb-ingress.yaml"
service_values="${values_dir}/osmo-control-plane.yaml"
router_values="${values_dir}/osmo-router.yaml"
ui_values="${values_dir}/osmo-ui.yaml"
service_identity_values="${values_dir}/osmo-control-plane-identity.yaml"
router_identity_values="${values_dir}/osmo-router-identity.yaml"

if [[ -z "${keyvault_name}" ]]; then
  echo "Error: key_vault_name output not found in terraform state" >&2
  exit 1
fi

if [[ -z "${pg_fqdn}" ]] || [[ -z "${redis_hostname}" ]]; then
  echo "Error: PostgreSQL or Redis not deployed. Ensure should_deploy_postgresql and should_deploy_redis are true." >&2
  exit 1
fi

echo "  AKS Cluster: ${aks_name}"
echo "  Resource Group: ${resource_group}"
echo "  PostgreSQL: ${pg_fqdn}"
echo "  Redis: ${redis_hostname}:${redis_port}"
echo "  Key Vault: ${keyvault_name}"

echo "Retrieving PostgreSQL password from Key Vault ${keyvault_name}..."
postgres_password=$(az keyvault secret show \
  --vault-name "${keyvault_name}" \
  --name "psql-admin-password" \
  --query value \
  --output tsv)

echo "Retrieving Redis access key from Key Vault ${keyvault_name}..."
redis_key=$(az keyvault secret show \
  --vault-name "${keyvault_name}" \
  --name "redis-primary-key" \
  --query value \
  --output tsv)

if [[ "${config_preview}" == "true" ]]; then
  echo
  echo "Configuration preview"
  echo "---------------------"
  printf 'script_dir=%s\n' "${script_dir}"
  printf 'terraform_dir=%s\n' "${terraform_dir}"
  printf 'values_dir=%s\n' "${values_dir}"
  printf 'namespace=%s\n' "${namespace}"
  printf 'chart_version=%s\n' "${chart_version}"
  printf 'image_version=%s\n' "${image_version}"
  printf 'use_acr=%s\n' "${use_acr}"
  printf 'acr_name=%s\n' "${acr_name}"
  printf 'ngc_token=%s\n' "${ngc_token:+(set)}"
  printf 'aks_name=%s\n' "${aks_name}"
  printf 'resource_group=%s\n' "${resource_group}"
  printf 'postgres_fqdn=%s\n' "${pg_fqdn}"
  printf 'postgres_user=%s\n' "${pg_user}"
  printf 'postgres_server_name=%s\n' "${postgres_server_name}"
  printf 'postgres_password=%s\n' "${postgres_password}"
  printf 'redis_hostname=%s\n' "${redis_hostname}"
  printf 'redis_port=%s\n' "${redis_port}"
  printf 'redis_cluster=%s\n' "${redis_cluster}"
  printf 'redis_key=%s\n' "${redis_key}"
  printf 'keyvault_name=%s\n' "${keyvault_name}"
  printf 'postgres_secret_name=%s\n' "${postgres_secret_name}"
  printf 'redis_secret_name=%s\n' "${redis_secret_name}"
  printf 'service_values=%s\n' "${service_values}"
  printf 'router_values=%s\n' "${router_values}"
  printf 'ui_values=%s\n' "${ui_values}"
  printf 'ingress_manifest=%s\n' "${ingress_manifest}"
  printf 'osmo_auth_mode=%s\n' "${osmo_auth_mode}"
  printf 'osmo_identity_client_id=%s\n' "${osmo_identity_client_id}"
  printf 'skip_mek=%s\n' "${skip_mek}"
  printf 'force_mek=%s\n' "${force_mek}"
  printf 'mek_config_file=%s\n' "${mek_config_file}"
  printf 'mek_configmap_name=%s\n' "${mek_configmap_name}"
  exit 0
fi

echo "Acquiring AKS credentials..."
az aks get-credentials \
  --resource-group "${resource_group}" \
  --name "${aks_name}" \
  --overwrite-existing
kubectl cluster-info &>/dev/null

echo "Ensuring namespace ${namespace} exists..."
kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -

generate_mek_config() {
  local random_key jwk_json encoded_jwk
  random_key="$(openssl rand -base64 32 | tr -d '\n')"
  jwk_json="{\"k\":\"${random_key}\",\"kid\":\"key1\",\"kty\":\"oct\"}"
  encoded_jwk="$(echo -n "${jwk_json}" | base64 | tr -d '\n')"

  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${mek_configmap_name}
data:
  mek.yaml: |
    currentMek: key1
    meks:
      key1: ${encoded_jwk}
EOF
}

if [[ "${skip_mek}" == "false" ]]; then
  mek_exists=false
  if kubectl get configmap "${mek_configmap_name}" -n "${namespace}" &>/dev/null; then
    mek_exists=true
  fi

  if [[ "${mek_exists}" == "true" && "${force_mek}" == "false" ]]; then
    echo "MEK ConfigMap '${mek_configmap_name}' already exists in namespace ${namespace}; skipping."
    echo "  Use --force-mek to replace the existing MEK (data loss warning)."
  elif [[ -n "${mek_config_file}" ]]; then
    if [[ ! -f "${mek_config_file}" ]]; then
      echo "Error: MEK config file not found: ${mek_config_file}" >&2
      exit 1
    fi
    if [[ "${mek_exists}" == "true" ]]; then
      echo "Warning: Replacing existing MEK ConfigMap with ${mek_config_file}..." >&2
    else
      echo "Applying MEK ConfigMap from ${mek_config_file}..."
    fi
    kubectl apply -f "${mek_config_file}" -n "${namespace}"
  else
    if [[ "${mek_exists}" == "true" ]]; then
      echo "Warning: Replacing existing MEK ConfigMap with newly generated key..." >&2
      echo "  Existing encrypted data will become unrecoverable!" >&2
    fi
    echo "Generating and applying MEK ConfigMap..."
    generate_mek_config | kubectl apply -n "${namespace}" -f -
    echo "Warning: MEK generated dynamically. Back up the ConfigMap for production use:" >&2
    echo "  kubectl get configmap ${mek_configmap_name} -n ${namespace} -o yaml > mek-backup.yaml" >&2
  fi
else
  echo "Skipping MEK configuration (--skip-mek specified)."
fi

if [[ "${use_acr}" == "true" ]]; then
  echo "Logging into Azure Container Registry ${acr_name}..."
  az acr login --name "${acr_name}"
else
  echo "Adding NVIDIA NGC Helm repository..."
  # shellcheck disable=SC2016
  helm repo add osmo https://helm.ngc.nvidia.com/nvidia/osmo \
    --username='$oauthtoken' \
    --password="${ngc_token}" 2>/dev/null || true
  helm repo update >/dev/null

  echo "Creating nvcr-secret image pull secret..."
  # shellcheck disable=SC2016
  kubectl create secret docker-registry nvcr-secret \
    --namespace="${namespace}" \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password="${ngc_token}" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

echo "Creating ${postgres_secret_name}..."
kubectl create secret generic "${postgres_secret_name}" \
  --namespace="${namespace}" \
  --from-literal=db-password="${postgres_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating ${redis_secret_name}..."
kubectl create secret generic "${redis_secret_name}" \
  --namespace="${namespace}" \
  --from-literal=redis-password="${redis_key}" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -f "${ingress_manifest}" ]]; then
  echo "Applying internal load balancer ingress..."
  kubectl apply -f "${ingress_manifest}"
else
  echo "Warning: ${ingress_manifest} not found; skipping ingress apply" >&2
fi

for values_file in "${service_values}" "${router_values}" "${ui_values}"; do
  if [[ ! -f "${values_file}" ]]; then
    echo "Error: Values file not found: ${values_file}" >&2
    exit 1
  fi
done

echo "Deploying osmo/service chart..."
set -x
helm_service_args=(
  --version "${chart_version}"
  --namespace "${namespace}"
  -f "${service_values}"
  --set "services.postgres.serviceName=${pg_fqdn}"
  --set "services.postgres.user=${pg_user}"
  --set "services.redis.serviceName=${redis_hostname}"
  --set "services.redis.port=${redis_port}"
  --set-string "global.osmoImageTag=${image_version}"
)

if [[ "${use_acr}" == "true" ]]; then
  helm_service_args+=(
    --set "global.osmoImageLocation=${acr_name}.azurecr.io/osmo"
    --set "global.imagePullSecret="
  )
fi

if [[ "$osmo_auth_mode" == "workload-identity" ]]; then
  helm_service_args+=(
    -f "${service_identity_values}"
    --set "serviceAccount.annotations.azure\.workload\.identity/client-id=${osmo_identity_client_id}"
  )
fi

if [[ "${use_acr}" == "true" ]]; then
  helm upgrade -i service "oci://${acr_name}.azurecr.io/helm/osmo" "${helm_service_args[@]}" --wait --timeout 10m
else
  helm upgrade -i service osmo/service "${helm_service_args[@]}" --wait --timeout 10m
fi
set +x

echo "Deploying osmo/router chart..."
set -x
helm_router_args=(
  --version "${chart_version}"
  --namespace "${namespace}"
  -f "${router_values}"
  --set "services.postgres.serviceName=${pg_fqdn}"
  --set "services.postgres.user=${pg_user}"
  --set-string "global.osmoImageTag=${image_version}"
)

if [[ "${use_acr}" == "true" ]]; then
  helm_router_args+=(
    --set "global.osmoImageLocation=${acr_name}.azurecr.io/osmo"
    --set "global.imagePullSecret="
  )
fi

if [[ "$osmo_auth_mode" == "workload-identity" ]]; then
  helm_router_args+=(
    -f "${router_identity_values}"
    --set "serviceAccount.annotations.azure\.workload\.identity/client-id=${osmo_identity_client_id}"
  )
fi

if [[ "${use_acr}" == "true" ]]; then
  helm upgrade -i router "oci://${acr_name}.azurecr.io/helm/router" "${helm_router_args[@]}" --wait --timeout 5m
else
  helm upgrade -i router osmo/router "${helm_router_args[@]}" --wait --timeout 5m
fi
set +x

echo "Deploying osmo/web-ui chart..."
set -x
helm_ui_args=(
  --version "${chart_version}"
  --namespace "${namespace}"
  -f "${ui_values}"
  --set-string "global.osmoImageTag=${image_version}"
)

if [[ "${use_acr}" == "true" ]]; then
  helm_ui_args+=(
    --set "global.osmoImageLocation=${acr_name}.azurecr.io/osmo"
    --set "global.imagePullSecret="
  )
  helm upgrade -i ui "oci://${acr_name}.azurecr.io/helm/ui" "${helm_ui_args[@]}" --wait --timeout 5m
else
  helm upgrade -i ui osmo/web-ui "${helm_ui_args[@]}" --wait --timeout 5m
fi
set +x

echo
echo "============================"
echo "Deployment Verification"
echo "============================"

kubectl get pods -n "${namespace}" -o wide
kubectl get svc -n "${namespace}"
helm list -n "${namespace}"
if kubectl get ingress -n "${namespace}" >/dev/null 2>&1; then
  kubectl get ingress -n "${namespace}"
else
  echo "No ingress resources found in namespace ${namespace}"
fi

echo
echo "============================"
echo "OSMO Control Plane Deployment Summary"
echo "============================"
echo "Namespace:        ${namespace}"
echo "Helm Charts:      service, router, ui"
echo "Chart Version:    ${chart_version}"
echo "Image Version:    ${image_version}"
if [[ "${use_acr}" == "true" ]]; then
  echo "Image Registry:   ${acr_name}.azurecr.io/osmo"
  echo "Chart Source:     oci://${acr_name}.azurecr.io/helm/{osmo,router,ui}"
else
  echo "Image Registry:   nvcr.io/nvidia/osmo"
  echo "Chart Source:     osmo (NGC)"
fi
echo "PostgreSQL Host:  ${pg_fqdn}"
echo "Redis Host:       ${redis_hostname}:${redis_port}"
if [[ "${use_acr}" == "true" ]]; then
  echo "K8s Secrets:      ${postgres_secret_name}, ${redis_secret_name}"
else
  echo "K8s Secrets:      nvcr-secret, ${postgres_secret_name}, ${redis_secret_name}"
fi
echo "Values Files:     ${values_dir}"
echo "MEK ConfigMap:    ${mek_configmap_name}"
echo "Auth Mode:        ${osmo_auth_mode}"
if [[ "$osmo_auth_mode" == "workload-identity" ]]; then
  echo "Identity Client:  ${osmo_identity_client_id}"
fi
echo
echo "Next Steps:"
echo "  kubectl get pods -n ${namespace}"
echo "  kubectl logs -n ${namespace} -l app=osmo-service --tail=50"
echo "  kubectl get svc -n ${namespace}"
echo
echo "Deployment completed successfully!"
