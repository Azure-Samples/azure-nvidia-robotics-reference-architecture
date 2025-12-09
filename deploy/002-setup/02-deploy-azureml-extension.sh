#!/usr/bin/env bash
# Install AzureML extension on AKS cluster and attach as compute target
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.conf
source "$SCRIPT_DIR/defaults.conf"

CONFIG_DIR="$SCRIPT_DIR/config"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install Azure Machine Learning extension on AKS cluster, create GPU instance types,
and attach the cluster as a compute target.

OPTIONS:
    -h, --help                Show this help message
    -t, --tf-dir DIR          Terraform directory (default: $DEFAULT_TF_DIR)
    --compute-name NAME       Compute target name (default: k8s-<suffix>)
    --fast-prod               Set cluster purpose to FastProd with HA inference router
    --skip-attach             Skip attaching cluster as compute target
    --skip-instance-types     Skip creating GPU instance types

EXAMPLES:
    $(basename "$0")
    $(basename "$0") --fast-prod
EOF
}

tf_dir="$SCRIPT_DIR/$DEFAULT_TF_DIR"
compute_name=""
cluster_purpose="DevTest"
inference_ha="false"
allow_insecure="true"
install_volcano="true"
install_prom_op="false"
skip_attach="false"
skip_instance_types="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)             show_help; exit 0 ;;
    -t|--tf-dir)           tf_dir="$2"; shift 2 ;;
    --compute-name)        compute_name="$2"; shift 2 ;;
    --fast-prod)           cluster_purpose="FastProd"; inference_ha="true"; allow_insecure="false"; shift ;;
    --skip-attach)         skip_attach="true"; shift ;;
    --skip-instance-types) skip_instance_types="true"; shift ;;
    *)                     fatal "Unknown option: $1" ;;
  esac
done

require_tools az terraform kubectl jq envsubst

tf_output=$(read_terraform_outputs "$tf_dir")
cluster=$(tf_require "$tf_output" "aks_cluster.value.name" "AKS cluster name")
cluster_id=$(tf_require "$tf_output" "aks_cluster.value.id" "AKS cluster ID")
rg=$(tf_require "$tf_output" "resource_group.value.name" "Resource group")
ml_workspace=$(tf_get "$tf_output" "azureml_workspace.value.name")
ml_identity_id=$(tf_get "$tf_output" "ml_workload_identity.value.id")

extension_name="azureml-$cluster"
[[ -z "$compute_name" ]] && compute_name="k8s-${cluster#aks-}"

connect_aks "$rg" "$cluster"

section "Install AzureML Extension"

config_template="$CONFIG_DIR/azureml-aks-config.template.json"
config_output="$CONFIG_DIR/out/azureml-aks-config.json"
mkdir -p "$(dirname "$config_output")"

export INFERENCE_ROUTER_HA="$inference_ha"
export ALLOW_INSECURE_CONNECTIONS="$allow_insecure"
export CLUSTER_PURPOSE="$cluster_purpose"
export INSTALL_VOLCANO="$install_volcano"
export INSTALL_PROM_OP="$install_prom_op"

envsubst < "$config_template" > "$config_output"

if az k8s-extension show --name "$extension_name" --cluster-type managedClusters \
    --cluster-name "$cluster" --resource-group "$rg" &>/dev/null; then
  info "Extension '$extension_name' already installed"
else
  info "Installing AzureML extension..."
  az k8s-extension create \
    --name "$extension_name" \
    --extension-type Microsoft.AzureML.Kubernetes \
    --cluster-type managedClusters \
    --cluster-name "$cluster" \
    --resource-group "$rg" \
    --scope cluster \
    --release-namespace "$NS_AZUREML" \
    --release-train stable \
    --config-file "$config_output"
  sleep 30
fi

if [[ "$skip_instance_types" != "true" ]]; then
  section "Create GPU Instance Types"

  info "Waiting for InstanceType CRD..."
  for i in {1..30}; do
    kubectl get crd instancetypes.amlarc.azureml.com &>/dev/null && break
    [[ $i -eq 30 ]] && { warn "InstanceType CRD not available"; skip_instance_types="true"; break; }
    sleep 10
  done

  if [[ "$skip_instance_types" != "true" ]]; then
    kubectl apply -f "$MANIFESTS_DIR/azureml-instance-types.yaml"
    info "Instance types applied"
  fi
fi

if [[ "$skip_attach" != "true" ]] && [[ -n "$ml_identity_id" ]]; then
  section "Create Federated Identity Credentials"

  ml_identity_name="${ml_identity_id##*/}"
  oidc_issuer=$(az aks show --resource-group "$rg" --name "$cluster" \
    --query "oidcIssuerProfile.issuerUrl" -o tsv)
  [[ -z "$oidc_issuer" ]] && fatal "OIDC issuer not enabled on cluster"

  for sa in default training; do
    fic_name="aml-${sa}-fic"
    if az identity federated-credential show --identity-name "$ml_identity_name" \
        --resource-group "$rg" --name "$fic_name" &>/dev/null; then
      info "Federated credential '$fic_name' exists"
    else
      info "Creating federated credential for azureml:$sa..."
      az identity federated-credential create \
        --identity-name "$ml_identity_name" \
        --resource-group "$rg" \
        --name "$fic_name" \
        --issuer "$oidc_issuer" \
        --subject "system:serviceaccount:azureml:$sa" \
        --audiences "api://AzureADTokenExchange"
    fi
  done
fi

if [[ "$skip_attach" != "true" ]]; then
  [[ -z "$ml_workspace" ]] && fatal "ML workspace not found in terraform outputs"

  section "Attach Compute Target"

  if az ml compute show --name "$compute_name" --resource-group "$rg" \
      --workspace-name "$ml_workspace" &>/dev/null; then
    info "Compute '$compute_name' already attached"
  else
    info "Attaching AKS cluster as compute target..."
    attach_args=(
      --resource-group "$rg"
      --workspace-name "$ml_workspace"
      --type Kubernetes
      --name "$compute_name"
      --resource-id "$cluster_id"
      --namespace "$NS_AZUREML"
    )
    if [[ -n "$ml_identity_id" ]]; then
      attach_args+=(--identity-type UserAssigned --user-assigned-identities "$ml_identity_id")
    else
      attach_args+=(--identity-type SystemAssigned)
    fi
    az ml compute attach "${attach_args[@]}"
  fi
fi

section "Summary"
print_kv "Cluster" "$cluster"
print_kv "Extension" "$extension_name"
print_kv "Compute" "$compute_name"
print_kv "Purpose" "$cluster_purpose"
echo
info "AzureML extension deployment complete"
