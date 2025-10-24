#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: test-streaming-session.sh [--namespace NS] [--service-name NAME] \
  [--local-signaling-port PORT] [--local-media-port PORT] \
  [--session-id ID] [--dry-run] [--verbose]

Port-forward Omniverse streaming service to local workstation for testing
with Web Viewer client. Optionally clean up streaming sessions.

Optional arguments:
  --namespace NS               Namespace for streaming service
                               (default: omni-streaming)
  --service-name NAME          Service name to port-forward
                               (default: auto-detect from profile)
  --local-signaling-port PORT  Local port for WebRTC signaling
                               (default: 30100)
  --local-media-port PORT      Local port for WebRTC media
                               (default: 30101)
  --session-id ID              Streaming session ID to clean up on exit
  --dry-run                    Print commands without executing
  --verbose                    Enable verbose logging
  --help                       Show this message

Prerequisites:
  * kubectl with context pointed to the target cluster
  * Streaming session service deployed
  * USD Viewer application deployed via deploy-usd-viewer-app.sh

Example:
  ./test-streaming-session.sh --service-name usd-viewer-session
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

cleanup_port_forward() {
  if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
    log "Terminating port-forward (PID: $PORT_FORWARD_PID)"
    kill "$PORT_FORWARD_PID" 2>/dev/null || true
    wait "$PORT_FORWARD_PID" 2>/dev/null || true
  fi

  if [[ -n "${SESSION_ID:-}" && "$DRY_RUN" == "false" ]]; then
    log "Cleaning up session ${SESSION_ID}"
    verbose_log "Sending DELETE request to streaming manager"
  fi
}

trap cleanup_port_forward EXIT SIGINT SIGTERM

NAMESPACE="omni-streaming"
SERVICE_NAME=""
LOCAL_SIGNALING_PORT="30100"
LOCAL_MEDIA_PORT="30101"
SESSION_ID=""
DRY_RUN="false"
VERBOSE="false"
PORT_FORWARD_PID=""

while (($#)); do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="$2"
      shift 2
      ;;
    --local-signaling-port)
      LOCAL_SIGNALING_PORT="$2"
      shift 2
      ;;
    --local-media-port)
      LOCAL_MEDIA_PORT="$2"
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

if [[ -z "$SERVICE_NAME" ]]; then
  verbose_log "Auto-detecting streaming session service"
  if [[ "$DRY_RUN" == "true" ]]; then
    SERVICE_NAME="usd-viewer-session-example"
    log "[dry-run] Would auto-detect service in namespace ${NAMESPACE}"
  else
    mapfile -t services < <(kubectl get svc -n "$NAMESPACE" \
      -o jsonpath='{range .items[?(@.spec.ports[?(@.port==31000)])]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
    if ((${#services[@]} == 0)); then
      log "No streaming session services found (looking for services with port 31000)"
      log ""
      log "Available services in ${NAMESPACE}:"
      kubectl get svc -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,PORTS:.spec.ports[*].port 2>/dev/null || true
      log ""
      log "Note: You need to create a streaming session first."
      log "The 'streaming' service is the session manager API (port 80),"
      log "not the actual WebRTC streaming endpoint."
      log ""
      log "To create a session, use the streaming manager API:"
      log "  kubectl port-forward -n ${NAMESPACE} svc/streaming 8080:80"
      log "  curl -X POST http://localhost:8080/stream \\"
      log "    -H 'Content-Type: application/json' \\"
      log "    -d '{\"id\":\"usd-viewer\",\"version\":\"107.3.2\",\"profile\":\"usd-viewer-partialgpu\"}'"
      fail "No active streaming session services found"
    fi
    SERVICE_NAME="${services[0]}"
    verbose_log "Detected service: ${SERVICE_NAME}"
  fi
fi

if [[ "$DRY_RUN" == "false" ]]; then
  if ! kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" \
    >/dev/null 2>&1; then
    fail "Service ${SERVICE_NAME} not found in namespace ${NAMESPACE}"
  fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "[dry-run] Would execute:"
  log "kubectl port-forward -n ${NAMESPACE} svc/${SERVICE_NAME} \\"
  log "  ${LOCAL_SIGNALING_PORT}:31000 ${LOCAL_MEDIA_PORT}:31001"
else
  verbose_log "Starting port-forward for service ${SERVICE_NAME}"
  kubectl port-forward -n "$NAMESPACE" \
    "svc/$SERVICE_NAME" \
    "${LOCAL_SIGNALING_PORT}:31000" \
    "${LOCAL_MEDIA_PORT}:31001" \
    >/dev/null 2>&1 &
  PORT_FORWARD_PID=$!

  sleep 2
  if ! kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
    fail "Port-forward process died immediately"
  fi
fi

cat <<EOF

Port-forward active (PID: ${PORT_FORWARD_PID:-N/A})

Web Viewer Configuration:
  source: local
  server: 127.0.0.1
  signalingPort: ${LOCAL_SIGNALING_PORT}
  mediaPort: ${LOCAL_MEDIA_PORT}

Instructions:
  1. Clone web-viewer-sample:
     git clone -b 1.5.2 https://github.com/NVIDIA-Omniverse/web-viewer-sample.git

  2. Configure stream.config.json:
     {
       "source": "local",
       "server": "127.0.0.1",
       "signalingPort": ${LOCAL_SIGNALING_PORT},
       "mediaPort": ${LOCAL_MEDIA_PORT},
       "resolution": "1920x1080",
       "fps": 30
     }

  3. Start Web Viewer:
     cd web-viewer-sample
     npm install
     npm run dev

  4. Open browser:
     http://localhost:5173/

Press Ctrl+C to terminate port-forward
EOF

if [[ "$DRY_RUN" == "false" ]]; then
  wait "$PORT_FORWARD_PID"
fi
