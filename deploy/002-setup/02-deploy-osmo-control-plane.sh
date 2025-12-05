#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ngc_token=""
terraform_dir="${script_dir}/../001-iac"
values_dir="${script_dir}/values"
namespace="osmo-control-plane"
chart_version="1.0.0"
image_version="6.0.0"
config_preview=false

help="Usage: deploy-osmo-control-plane.sh --ngc-token TOKEN [OPTIONS]

Deploys OSMO Control Plane components to Azure Kubernetes Service.

REQUIRED:
  --ngc-token TOKEN         NGC API token for pulling OSMO images

OPTIONS:
  --terraform-dir PATH      Path to terraform directory (default: ../001-iac)
  --values-dir PATH         Path to values directory (default: ./values)
  --namespace NAME          Target Kubernetes namespace (default: osmo-control-plane)
  --config-preview          Print configuration details and exit before deployment
  --help                    Show this help message

EXAMPLES:
  # Deploy with NGC token
  ./deploy-osmo-control-plane.sh --ngc-token YOUR_NGC_TOKEN

  # Deploy with custom terraform directory
  ./deploy-osmo-control-plane.sh --ngc-token TOKEN --terraform-dir /path/to/terraform
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
  --config-preview)
    config_preview=true
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

if [[ -z "${ngc_token}" ]]; then
  echo "Error: --ngc-token is required"
  echo
  echo "${help}"
  exit 1
fi

required_tools=(terraform az kubectl helm jq base64)
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
postgres_server_name=${pg_fqdn%%.*}
redis_cluster=${redis_hostname%%.*}
postgres_secret_name="db-secret"
redis_secret_name="redis-secret"
ingress_manifest="${script_dir}/manifests/internal-lb-ingress.yaml"
service_values="${values_dir}/osmo-control-plane.yaml"
router_values="${values_dir}/osmo-control-plane-router.yaml"
ui_values="${values_dir}/osmo-control-plane-ui.yaml"

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
  --name "${postgres_server_name}-admin-password" \
  --query value \
  --output tsv)

echo "Retrieving Redis access key for ${redis_cluster}..."
redis_key=$(az redisenterprise database list-keys \
  --cluster-name "${redis_cluster}" \
  --resource-group "${resource_group}" \
  --query primaryKey \
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
  printf 'ngc_token=%s\n' "${ngc_token}"
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
helm upgrade -i service osmo/service \
  --version "${chart_version}" \
  --namespace "${namespace}" \
  -f "${service_values}" \
  --set services.postgres.serviceName="${pg_fqdn}" \
  --set services.postgres.user="${pg_user}" \
  --set services.redis.serviceName="${redis_hostname}" \
  --set services.redis.port="${redis_port}" \
  --set-string global.osmoImageTag="${image_version}" \
  --wait \
  --timeout 10m
set +x

echo "Deploying osmo/router chart..."
set -x
helm upgrade -i router osmo/router \
  --version "${chart_version}" \
  --namespace "${namespace}" \
  -f "${router_values}" \
  --set services.postgres.serviceName="${pg_fqdn}" \
  --set services.postgres.user="${pg_user}" \
  --set-string global.osmoImageTag="${image_version}" \
  --wait \
  --timeout 5m
set +x

echo "Deploying osmo/web-ui chart..."
set -x
helm upgrade -i ui osmo/web-ui \
  --version "${chart_version}" \
  --namespace "${namespace}" \
  -f "${ui_values}" \
  --set-string global.osmoImageTag="${image_version}" \
  --wait \
  --timeout 5m
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
echo "Image Registry:   nvcr.io/nvidia/osmo"
echo "PostgreSQL Host:  ${pg_fqdn}"
echo "Redis Host:       ${redis_hostname}:${redis_port}"
echo "K8s Secrets:      nvcr-secret, ${postgres_secret_name}, ${redis_secret_name}"
echo "Values Files:     ${values_dir}"
echo
echo "Next Steps:"
echo "  kubectl get pods -n ${namespace}"
echo "  kubectl logs -n ${namespace} -l app=osmo-service --tail=50"
echo "  kubectl get svc -n ${namespace}"
echo
echo "Deployment completed successfully!"
