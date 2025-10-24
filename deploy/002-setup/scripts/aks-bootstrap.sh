#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: aks-bootstrap.sh [--namespace NAME] \
  [--ngc-token TOKEN] \
  [--regcred-name NAME] [--ngc-secret-name NAME] [--use-az-token] \
  [--dry-run] [--verbose] [--skip-verify]

Prepare the target AKS namespace with pull secrets required by
Omniverse Kit App Streaming workloads.

Required arguments:
  --ngc-token TOKEN        NGC API token (required, or set $NGC_API_TOKEN)

Optional arguments:
  --namespace NAME         Namespace for Omniverse resources (default: omni-streaming)
  --regcred-name NAME      Name of Docker registry secret (default: ngc-registry-secret)
  --ngc-secret-name NAME   Name of NGC API secret (default: ngc-omni-user)
  --dry-run                Print rendered manifests instead of applying
  --verbose                Enable verbose logging
  --skip-verify            Skip kubectl get checks after apply
  --help                   Show this message

Prerequisites:
  * kubectl with context pointed to the target cluster
  * az CLI when using --use-az-token
  * Helm and deployment tooling already configured per repo workflow
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

base64_no_wrap() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

encode_secret_value() {
  local value="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    base64_no_wrap "REDACTED"
  else
    base64_no_wrap "$value"
  fi
}

docker_config_payload() {
  local registry auth_json auth_value
  registry="nvcr.io"

  if [[ "$DRY_RUN" == "true" ]]; then
    auth_json=$(cat <<EOF
{"auths":{"$registry":{"auth":"REDACTED"}}}
EOF
)
  else
    auth_value=$(base64_no_wrap "\$oauthtoken:$NGC_TOKEN")
    auth_json=$(cat <<EOF
{"auths":{"$registry":{"username":"\$oauthtoken","password":"$NGC_TOKEN","email":"none","auth":"$auth_value"}}}
EOF
)
  fi

  base64_no_wrap "$auth_json"
}

generate_namespace_manifest() {
  cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $KUBE_NAMESPACE
EOF
}

generate_regcred_manifest() {
  cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $REGCRED_NAME
  namespace: $KUBE_NAMESPACE
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $(docker_config_payload)
EOF
}

generate_ngc_manifest() {
  cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $NGC_SECRET_NAME
  namespace: $KUBE_NAMESPACE
type: Opaque
data:
  username: $(encode_secret_value "$NGC_SECRET_USERNAME_VALUE")
  password: $(encode_secret_value "$NGC_TOKEN")
EOF
}

apply_manifest() {
  local description="$1"
  local manifest="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] ${description}"
    printf '---\n%s\n' "$manifest"
    return
  fi

  printf '%s\n' "$manifest" | kubectl apply -f -
  log "Applied ${description}"
}

verify_namespace() {
  if [[ "$DRY_RUN" == "true" || "$SKIP_VERIFY" == "true" ]]; then
    return
  fi

  if ! kubectl get namespace "$KUBE_NAMESPACE" >/dev/null 2>&1; then
    fail "Namespace $KUBE_NAMESPACE not found after apply"
  fi

  log "Verified namespace $KUBE_NAMESPACE"
}

verify_secret() {
  local secret_name="$1"

  if [[ "$DRY_RUN" == "true" || "$SKIP_VERIFY" == "true" ]]; then
    return
  fi

  if ! kubectl get secret "$secret_name" -n "$KUBE_NAMESPACE" >/dev/null 2>&1; then
    fail "Secret $secret_name not found after apply"
  fi

  log "Verified secret $secret_name in namespace $KUBE_NAMESPACE"
}

KUBE_NAMESPACE="omni-streaming"
NGC_TOKEN="${NGC_API_TOKEN:-}"
REGCRED_NAME="ngc-registry-secret"
NGC_SECRET_NAME="ngc-omni-user"
NGC_SECRET_USERNAME_VALUE="\$oauthtoken"
DRY_RUN="false"
VERBOSE="false"
SKIP_VERIFY="false"

while (($#)); do
  case "$1" in
    --namespace)
      [[ $# -lt 2 ]] && fail "--namespace requires a value"
      KUBE_NAMESPACE="$2"
      shift 2
      ;;
    --ngc-token)
      [[ $# -lt 2 ]] && fail "--ngc-token requires a value"
      NGC_TOKEN="$2"
      shift 2
      ;;
    --regcred-name)
      [[ $# -lt 2 ]] && fail "--regcred-name requires a value"
      REGCRED_NAME="$2"
      shift 2
      ;;
    --ngc-secret-name)
      [[ $# -lt 2 ]] && fail "--ngc-secret-name requires a value"
      NGC_SECRET_NAME="$2"
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

if [[ -z "$NGC_TOKEN" ]]; then
  fail "Provide --ngc-token or export NGC_API_TOKEN"
fi

require_command kubectl

namespace_manifest="$(generate_namespace_manifest)"
apply_manifest "namespace ${KUBE_NAMESPACE}" "$namespace_manifest"
verify_namespace

regcred_manifest="$(generate_regcred_manifest)"
apply_manifest "secret ${REGCRED_NAME}" "$regcred_manifest"
verify_secret "$REGCRED_NAME"

ngc_manifest="$(generate_ngc_manifest)"
apply_manifest "secret ${NGC_SECRET_NAME}" "$ngc_manifest"
verify_secret "$NGC_SECRET_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
  log "Dry-run complete. Manifests rendered above."
else
  log "AKS bootstrap completed for namespace ${KUBE_NAMESPACE}."
  if [[ "$SKIP_VERIFY" == "false" ]]; then
    log "Namespace and secrets verified."
  fi
fi
