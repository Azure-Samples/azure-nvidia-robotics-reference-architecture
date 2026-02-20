#!/usr/bin/env bash
# Build and push the OSMO client image from the fixed OSMO repo (Azure dataset upload fix).
# Use this so workflow pods get the CLI that builds the Azure connection string from
# access_key_id + access_key. See docs/deployment-issues-and-fixes.md §3.12.
#
# Prerequisites: Bazel (bazelisk), Docker, Azure CLI (az), jq. ACR must exist (001-iac).
#
# Usage:
#   ./build-osmo-client-image.sh [--acr-name NAME] [--image-tag TAG] [--tf-dir DIR] [--osmo-dir DIR] [--skip-builder-load]
#
# After running: use the same image tag in the cluster (restart backend or re-run 04 script),
# then submit a new workflow so the pod uses the new client image.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.conf
source "$SCRIPT_DIR/defaults.conf"

# Defaults (OSMO is sibling of deploy/, so 002-setup -> ../../OSMO)
tf_dir="${SCRIPT_DIR}/../001-iac"
osmo_dir="${SCRIPT_DIR}/../../OSMO"
acr_name=""
image_tag="${OSMO_IMAGE_VERSION:-6.0.0}"
skip_builder_load=false

usage() {
  echo "Usage: $(basename "$0") [OPTIONS]"
  echo ""
  echo "Build and push OSMO client image from the fixed repo to your ACR."
  echo ""
  echo "Options:"
  echo "  --acr-name NAME    ACR name (default: from Terraform container_registry.name)"
  echo "  --image-tag TAG    Image tag (default: ${OSMO_IMAGE_VERSION:-6.0.0})"
  echo "  --tf-dir DIR       Terraform directory for ACR lookup (default: ../001-iac)"
  echo "  --osmo-dir DIR     OSMO repo directory (default: ../../OSMO)"
  echo "  --skip-builder-load  Skip loading builder image (use if already loaded)"
  echo "  -h, --help         Show this help"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --acr-name)        acr_name="$2"; shift 2 ;;
    --image-tag)       image_tag="$2"; shift 2 ;;
    --tf-dir)          tf_dir="$2"; shift 2 ;;
    --osmo-dir)        osmo_dir="$2"; shift 2 ;;
    --skip-builder-load) skip_builder_load=true; shift ;;
    -h|--help)         usage ;;
    *)                 fatal "Unknown option: $1" ;;
  esac
done

require_tools bazel docker az jq

[[ -d "$osmo_dir" ]] || fatal "OSMO directory not found: $osmo_dir"
[[ -f "$osmo_dir/MODULE.bazel" ]] || fatal "MODULE.bazel not found in $osmo_dir (is this the OSMO repo?)"

# Resolve ACR name
if [[ -z "$acr_name" ]]; then
  [[ -d "$tf_dir" ]] || fatal "Terraform directory not found: $tf_dir (use --tf-dir)"
  tf_output=$(read_terraform_outputs "$tf_dir")
  acr_name=$(echo "$tf_output" | jq -r '.container_registry.value.name // .container_registry.name // empty')
  [[ -n "$acr_name" ]] || fatal "Could not get container_registry.name from Terraform (use --acr-name)"
fi

acr_login_server="${acr_name}.azurecr.io"
base_image_url="${acr_login_server}/osmo/"

info "ACR: $acr_login_server"
info "Image tag: $image_tag"
info "OSMO repo: $osmo_dir"

# Backup and update MODULE.bazel (restore on exit)
MODULE_BAZEL="${osmo_dir}/MODULE.bazel"
cp "$MODULE_BAZEL" "${MODULE_BAZEL}.bak"
info "Backed up MODULE.bazel"
restore_module_bazel() {
  if [[ -f "${MODULE_BAZEL}.bak" ]]; then
    mv "${MODULE_BAZEL}.bak" "$MODULE_BAZEL"
    info "Restored MODULE.bazel"
  fi
}
trap restore_module_bazel EXIT

sed "s|BASE_IMAGE_URL = \"nvcr.io/nvidia/osmo/\"|BASE_IMAGE_URL = \"${base_image_url}\"|" "$MODULE_BAZEL" > "${MODULE_BAZEL}.tmp" && mv "${MODULE_BAZEL}.tmp" "$MODULE_BAZEL"
sed "s|IMAGE_TAG = \"\"|IMAGE_TAG = \"${image_tag}\"|" "$MODULE_BAZEL" > "${MODULE_BAZEL}.tmp" && mv "${MODULE_BAZEL}.tmp" "$MODULE_BAZEL"
info "Updated MODULE.bazel (BASE_IMAGE_URL, IMAGE_TAG)"

# Get ACR credentials or use Azure CLI login
# If admin user is disabled or ACR is in another subscription, we use az acr login on the host
# and the builder container will use the host's Docker daemon (already logged in).
acr_username=""
acr_password=""
use_acr_login=false
if az acr credential show -n "$acr_name" --query username -o tsv &>/dev/null; then
  info "Fetching ACR credentials (admin user)..."
  acr_username=$(az acr credential show -n "$acr_name" --query username -o tsv 2>/dev/null || true)
  acr_password=$(az acr credential show -n "$acr_name" --query "passwords[0].value" -o tsv 2>/dev/null || true)
fi
if [[ -z "$acr_username" || -z "$acr_password" ]]; then
  info "Admin credentials not available (wrong subscription or admin disabled). Using 'az acr login' on host..."
  az acr login -n "$acr_name" || fatal "Could not log in to ACR. Run: az login and ensure you have access to $acr_name (or set subscription: az account set -s <id>)"
  use_acr_login=true
fi

# Load builder image unless skipped
if [[ "$skip_builder_load" != "true" ]]; then
  info "Loading OSMO builder image (this may take a while on first run)..."
  (cd "$osmo_dir" && bazel run --platforms=@io_bazel_rules_go//go/toolchain:linux_amd64 @osmo_workspace//run:builder_image_load_x86_64) || fatal "Failed to load builder image"
else
  info "Skipping builder image load (--skip-builder-load)"
  docker image inspect osmo-builder:latest-amd64 &>/dev/null || fatal "Builder image osmo-builder:latest-amd64 not found. Run without --skip-builder-load."
fi

# Build and push client image from builder container
# When use_acr_login is true, host Docker is already logged in via az acr login; the container uses the host's socket.
info "Building and pushing client image (runs inside builder container)..."
if [[ "$use_acr_login" == "true" ]]; then
  (cd "$osmo_dir" && docker run --rm \
    -v "$(pwd)":/workspace -w /workspace \
    -v /var/run/docker.sock:/var/run/docker.sock \
    osmo-builder:latest-amd64 \
    bash -c 'bazel run @osmo_workspace//src/cli:cli_push_x86_64') || fatal "Build/push failed"
else
  (cd "$osmo_dir" && docker run --rm \
    -v "$(pwd)":/workspace -w /workspace \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e CONTAINER_REGISTRY="$acr_login_server" \
    -e CONTAINER_REGISTRY_USERNAME="$acr_username" \
    -e CONTAINER_REGISTRY_PASSWORD="$acr_password" \
    osmo-builder:latest-amd64 \
    bash -c 'echo "$CONTAINER_REGISTRY_PASSWORD" | docker login -u "$CONTAINER_REGISTRY_USERNAME" --password-stdin "$CONTAINER_REGISTRY" && bazel run @osmo_workspace//src/cli:cli_push_x86_64') || fatal "Build/push failed"
fi

# Optionally tag and push as client:$TAG (no -amd64) for single-tag deploy
info "Tagging and pushing client:${image_tag} (for single-tag deploy)..."
docker pull "${acr_login_server}/osmo/client:${image_tag}-amd64" || true
docker tag "${acr_login_server}/osmo/client:${image_tag}-amd64" "${acr_login_server}/osmo/client:${image_tag}"
docker push "${acr_login_server}/osmo/client:${image_tag}" || warn "Push of client:${image_tag} failed (cluster may use client:${image_tag}-amd64)"

info "Done. Client image pushed to ${acr_login_server}/osmo/client:${image_tag}"
info "Next: restart backend so new workflow pods use it: kubectl rollout restart deployment -n osmo-operator osmo-operator-osmo-backend-worker osmo-operator-osmo-backend-listener"
info "Then submit a new workflow; dataset upload should succeed."
