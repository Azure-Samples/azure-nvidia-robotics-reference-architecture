#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ngc_token=""
terraform_dir="${script_dir}/../../001-iac"
values_dir="${script_dir}/values"
namespace="osmo-control-plane"
chart_version="1.0.0-2025.10.8.c18411774"

help="Usage: deploy-osmo-control-plane.sh --ngc-token TOKEN [OPTIONS]

Deploys OSMO Control Plane components to Azure Kubernetes Service.

REQUIRED:
  --ngc-token TOKEN         NGC API token for pulling OSMO images

OPTIONS:
  --terraform-dir PATH      Path to terraform directory (default: ../../001-iac)
  --values-dir PATH         Path to values directory (default: ./values)
  --namespace NAME          Target Kubernetes namespace (default: osmo-control-plane)
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
pg_secret_name=$(echo "${tf_output}" | jq -r '.postgresql_connection_info.value.secret_name // empty')
redis_hostname=$(echo "${tf_output}" | jq -r '.managed_redis_connection_info.value.hostname // empty')
redis_port=$(echo "${tf_output}" | jq -r '.managed_redis_connection_info.value.port // empty')
redis_secret_name=$(echo "${tf_output}" | jq -r '.managed_redis_connection_info.value.secret_name // empty')
keyvault_name=$(echo "${tf_output}" | jq -r '.key_vault_name.value // empty')

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

k8s_postgres_secret="db-secret"
k8s_redis_secret="redis-secret"

echo "Retrieving PostgreSQL password from Key Vault ${keyvault_name}..."
postgres_password=$(az keyvault secret show \
  --vault-name "${keyvault_name}" \
  --name "${pg_secret_name}" \
  --query value \
  --output tsv)

echo "Creating ${k8s_postgres_secret}..."
kubectl create secret generic "${k8s_postgres_secret}" \
  --namespace="${namespace}" \
  --from-literal=db-password="${postgres_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Retrieving Redis access key from Key Vault ${keyvault_name}..."
redis_key=$(az keyvault secret show \
  --vault-name "${keyvault_name}" \
  --name "${redis_secret_name}" \
  --query value \
  --output tsv)

echo "Creating ${k8s_redis_secret}..."
kubectl create secret generic "${k8s_redis_secret}" \
  --namespace="${namespace}" \
  --from-literal=redis-password="${redis_key}" \
  --dry-run=client -o yaml | kubectl apply -f -

ingress_manifest="${script_dir}/internal-lb-ingress.yaml"
if [[ -f "${ingress_manifest}" ]]; then
  echo "Applying internal load balancer ingress..."
  kubectl apply -f "${ingress_manifest}"
else
  echo "Warning: ${ingress_manifest} not found; skipping ingress apply" >&2
fi

service_values="${values_dir}/osmo-control-plane.yaml"
router_values="${values_dir}/osmo-control-plane-router.yaml"
ui_values="${values_dir}/osmo-control-plane-ui.yaml"

for values_file in "${service_values}" "${router_values}" "${ui_values}"; do
  if [[ ! -f "${values_file}" ]]; then
    echo "Error: Values file not found: ${values_file}" >&2
    exit 1
  fi
done

echo "Deploying osmo/service chart..."
helm upgrade -i service osmo/service \
  --version "${chart_version}" \
  --namespace "${namespace}" \
  -f "${service_values}" \
  --set services.postgres.serviceName="${pg_fqdn}" \
  --set services.postgres.user="${pg_user}" \
  --set services.redis.serviceName="${redis_hostname}" \
  --set services.redis.port="${redis_port}" \
  --wait \
  --timeout 10m

echo "Deploying osmo/router chart..."
helm upgrade -i router osmo/router \
  --version "${chart_version}" \
  --namespace "${namespace}" \
  -f "${router_values}" \
  --set services.postgres.serviceName="${pg_fqdn}" \
  --set services.postgres.user="${pg_user}" \
  --wait \
  --timeout 5m

echo "Deploying osmo/web-ui chart..."
helm upgrade -i ui osmo/web-ui \
  --version "${chart_version}" \
  --namespace "${namespace}" \
  -f "${ui_values}" \
  --wait \
  --timeout 5m

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
echo "Image Version:    2025.10.8.c18411774"
echo "Image Registry:   nvcr.io/nvidia/osmo"
echo "PostgreSQL Host:  ${pg_fqdn}"
echo "Redis Host:       ${redis_hostname}:${redis_port}"
echo "K8s Secrets:      nvcr-secret, ${k8s_postgres_secret}, ${k8s_redis_secret}"
echo "Values Files:     ${values_dir}"
echo
echo "Next Steps:"
echo "  kubectl get pods -n ${namespace}"
echo "  kubectl logs -n ${namespace} -l app=osmo-service --tail=50"
echo "  kubectl get svc -n ${namespace}"
echo
echo "Deployment completed successfully!"
