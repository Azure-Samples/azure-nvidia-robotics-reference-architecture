#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deploy-omniverse.sh --app-version VERSION --ngc-token TOKEN \
  [--namespace NS] [--flux-namespace NS] [--values-dir DIR] \
  [--dry-run] [--skip-validate] [--verbose]

Install Omniverse Kit App Streaming on AKS using NVIDIA NGC Helm charts
and container registry directly.

Required arguments:
  --app-version VERSION    Omniverse chart version to deploy
  --ngc-token TOKEN        NGC API token (or set $NGC_API_TOKEN)

Optional arguments:
  --namespace NS           Application namespace (default: omni-streaming)
  --flux-namespace NS      Flux namespace (default: flux-operators)
  --values-dir DIR         Directory containing Helm values overlays
                           (default: ../values relative to this script)
  --dry-run                Log the commands without executing them
  --skip-validate          Skip kubectl rollout validation checks
  --verbose                Print executed commands
  --help                   Show this message

Prerequisites:
  * helm >= 3.8
  * kubectl >= 1.29 (required unless --dry-run)
  * NGC secret 'ngc-omni-user' in target namespace for image pulls
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

log_command() {
  local prefix="$1"
  shift
  if [[ -z "$prefix" ]]; then
    return
  fi
  printf '%s' "$prefix" >&2
  while (($#)); do
    printf ' %q' "$1" >&2
    shift
  done
  printf '\n' >&2
}

run_command() {
  local -a cmd=("$@")
  if [[ "$DRY_RUN" == "true" ]]; then
    log_command "[dry-run]" "${cmd[@]}"
    return 0
  fi
  if [[ "$VERBOSE" == "true" ]]; then
    log_command "[exec]" "${cmd[@]}"
  fi
  "${cmd[@]}"
}

login_ngc_registry() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] helm repo add omniverse https://helm.ngc.nvidia.com/nvidia/omniverse"
    return
  fi
  helm repo remove omniverse >/dev/null 2>&1 || true
  helm repo add omniverse https://helm.ngc.nvidia.com/nvidia/omniverse \
    --username "\$oauthtoken" \
    --password "$NGC_TOKEN" \
    --force-update >/dev/null \
    || fail "Unable to add NGC Helm repository"
}

ensure_namespace() {
  local ns="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] ensure namespace ${ns}"
    return
  fi
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    return
  fi
  log "Creating namespace ${ns}"
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${ns}
EOF
}

render_values() {
  local source="$1" name="$2" output
  if [[ ! -f "$source" ]]; then
    fail "Values file not found: ${source}"
  fi
  output="${WORK_DIR}/${name}.yaml"
  sed -e "s|{{APP_VERSION}}|${APP_VERSION}|g" \
    "$source" >"$output"
  printf '%s\n' "$output"
}

validate_rollouts() {
  local ns="$1" release="$2" timeout="$3"
  if [[ "$DRY_RUN" == "true" || "$SKIP_VALIDATE" == "true" ]]; then
    return
  fi
  mapfile -t resources < <(kubectl -n "$ns" get deploy,statefulset \
    -l app.kubernetes.io/instance="$release" -o name 2>/dev/null | awk 'NF') || true
  if ((${#resources[@]} == 0)); then
    verbose_log "No rollout-managed resources for ${release} in ${ns}"
    return
  fi
  for resource in "${resources[@]}"; do
    log "Validating ${resource}"
    kubectl -n "$ns" rollout status "$resource" --timeout "$timeout"
  done
}

run_helm_upgrade() {
  local release="$1" chart="$2" namespace="$3" timeout="$4"
  shift 4
  local -a base=(helm upgrade --install "$release" "$chart" \
    --namespace "$namespace" --wait --timeout "$timeout" --atomic)
  if [[ "$DRY_RUN" == "true" ]]; then
    log_command "[dry-run]" "${base[@]}" "$@" "--dry-run" "--debug"
    return
  fi
  if [[ "$VERBOSE" == "true" ]]; then
    log_command "[exec]" "${base[@]}" "$@"
  else
    log "Applying release ${release} in ${namespace}"
  fi
  "${base[@]}" "$@"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_VALUES_DIR="$(cd "${SCRIPT_DIR}/../values" && pwd)"

NGC_TOKEN="${NGC_API_TOKEN:-}"
APP_VERSION=""
APP_NAMESPACE="omni-streaming"
FLUX_NAMESPACE="flux-operators"
VALUES_DIR=""
DRY_RUN="false"
VERBOSE="false"
SKIP_VALIDATE="false"
HELM_TIMEOUT="10m"
ROLLOUT_TIMEOUT="5m"
WORK_DIR=""

while (($#)); do
  case "$1" in
    --ngc-token)
      NGC_TOKEN="$2"
      shift 2
      ;;
    --app-version)
      APP_VERSION="$2"
      shift 2
      ;;
    --namespace)
      APP_NAMESPACE="$2"
      shift 2
      ;;
    --flux-namespace)
      FLUX_NAMESPACE="$2"
      shift 2
      ;;
    --values-dir)
      VALUES_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift 1
      ;;
    --skip-validate)
      SKIP_VALIDATE="true"
      shift 1
      ;;
    --verbose)
      VERBOSE="true"
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

: "${NGC_TOKEN:?Provide --ngc-token or export NGC_API_TOKEN}"
: "${APP_VERSION:?--app-version is required}"

if [[ -z "$VALUES_DIR" ]]; then
  VALUES_DIR="$DEFAULT_VALUES_DIR"
elif [[ -d "$VALUES_DIR" ]]; then
  VALUES_DIR="$(cd "$VALUES_DIR" && pwd)"
else
  fail "Values directory not found: ${VALUES_DIR}"
fi

if [[ ! -d "$VALUES_DIR" ]]; then
  fail "Values directory not found: ${VALUES_DIR}"
fi

require_command helm
if [[ "$DRY_RUN" == "false" ]]; then
  require_command kubectl
fi

OUT_DIR="${PWD}/out"
mkdir -p "$OUT_DIR"
WORK_DIR="${OUT_DIR}/deploy-omniverse"
mkdir -p "$WORK_DIR"

FLUX_VALUES="${VALUES_DIR}/flux2-aksgpu.yaml"
MEMCACHED_VALUES="${VALUES_DIR}/memcached-aksgpu.yaml"
RMCP_TEMPLATE="${VALUES_DIR}/kit-appstreaming-rmcp-aksgpu.yaml"
MANAGER_TEMPLATE="${VALUES_DIR}/kit-appstreaming-manager-aksgpu.yaml"
APPS_TEMPLATE="${VALUES_DIR}/kit-appstreaming-applications-aksgpu.yaml"

if [[ ! -f "$FLUX_VALUES" ]]; then
  fail "Flux values file not found: ${FLUX_VALUES}"
fi
if [[ ! -f "$MEMCACHED_VALUES" ]]; then
  fail "Memcached values file not found: ${MEMCACHED_VALUES}"
fi

RMCP_VALUES="$(render_values "$RMCP_TEMPLATE" "kit-appstreaming-rmcp")"
MANAGER_VALUES="$(render_values "$MANAGER_TEMPLATE" "kit-appstreaming-manager")"
APPS_VALUES="$(render_values "$APPS_TEMPLATE" "kit-appstreaming-applications")"

login_ngc_registry

run_command helm repo add fluxcd-community \
  https://fluxcd-community.github.io/helm-charts --force-update >/dev/null
run_command helm repo add bitnami https://charts.bitnami.com/bitnami --force-update >/dev/null
run_command helm repo update >/dev/null

ensure_namespace "$FLUX_NAMESPACE"
ensure_namespace "$APP_NAMESPACE"

declare -a DEPLOYED_RELEASES=()

run_release() {
  local release="$1" chart="$2" namespace="$3" values_file="$4" version_flag="$5"
  shift 5
  local -a extra=("--values" "$values_file")
  if [[ -n "$version_flag" ]]; then
    extra+=("--version" "$version_flag")
  fi
  extra+=("$@")
  run_helm_upgrade "$release" "$chart" "$namespace" "$HELM_TIMEOUT" "${extra[@]}"
  DEPLOYED_RELEASES+=("${release}|${namespace}|${chart}")
  validate_rollouts "$namespace" "$release" "$ROLLOUT_TIMEOUT"
}

run_release flux fluxcd-community/flux2 "$FLUX_NAMESPACE" "$FLUX_VALUES" "" "--create-namespace"
run_release omni-memcached bitnami/memcached "$APP_NAMESPACE" "$MEMCACHED_VALUES" ""
run_release omni-rmcp omniverse/kit-appstreaming-rmcp "$APP_NAMESPACE" "$RMCP_VALUES" "$APP_VERSION"
run_release omni-manager omniverse/kit-appstreaming-manager "$APP_NAMESPACE" "$MANAGER_VALUES" "$APP_VERSION"
run_release omni-applications omniverse/kit-appstreaming-applications "$APP_NAMESPACE" "$APPS_VALUES" "$APP_VERSION"

log "Releases processed:"
for entry in "${DEPLOYED_RELEASES[@]}"; do
  IFS='|' read -r rel ns chart <<<"$entry"
  log " - ${rel} (${ns}) <- ${chart}"
done
