#!/usr/bin/env bash
# Shared functions for 002-setup deployment scripts
# Follows k3s/Docker/Homebrew conventions for user-facing scripts

# Logging functions with color support
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
fatal() { error "$@"; exit 1; }

# Check for required tools
require_tools() {
  local missing=()
  for tool in "$@"; do
    command -v "$tool" &>/dev/null || missing+=("$tool")
  done
  [[ ${#missing[@]} -eq 0 ]] || fatal "Missing required tools: ${missing[*]}"
}

# Ensure Azure CLI extension is installed
require_az_extension() {
  local ext="${1:?extension name required}"
  if ! az extension show --name "$ext" &>/dev/null; then
    info "Installing Azure CLI extension '$ext'..."
    az extension add --name "$ext" --yes || fatal "Failed to install Azure CLI extension '$ext'"
  fi
}

# Read terraform outputs from state file
read_terraform_outputs() {
  local tf_dir="${1:?terraform directory required}"
  [[ -d "$tf_dir" ]] || fatal "Terraform directory not found: $tf_dir"
  [[ -f "$tf_dir/terraform.tfstate" ]] || fatal "terraform.tfstate not found in $tf_dir"
  (cd "$tf_dir" && terraform output -json) || fatal "Unable to read terraform outputs"
}

# Extract value from terraform JSON output
tf_get() {
  local json="${1:?json required}" key="${2:?key required}" default="${3:-}"
  local val
  val=$(echo "$json" | jq -r ".$key // empty")
  if [[ -n "$val" ]]; then
    echo "$val"
  elif [[ -n "$default" ]]; then
    echo "$default"
  fi
}

# Require a terraform output value (fatal if missing)
tf_require() {
  local json="${1:?json required}" key="${2:?key required}" description="${3:-$key}"
  local val
  val=$(tf_get "$json" "$key")
  [[ -n "$val" ]] || fatal "$description not found in terraform outputs"
  echo "$val"
}

# Connect to AKS cluster
connect_aks() {
  local rg="${1:?resource group required}" name="${2:?cluster name required}"
  info "Connecting to AKS cluster $name..."
  az aks get-credentials --resource-group "$rg" --name "$name" --overwrite-existing
  verify_cluster_connectivity
}

# Verify kubectl can reach the cluster API server
verify_cluster_connectivity() {
  info "Verifying cluster connectivity..."
  if ! kubectl cluster-info &>/dev/null; then
    error "Cannot connect to Kubernetes cluster"
    echo
    echo "This typically means the AKS cluster has a private endpoint and your machine"
    echo "cannot resolve the private DNS name. The error usually looks like:"
    echo
    echo "  dial tcp: lookup aks-xxx.privatelink.<region>.azmk8s.io: no such host"
    echo
    echo "To resolve this, you need to connect via VPN:"
    echo
    echo "  1. Deploy the VPN Gateway (if not already deployed):"
    echo "     cd ../001-iac/vpn && terraform apply"
    echo
    echo "  2. Install Azure VPN Client:"
    echo "     - Windows: Microsoft Store (search 'Azure VPN Client')"
    echo "     - macOS:   App Store (search 'Azure VPN Client')"
    echo "     - Linux:   https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-vpn-client-linux"
    echo
    echo "  3. Download VPN configuration from Azure Portal:"
    echo "     - Navigate to your Virtual Network Gateway"
    echo "     - Select 'Point-to-site configuration'"
    echo "     - Click 'Download VPN client'"
    echo
    echo "  4. Import the configuration in Azure VPN Client and connect"
    echo
    echo "  5. Re-run this script after VPN connection is established"
    echo
    echo "For detailed instructions, see: ../001-iac/vpn/README.md"
    echo
    echo "Alternatively, redeploy infrastructure with:"
    echo "  should_enable_private_aks_cluster = false"
    echo "in your terraform.tfvars for a public AKS control plane."
    echo
    fatal "Cluster connectivity check failed"
  fi
  info "Cluster connectivity verified"
}

# Ensure Kubernetes namespace exists
ensure_namespace() {
  local ns="${1:?namespace required}"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

# Login to Azure Container Registry
login_acr() {
  local acr="${1:?acr name required}"
  info "Logging into ACR $acr..."
  az acr login --name "$acr"
}

# Auto-detect ACR name from terraform outputs
detect_acr_name() {
  local tf_output="${1:?terraform output required}"
  local acr_name
  acr_name=$(tf_get "$tf_output" "container_registry.value.name")
  [[ -n "$acr_name" ]] || fatal "--use-acr specified but container_registry output not found in terraform state"
  echo "$acr_name"
}

# Auto-detect OSMO identity client ID from terraform outputs
detect_osmo_identity() {
  local tf_output="${1:?terraform output required}"
  local client_id
  client_id=$(tf_get "$tf_output" "osmo_workload_identity.value.client_id")
  [[ -n "$client_id" ]] || fatal "osmo_workload_identity output not found in terraform state"
  echo "$client_id"
}

# Detect OSMO service URL from cluster
detect_service_url() {
  local url=""
  # Try internal load balancer first
  local lb_ip
  lb_ip=$(kubectl get svc azureml-ingress-nginx-internal-lb -n azureml \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "$lb_ip" ]]; then
    url="http://${lb_ip}"
  else
    # Fallback to ClusterIP
    local cluster_ip
    cluster_ip=$(kubectl get svc azureml-ingress-nginx-controller -n azureml \
      -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
    if [[ -n "$cluster_ip" && "$cluster_ip" != "None" ]]; then
      url="http://${cluster_ip}"
    fi
  fi
  echo "$url"
}

# Print section header
section() {
  echo
  echo "============================"
  echo "$*"
  echo "============================"
}

# Print key-value pair for summaries
print_kv() {
  printf '%-18s %s\n' "$1:" "$2"
}

# Apply SecretProviderClass for Azure Key Vault secrets sync
# Usage: apply_secret_provider_class <namespace> <keyvault> <client_id> <tenant_id>
apply_secret_provider_class() {
  local namespace="${1:?namespace required}"
  local keyvault="${2:?keyvault name required}"
  local client_id="${3:?client_id required}"
  local tenant_id="${4:?tenant_id required}"

  local manifest_dir
  manifest_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/manifests"

  export NAMESPACE="$namespace"
  export KEY_VAULT_NAME="$keyvault"
  export OSMO_CLIENT_ID="$client_id"
  export TENANT_ID="$tenant_id"

  info "Applying SecretProviderClass to namespace $namespace..."
  envsubst < "$manifest_dir/aks-secret-provider-class.yaml" | kubectl apply -f -
}
