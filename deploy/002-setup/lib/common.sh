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
  kubectl cluster-info &>/dev/null || fatal "Failed to connect to cluster"
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

# Setup NGC Helm repository
setup_ngc_repo() {
  local token="${1:?ngc token required}" repo_name="${2:-osmo}"
  info "Configuring NGC Helm repository..."
  # shellcheck disable=SC2016
  helm repo add "$repo_name" "https://helm.ngc.nvidia.com/nvidia/$repo_name" \
    --username='$oauthtoken' --password="$token" 2>/dev/null || true
  helm repo update >/dev/null
}

# Create NGC image pull secret
create_ngc_secret() {
  local ns="${1:?namespace required}" token="${2:?token required}" name="${3:-nvcr-secret}"
  info "Creating NGC pull secret $name in namespace $ns..."
  # shellcheck disable=SC2016
  kubectl create secret docker-registry "$name" \
    --namespace="$ns" \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password="$token" \
    --dry-run=client -o yaml | kubectl apply -f -
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
