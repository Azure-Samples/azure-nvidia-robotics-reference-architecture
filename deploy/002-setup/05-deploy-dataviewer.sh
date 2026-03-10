#!/usr/bin/env bash
# Build and deploy the dataviewer application to Azure Container Apps
set -o errexit -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.conf
source "$SCRIPT_DIR/defaults.conf"

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build and deploy the dataviewer application to Azure Container Apps.

OPTIONS:
    -h, --help               Show this help message
    -t, --tf-dir DIR         Terraform directory (default: $DEFAULT_TF_DIR)
    --tag TAG                Image tag (default: $DATAVIEWER_IMAGE_TAG)
    --skip-build             Skip container image builds (use existing images)
    --skip-update            Skip container app update (build images only)
    --skip-backend           Skip backend build/deploy
    --skip-frontend          Skip frontend build/deploy
    --config-preview         Print configuration and exit

EXAMPLES:
    $(basename "$0")
    $(basename "$0") --tag v0.1.0
    $(basename "$0") --skip-build
    $(basename "$0") --skip-frontend --tag sha-abc1234
EOF
}

# Defaults
tf_dir="$SCRIPT_DIR/$DEFAULT_TF_DIR"
image_tag="$DATAVIEWER_IMAGE_TAG"
skip_build=false
skip_update=false
skip_backend=false
skip_frontend=false
config_preview=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)           show_help; exit 0 ;;
    -t|--tf-dir)         tf_dir="$2"; shift 2 ;;
    --tag)               image_tag="$2"; shift 2 ;;
    --skip-build)        skip_build=true; shift ;;
    --skip-update)       skip_update=true; shift ;;
    --skip-backend)      skip_backend=true; shift ;;
    --skip-frontend)     skip_frontend=true; shift ;;
    --config-preview)    config_preview=true; shift ;;
    *)                   fatal "Unknown option: $1" ;;
  esac
done

require_tools az terraform jq

#------------------------------------------------------------------------------
# Gather Configuration
#------------------------------------------------------------------------------

info "Reading terraform outputs from $tf_dir..."
tf_output=$(read_terraform_outputs "$tf_dir")

rg=$(tf_require "$tf_output" "resource_group.value.name" "Resource group")
acr_name=$(tf_require "$tf_output" "container_registry.value.name" "ACR name")
acr_login_server=$(tf_require "$tf_output" "container_registry.value.login_server" "ACR login server")

# Verify dataviewer is deployed
dataviewer_deployed=$(tf_get "$tf_output" "dataviewer.value" "")
if [[ -z "$dataviewer_deployed" || "$dataviewer_deployed" == "null" ]]; then
  fatal "Dataviewer is not deployed. Set should_deploy_dataviewer=true in terraform.tfvars and run terraform apply first."
fi

backend_app=$(tf_require "$tf_output" "dataviewer.value.backend.name" "Backend container app name")
frontend_app=$(tf_require "$tf_output" "dataviewer.value.frontend.name" "Frontend container app name")

backend_image="${acr_login_server}/${DATAVIEWER_BACKEND_IMAGE}:${image_tag}"
frontend_image="${acr_login_server}/${DATAVIEWER_FRONTEND_IMAGE}:${image_tag}"

#------------------------------------------------------------------------------
# Configuration Preview
#------------------------------------------------------------------------------

section "Configuration"
print_kv "Resource Group" "$rg"
print_kv "ACR" "$acr_name"
print_kv "Image Tag" "$image_tag"
print_kv "Backend Image" "$backend_image"
print_kv "Frontend Image" "$frontend_image"
print_kv "Backend App" "$backend_app"
print_kv "Frontend App" "$frontend_app"
print_kv "Skip Build" "$skip_build"
print_kv "Skip Update" "$skip_update"

if [[ "$config_preview" == "true" ]]; then
  info "Config preview mode — exiting without changes."
  exit 0
fi

#------------------------------------------------------------------------------
# Build Container Images
#------------------------------------------------------------------------------

SRC_DIR="$SCRIPT_DIR/../../src/dataviewer"

if [[ "$skip_build" == "false" ]]; then

  if [[ "$skip_backend" == "false" ]]; then
    section "Building Backend Image"
    info "Building $backend_image..."
    az acr build \
      --registry "$acr_name" \
      --image "${DATAVIEWER_BACKEND_IMAGE}:${image_tag}" \
      --file "$SRC_DIR/backend/Dockerfile" \
      "$SRC_DIR/backend/"
  fi

  if [[ "$skip_frontend" == "false" ]]; then
    section "Building Frontend Image"
    info "Building $frontend_image..."

    build_args=()
    # Inject MSAL build args when Entra ID auth is deployed
    entra_client_id=$(tf_get "$tf_output" "dataviewer.value.entra_id.client_id" "")
    entra_tenant_id=$(tf_get "$tf_output" "dataviewer.value.entra_id.tenant_id" "")
    if [[ -n "$entra_client_id" && "$entra_client_id" != "null" ]]; then
      build_args+=(--build-arg "VITE_AZURE_CLIENT_ID=${entra_client_id}")
      build_args+=(--build-arg "VITE_AZURE_TENANT_ID=${entra_tenant_id}")
      info "Entra ID auth enabled — injecting MSAL build args"
    fi

    az acr build \
      --registry "$acr_name" \
      --image "${DATAVIEWER_FRONTEND_IMAGE}:${image_tag}" \
      ${build_args[@]+"${build_args[@]}"} \
      --file "$SRC_DIR/frontend/Dockerfile" \
      "$SRC_DIR/frontend/"
  fi
fi

#------------------------------------------------------------------------------
# Update Container Apps
#------------------------------------------------------------------------------

if [[ "$skip_update" == "false" ]]; then

  if [[ "$skip_backend" == "false" ]]; then
    section "Updating Backend Container App"
    info "Deploying $backend_image to $backend_app..."
    az containerapp update \
      --name "$backend_app" \
      --resource-group "$rg" \
      --image "$backend_image"
  fi

  if [[ "$skip_frontend" == "false" ]]; then
    section "Updating Frontend Container App"
    info "Deploying $frontend_image to $frontend_app..."
    az containerapp update \
      --name "$frontend_app" \
      --resource-group "$rg" \
      --image "$frontend_image"
  fi
fi

#------------------------------------------------------------------------------
# Deployment Summary
#------------------------------------------------------------------------------

section "Deployment Summary"
print_kv "Backend Image" "$backend_image"
print_kv "Frontend Image" "$frontend_image"
print_kv "Backend App" "$backend_app"
print_kv "Frontend App" "$frontend_app"
print_kv "Build" "$([[ "$skip_build" == "true" ]] && echo 'Skipped' || echo 'Complete')"
print_kv "Update" "$([[ "$skip_update" == "true" ]] && echo 'Skipped' || echo 'Complete')"
info "Deployment complete"
