#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Review submit-training.sh for additional arguments and their details.
#
# --run-smoke-test: validates Azure connectivity before training starts
# --sleep-after-unpack 7200: pauses 2 hours after extracting payload for debugging
# --dry-run: Outputs resolved workflow without submitting to OSMO

exec "${SCRIPT_DIR}/submit-training.sh" \
  --image nvcr.io/nvidia/isaac-lab:2.2.0 \
  --max-iterations 600 \
  --task Isaac-Velocity-Rough-Anymal-C-v0 \
  --register-checkpoint isaaclab-anymal-latest \
  --checkpoint-mode from-scratch \
  -- \
  "azure_client_id=00000000-0000-0000-0000-000000000000" \
  "azure_tenant_id=00000000-0000-0000-0000-000000000001" \
  "azure_subscription_id=00000000-0000-0000-0000-000000000002" \
  "azure_resource_group=rg-replace-me" \
  "azure_workspace_name=mlw-replace-me"
