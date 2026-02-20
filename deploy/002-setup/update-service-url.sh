#!/usr/bin/env bash
# Update the OSMO control plane SERVICE config (service_base_url).
# Run after port-forward and osmo login.
#
# Usage:
#   ./update-service-url.sh                    # use auto-detected LB URL
#   ./update-service-url.sh http://10.0.5.6    # explicit LB
#   ./update-service-url.sh http://osmo-service.osmo-control-plane.svc.cluster.local   # in-cluster (workflow pods stay 2/2; logger 403)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

service_url="${1:-}"
if [[ -z "$service_url" ]]; then
  service_url=$(detect_service_url)
  [[ -n "$service_url" ]] || fatal "Could not detect service URL. Pass it explicitly: $0 http://<LB_IP>"
  info "Using detected service URL: $service_url"
else
  info "Using provided service URL: $service_url"
fi

mkdir -p "$CONFIG_DIR/out"
echo "{\"service_base_url\":\"$service_url\"}" > "$CONFIG_DIR/out/service-config.json"
info "Applying SERVICE config (service_base_url: $service_url)..."
osmo config update SERVICE --file "$CONFIG_DIR/out/service-config.json" --description "Set service base URL to LB"
info "Done. Restart the backend if you want it to use the same URL: kubectl rollout restart deployment -n osmo-operator osmo-operator-osmo-backend-worker osmo-operator-osmo-backend-listener"
