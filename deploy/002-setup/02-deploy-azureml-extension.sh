#!/usr/bin/env bash
# Install AzureML extension on AKS cluster and attach as compute target
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.conf
source "$SCRIPT_DIR/defaults.conf"

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install Azure Machine Learning extension on AKS cluster, create GPU instance types,
and attach the cluster as a compute target.

OPTIONS:
    -h, --help                Show this help message
    -t, --tf-dir DIR          Terraform directory (default: $DEFAULT_TF_DIR)
    --extension-name NAME     Extension name (default: azureml-<cluster>)
    --compute-name NAME       Compute target name (default: k8s-<suffix>)
    --cluster-purpose PURPOSE DevTest or FastProd (default: DevTest)
    --internal-load-balancer  Use internal LoadBalancer for inference router
    --inference-router-ha     Enable inference router high availability
    --secure-connections      Require secure connections
    --skip-volcano            Skip Volcano scheduler installation
    --enable-prom-op          Enable Prometheus Operator (conflicts with Azure Monitor)
    --skip-gpu-tolerations    Skip GPU spot node tolerations
    --skip-compute-attach     Skip attaching cluster as compute target
    --skip-instance-types     Skip creating GPU instance types

EXAMPLES:
    $(basename "$0")
    $(basename "$0") --cluster-purpose FastProd --inference-router-ha
EOF
}

tf_dir="$SCRIPT_DIR/$DEFAULT_TF_DIR"
extension_name=""
compute_name=""
cluster_purpose="DevTest"
internal_lb="azure"
inference_ha="false"
allow_insecure="true"
install_volcano="true"
install_prom_op="false"
gpu_tolerations="true"
skip_attach="false"
skip_instance_types="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)                show_help; exit 0 ;;
    -t|--tf-dir)              tf_dir="$2"; shift 2 ;;
    --extension-name)         extension_name="$2"; shift 2 ;;
    --compute-name)           compute_name="$2"; shift 2 ;;
    --cluster-purpose)        cluster_purpose="$2"; shift 2 ;;
    --internal-load-balancer) internal_lb="azure"; shift ;;
    --inference-router-ha)    inference_ha="true"; shift ;;
    --secure-connections)     allow_insecure="false"; shift ;;
    --skip-volcano)           install_volcano="false"; shift ;;
    --enable-prom-op)         install_prom_op="true"; shift ;;
    --skip-gpu-tolerations)   gpu_tolerations="false"; shift ;;
    --skip-compute-attach)    skip_attach="true"; shift ;;
    --skip-instance-types)    skip_instance_types="true"; shift ;;
    *)                        fatal "Unknown option: $1" ;;
  esac
done

require_tools az terraform kubectl jq

info "Reading terraform outputs from $tf_dir..."
tf_output=$(read_terraform_outputs "$tf_dir")
cluster=$(tf_require "$tf_output" "aks_cluster.value.name" "AKS cluster name")
cluster_id=$(tf_require "$tf_output" "aks_cluster.value.id" "AKS cluster ID")
rg=$(tf_require "$tf_output" "resource_group.value.name" "Resource group")
ml_workspace=$(tf_get "$tf_output" "azureml_workspace.value.name")
ml_identity_id=$(tf_get "$tf_output" "ml_workload_identity.value.id")

[[ -z "$extension_name" ]] && extension_name="azureml-$cluster"
if [[ -z "$compute_name" ]]; then
  suffix="${cluster#aks-}"
  compute_name="k8s-${suffix:0:12}"
fi

connect_aks "$rg" "$cluster"

section "Step 1: Install AzureML Extension"

config_args=(
  "enableTraining=true"
  "enableInference=true"
  "inferenceRouterServiceType=LoadBalancer"
  "inferenceRouterHA=$inference_ha"
  "allowInsecureConnections=$allow_insecure"
  "clusterPurpose=$cluster_purpose"
  "installNvidiaDevicePlugin=false"
  "installDcgmExporter=false"
  "installVolcano=$install_volcano"
  "installPromOp=$install_prom_op"
  "servicebus.enabled=false"
  "relayserver.enabled=false"
)

[[ -n "$internal_lb" ]] && config_args+=("internalLoadBalancerProvider=$internal_lb")

if [[ "$gpu_tolerations" == "true" ]]; then
  config_args+=(
    "workLoadToleration[0].key=nvidia.com/gpu"
    "workLoadToleration[0].operator=Exists"
    "workLoadToleration[0].effect=NoSchedule"
    "workLoadToleration[1].key=kubernetes.azure.com/scalesetpriority"
    "workLoadToleration[1].operator=Equal"
    "workLoadToleration[1].value=spot"
    "workLoadToleration[1].effect=NoSchedule"
  )
fi

config_string="${config_args[*]}"

if az k8s-extension show --name "$extension_name" --cluster-type managedClusters \
    --cluster-name "$cluster" --resource-group "$rg" &>/dev/null; then
  info "AzureML extension '$extension_name' already exists"
else
  info "Installing AzureML extension..."
  # shellcheck disable=SC2086
  az k8s-extension create \
    --name "$extension_name" \
    --extension-type Microsoft.AzureML.Kubernetes \
    --cluster-type managedClusters \
    --cluster-name "$cluster" \
    --resource-group "$rg" \
    --scope cluster \
    --release-namespace "$NS_AZUREML" \
    --release-train stable \
    --config $config_string
  sleep 30
fi

if [[ "$skip_instance_types" != "true" ]]; then
  section "Step 2: Create GPU Instance Types"

  info "Waiting for InstanceType CRD..."
  for i in {1..30}; do
    kubectl get crd instancetypes.amlarc.azureml.com &>/dev/null && break
    [[ $i -eq 30 ]] && { warn "InstanceType CRD not available"; skip_instance_types="true"; break; }
    sleep 10
  done

  if [[ "$skip_instance_types" != "true" ]]; then
    kubectl apply -f - <<'EOF'
apiVersion: amlarc.azureml.com/v1alpha1
kind: InstanceTypeList
items:
  - metadata:
      name: defaultinstancetype
    spec:
      resources:
        requests: { cpu: "1", memory: "4Gi" }
        limits: { cpu: "2", memory: "8Gi" }
  - metadata:
      name: gpuspot
    spec:
      nodeSelector:
        accelerator: nvidia
        kubernetes.azure.com/scalesetpriority: spot
      resources:
        requests: { cpu: "4", memory: "16Gi" }
        limits: { cpu: "8", memory: "32Gi", nvidia.com/gpu: 1 }
EOF
    info "Instance types created"
  fi
else
  info "Skipping instance types (--skip-instance-types)"
fi

if [[ "$skip_attach" != "true" ]] && [[ -n "$ml_identity_id" ]]; then
  section "Step 3: Create Federated Identity Credentials"

  ml_identity_name="${ml_identity_id##*/}"
  oidc_issuer=$(az aks show --resource-group "$rg" --name "$cluster" --query "oidcIssuerProfile.issuerUrl" -o tsv)
  [[ -z "$oidc_issuer" ]] && fatal "OIDC issuer not enabled on cluster"

  for sa in default training; do
    fic_name="aml-${sa}-fic"
    if ! az identity federated-credential show --identity-name "$ml_identity_name" \
        --resource-group "$rg" --name "$fic_name" &>/dev/null; then
      info "Creating federated credential for azureml:$sa..."
      az identity federated-credential create \
        --identity-name "$ml_identity_name" \
        --resource-group "$rg" \
        --name "$fic_name" \
        --issuer "$oidc_issuer" \
        --subject "system:serviceaccount:azureml:$sa" \
        --audiences "api://AzureADTokenExchange"
    else
      info "Federated credential '$fic_name' already exists"
    fi
  done
fi

if [[ "$skip_attach" != "true" ]]; then
  [[ -z "$ml_workspace" ]] && fatal "ML workspace not found in terraform outputs"

  section "Step 4: Attach Compute Target"

  if az ml compute show --name "$compute_name" --resource-group "$rg" \
      --workspace-name "$ml_workspace" &>/dev/null; then
    info "Compute target '$compute_name' already exists"
  else
    info "Attaching AKS cluster as compute target..."
    if [[ -n "$ml_identity_id" ]]; then
      az ml compute attach \
        --resource-group "$rg" \
        --workspace-name "$ml_workspace" \
        --type Kubernetes \
        --name "$compute_name" \
        --resource-id "$cluster_id" \
        --identity-type UserAssigned \
        --user-assigned-identities "$ml_identity_id" \
        --namespace "$NS_AZUREML"
    else
      az ml compute attach \
        --resource-group "$rg" \
        --workspace-name "$ml_workspace" \
        --type Kubernetes \
        --name "$compute_name" \
        --resource-id "$cluster_id" \
        --identity-type SystemAssigned \
        --namespace "$NS_AZUREML"
    fi
    info "Compute target attached"
  fi
else
  info "Skipping compute attach (--skip-compute-attach)"
fi

section "Deployment Summary"
print_kv "Cluster" "$cluster"
print_kv "Resource Group" "$rg"
print_kv "Extension" "$extension_name"
print_kv "Compute Target" "$compute_name"
print_kv "Cluster Purpose" "$cluster_purpose"
echo
kubectl get pods -n "$NS_AZUREML" --no-headers 2>/dev/null | head -5 || true
echo
info "AzureML extension deployment complete"
