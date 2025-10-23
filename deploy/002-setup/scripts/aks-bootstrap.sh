#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: aks-bootstrap.sh --acr-name NAME [--namespace NAME] \
  [--ngc-token TOKEN] [--acr-username USER] [--acr-password PASS] \
  [--regcred-name NAME] [--ngc-secret-name NAME] [--use-az-token] \
  [--dry-run] [--verbose] [--skip-verify]

Prepare the target AKS namespace with pull secrets required by
Omniverse Kit App Streaming workloads.

Required arguments:
  --acr-name NAME          Azure Container Registry name (no fqdn)

Optional arguments:
  --namespace NAME         Namespace for Omniverse resources (default: omni-streaming)
  --ngc-token TOKEN        NGC API token (defaults to $NGC_API_TOKEN)
  --acr-username USER      Username for ACR pull secret (defaults to $ACR_USERNAME)
  --acr-password PASS      Password for ACR pull secret (defaults to $ACR_PASSWORD)
  --regcred-name NAME      Name of Docker registry secret (default: regcred)
  --ngc-secret-name NAME   Name of NGC API secret (default: ngc-omni-user)
  --use-az-token           Fetch temporary ACR token via az acr login --expose-token
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

acr_registry_fqdn() {
  printf '%s.azurecr.io' "$ACR_NAME"
}

resolve_acr_credentials() {
  if [[ "$USE_AZ_TOKEN" == "true" ]]; then
    require_command az
    local token
    verbose_log "Requesting temporary ACR token via az"
    token=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken) \
      || fail "Unable to obtain ACR token from az"
    ACR_SECRET_USERNAME="00000000-0000-0000-0000-000000000000"
    ACR_SECRET_PASSWORD="$token"
    return
  fi

  if [[ -z "$ACR_SECRET_PASSWORD" ]]; then
    fail "Provide --acr-password, export ACR_PASSWORD, or use --use-az-token"
  fi

  if [[ -z "$ACR_SECRET_USERNAME" ]]; then
    ACR_SECRET_USERNAME="00000000-0000-0000-0000-000000000000"
  fi
}

docker_config_payload() {
  local registry auth_json auth_value
  registry="$(acr_registry_fqdn)"

  if [[ "$DRY_RUN" == "true" ]]; then
    auth_json=$(cat <<EOF
{"auths":{"$registry":{"auth":"REDACTED"}}}
EOF
)
  else
    auth_value=$(printf '%s:%s' "$ACR_SECRET_USERNAME" "$ACR_SECRET_PASSWORD" | base64_no_wrap)
    auth_json=$(cat <<EOF
{"auths":{"$registry":{"username":"$ACR_SECRET_USERNAME","password":"$ACR_SECRET_PASSWORD","email":"none","auth":"$auth_value"}}}
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
  api-key: $(encode_secret_value "$NGC_TOKEN")
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

ACR_NAME=""
KUBE_NAMESPACE="omni-streaming"
NGC_TOKEN="${NGC_API_TOKEN:-}"
ACR_SECRET_USERNAME="${ACR_USERNAME:-}"
ACR_SECRET_PASSWORD="${ACR_PASSWORD:-}"
REGCRED_NAME="regcred"
NGC_SECRET_NAME="ngc-omni-user"
NGC_SECRET_USERNAME_VALUE="\$oauthtoken"
USE_AZ_TOKEN="false"
DRY_RUN="false"
VERBOSE="false"
SKIP_VERIFY="false"

while (($#)); do
  case "$1" in
    --acr-name)
      [[ $# -lt 2 ]] && fail "--acr-name requires a value"
      ACR_NAME="$2"
      shift 2
      ;;
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
    --acr-username)
      [[ $# -lt 2 ]] && fail "--acr-username requires a value"
      ACR_SECRET_USERNAME="$2"
      shift 2
      ;;
    --acr-password)
      [[ $# -lt 2 ]] && fail "--acr-password requires a value"
      ACR_SECRET_PASSWORD="$2"
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
    --use-az-token)
      USE_AZ_TOKEN="true"
      shift 1
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

if [[ -z "$ACR_NAME" ]]; then
  fail "--acr-name is required"
fi

if [[ -z "$NGC_TOKEN" ]]; then
  fail "Provide --ngc-token or export NGC_API_TOKEN"
fi

require_command kubectl

resolve_acr_credentials

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
