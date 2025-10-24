#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: test-streaming-session.sh [--namespace NS] [--session-id ID] \
  [--dry-run] [--verbose]

Get NodePort connection details for Omniverse streaming session to access
over VPN with Web Viewer client. Works with NodePort service type.

Optional arguments:
  --namespace NS               Namespace pattern for streaming session
                               (default: auto-detect UUID namespace)
  --session-id ID              Streaming session ID (UUID)
  --dry-run                    Print information without executing
  --verbose                    Enable verbose logging
  --help                       Show this message

Prerequisites:
  * kubectl with context pointed to the target cluster
  * VPN connection to AKS cluster network
  * Active streaming session created via streaming manager API

Example:
  ./test-streaming-session.sh --session-id 2549622e-58fd-4470-9bf0-c27da927c4d7
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

cleanup_session() {
  if [[ -n "${SESSION_ID:-}" && "$DRY_RUN" == "false" ]]; then
    log "Cleaning up session ${SESSION_ID}"
    verbose_log "Namespace with session resources will be deleted automatically by session manager"
  fi
}

trap cleanup_session EXIT SIGINT SIGTERM

NAMESPACE=""
SESSION_ID=""
DRY_RUN="false"
VERBOSE="false"

while (($#)); do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --session-id)
      SESSION_ID="$2"
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

require_command kubectl
require_command jq

if [[ -z "$NAMESPACE" && -z "$SESSION_ID" ]]; then
  verbose_log "Auto-detecting active streaming session namespaces"
  namespaces=$(kubectl get ns -o json 2>/dev/null | \
    jq -r '.items[].metadata.name | select(test("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"))' || true)
  namespace_count=$(echo "$namespaces" | grep -c . || echo 0)
  if [[ $namespace_count -eq 0 ]]; then
    fail "No active streaming session namespaces found (UUID format)"
  fi
  if [[ $namespace_count -gt 1 ]]; then
    log "Multiple streaming sessions found:"
    echo "$namespaces" | sed 's/^/  /'
    fail "Please specify --session-id or --namespace"
  fi
  NAMESPACE="$namespaces"
  SESSION_ID="$NAMESPACE"
  verbose_log "Detected session namespace: ${NAMESPACE}"
elif [[ -n "$SESSION_ID" && -z "$NAMESPACE" ]]; then
  NAMESPACE="$SESSION_ID"
fi

if [[ "$DRY_RUN" == "false" ]]; then
  if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    fail "Namespace ${NAMESPACE} not found"
  fi
fi

verbose_log "Getting service details for session ${SESSION_ID:-$NAMESPACE}"
if [[ "$DRY_RUN" == "false" ]]; then
  SERVICE_NAME=$(kubectl get svc -n "$NAMESPACE" -o json 2>/dev/null | \
    jq -r '.items[] | select(.metadata.name | contains("kit-app")) | .metadata.name' | head -1 || true)
  if [[ -z "$SERVICE_NAME" ]]; then
    fail "No kit-app service found in namespace ${NAMESPACE}"
  fi

  NODE_IP=$(kubectl get pod -n "$NAMESPACE" -o json 2>/dev/null | \
    jq -r '.items[0].status.hostIP // ""' || echo "")
  if [[ -z "$NODE_IP" ]]; then
    fail "Could not determine node IP for session pod"
  fi

  SIGNALING_NODEPORT=$(kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" -o json 2>/dev/null | \
    jq -r '.spec.ports[] | select(.port == 31000) | .nodePort // ""' || echo "")
  MEDIA_NODEPORT=$(kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" -o json 2>/dev/null | \
    jq -r '.spec.ports[] | select(.port == 31001) | .nodePort // ""' || echo "")

  if [[ -z "$SIGNALING_NODEPORT" || -z "$MEDIA_NODEPORT" ]]; then
    fail "Could not retrieve NodePort mappings from service ${SERVICE_NAME}"
  fi
else
  log "[dry-run] Would query service and pod details from namespace"
  SERVICE_NAME="kit-app-<session-id>"
  NODE_IP="<node-ip>"
  SIGNALING_NODEPORT="<signaling-nodeport>"
  MEDIA_NODEPORT="<media-nodeport>"
fi

cat <<EOF

Omniverse Streaming Session Details
====================================

Session ID: ${SESSION_ID:-$NAMESPACE}
Service: ${SERVICE_NAME}
Node IP: ${NODE_IP}

NodePort Mappings:
  Signaling (TCP): 31000 → ${SIGNALING_NODEPORT}
  Media (UDP):     31001 → ${MEDIA_NODEPORT}

Web Viewer Configuration (stream.config.json):
{
  "source": "local",
  "local": {
    "server": "${NODE_IP}",
    "signalingPort": ${SIGNALING_NODEPORT},
    "mediaPort": ${MEDIA_NODEPORT}
  }
}

Instructions:
  1. Clone web-viewer-sample:
     git clone -b 1.5.2 https://github.com/NVIDIA-Omniverse/web-viewer-sample.git

  2. Update stream.config.json with the configuration above

  3. Start Web Viewer:
     cd web-viewer-sample
     npm install
     npm run dev

  4. Open browser (must be on VPN):
     http://localhost:5173/

  5. The Web Viewer will connect to ${NODE_IP}:${SIGNALING_NODEPORT} (signaling)
     and ${NODE_IP}:${MEDIA_NODEPORT} (media)

Notes:
  * You must be connected to the AKS cluster VPN to access node IP ${NODE_IP}
  * Any node IP works with NodePort, but using the pod's node is recommended
  * To get all available node IPs: kubectl get nodes -o wide
  * To terminate session:
      curl -X DELETE http://localhost:8080/stream \\
        -H 'Content-Type: application/json' \\
        -d '{"id": "${SESSION_ID:-$NAMESPACE}"}'

EOF
