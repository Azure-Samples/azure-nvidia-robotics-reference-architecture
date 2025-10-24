#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deploy-usd-viewer-app.sh --acr-name NAME --app-version VERSION \
  [--namespace NS] [--profile-type TYPE] [--dry-run] [--verbose] \
  [--skip-verify]

Deploy Omniverse USD Viewer Application, ApplicationVersion, and
ApplicationProfile CRDs to AKS cluster.

Required arguments:
  --acr-name NAME          Azure Container Registry name (no fqdn)
  --app-version VERSION    Omniverse chart version matching mirrored charts

Optional arguments:
  --namespace NS           Application namespace (default: omni-streaming)
  --profile-type TYPE      Profile variant to deploy: partialgpu or fullgpu
                           (default: partialgpu)
  --dry-run                Print rendered manifests without applying
  --verbose                Enable verbose logging
  --skip-verify            Skip kubectl get checks after apply
  --help                   Show this message

Prerequisites:
  * kubectl with context pointed to the target cluster
  * Omniverse core services deployed via deploy-omniverse.sh
  * GPU node pools configured with appropriate taints
EOF
}

log() {
  printf '%s\n' "$1" >&2
}

verbose_log() {
  if [[ "$VERBOSE" == "true" ]]; then
    log "$1"
  fi
}

fail() {
  log "ERROR: $1"
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing required command: $1"
  fi
}

render_template() {
  local source="$1" output
  if [[ ! -f "$source" ]]; then
    fail "Template file not found: ${source}"
  fi
  output=$(sed -e "s|{{ACR_NAME}}|${ACR_NAME}|g" \
    -e "s|{{APP_VERSION}}|${APP_VERSION}|g" "$source")
  printf '%s\n' "$output"
}

apply_manifest() {
  local description="$1" manifest="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] ${description}"
    printf '---\n%s\n' "$manifest"
    return
  fi
  printf '%s\n' "$manifest" | kubectl apply -f -
  log "Applied ${description}"
}

verify_crd() {
  local kind="$1" name="$2"
  if [[ "$DRY_RUN" == "true" || "$SKIP_VERIFY" == "true" ]]; then
    return
  fi
  if ! kubectl get "$kind" "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
    fail "${kind} ${name} not found after apply"
  fi
  log "Verified ${kind} ${name} in namespace ${NAMESPACE}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_DIR="$(cd "${SCRIPT_DIR}/../values" && pwd)"

ACR_NAME=""
APP_VERSION=""
NAMESPACE="omni-streaming"
PROFILE_TYPE="partialgpu"
DRY_RUN="false"
VERBOSE="false"
SKIP_VERIFY="false"

while (($#)); do
  case "$1" in
    --acr-name)
      ACR_NAME="$2"
      shift 2
      ;;
    --app-version)
      APP_VERSION="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --profile-type)
      PROFILE_TYPE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift 1
      ;;
    --verbose)
      VERBOSE="true"
      shift 1
      ;;
    --skip-verify)
      SKIP_VERIFY="true"
      shift 1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

: "${ACR_NAME:?--acr-name is required}"
: "${APP_VERSION:?--app-version is required}"

if [[ "$PROFILE_TYPE" != "partialgpu" && \
  "$PROFILE_TYPE" != "fullgpu" ]]; then
  fail "--profile-type must be partialgpu or fullgpu"
fi

require_command kubectl

APP_TEMPLATE="${VALUES_DIR}/usd-viewer-application.yaml"
VERSION_TEMPLATE="${VALUES_DIR}/usd-viewer-version.yaml"
PROFILE_TEMPLATE="${VALUES_DIR}/usd-viewer-${PROFILE_TYPE}-profile.yaml"

if [[ ! -f "$APP_TEMPLATE" ]]; then
  fail "Application template not found: ${APP_TEMPLATE}"
fi
if [[ ! -f "$VERSION_TEMPLATE" ]]; then
  fail "ApplicationVersion template not found: ${VERSION_TEMPLATE}"
fi
if [[ ! -f "$PROFILE_TEMPLATE" ]]; then
  fail "ApplicationProfile template not found: ${PROFILE_TEMPLATE}"
fi

verbose_log "Rendering Application manifest"
app_manifest=$(render_template "$APP_TEMPLATE")
apply_manifest "Application usd-viewer" "$app_manifest"
verify_crd "application" "usd-viewer"

verbose_log "Rendering ApplicationVersion manifest"
version_manifest=$(render_template "$VERSION_TEMPLATE")
apply_manifest "ApplicationVersion usd-viewer-${APP_VERSION}" "$version_manifest"
verify_crd "applicationversion" "usd-viewer-${APP_VERSION}"

verbose_log "Rendering ApplicationProfile manifest"
profile_manifest=$(render_template "$PROFILE_TEMPLATE")
apply_manifest "ApplicationProfile usd-viewer-${PROFILE_TYPE}" \
  "$profile_manifest"
verify_crd "applicationprofile" "usd-viewer-${PROFILE_TYPE}"

if [[ "$DRY_RUN" == "false" ]]; then
  log "USD Viewer application deployed with ${PROFILE_TYPE} profile"
fi
