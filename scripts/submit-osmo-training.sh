#!/usr/bin/env bash
#
# OSMO Training Workflow Submission Script
#
# Packages src/training/, encodes the archive, and submits an OSMO workflow
# using workflows/osmo/train.yaml as a template.
#
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")

# Source shared library for Terraform outputs
source "${SCRIPT_DIR}/lib/terraform-outputs.sh"

# Attempt to read Terraform outputs (non-fatal if missing)
read_terraform_outputs "${REPO_ROOT}/deploy/001-iac" 2>/dev/null || true

usage() {
  cat <<'EOF'
Usage: submit-osmo-training.sh [options] [-- osmo-submit-flags]

Packages src/training/, encodes the archive, and submits the inline workflow.

Options:
  -w, --workflow PATH     Path to workflow template YAML.
  -t, --task NAME         Isaac Lab task name override.
  -n, --num-envs COUNT    Number of environments override.
  -m, --max-iterations N  Maximum iteration override (blank to unset).
  -i, --image IMAGE       Container image override for the workflow.
  -p, --payload-root DIR  Runtime extraction root override.
  -c, --checkpoint-uri URI  MLflow checkpoint artifact URI to resume or warm-start from.
  -M, --checkpoint-mode MODE  Checkpoint mode (from-scratch, warm-start, resume, fresh).
  -r, --register-checkpoint NAME  Azure ML model name to register the final checkpoint under (default: derived from task).
      --skip-register-checkpoint  Skip automatic model registration.
      --sleep-after-unpack VALUE  Provide a non-empty value to sleep post-unpack (ex. 7200 to sleep 2 hours).
  -s, --run-smoke-test    Enable the Azure connectivity smoke test before training.
  -b, --backend BACKEND   Training backend: skrl (default), rsl_rl.

Azure context overrides (resolved from Terraform outputs if not provided):
      --azure-subscription-id ID    Azure subscription ID
      --azure-resource-group NAME   Azure resource group
      --azure-workspace-name NAME   Azure ML workspace name

General:
  -h, --help              Show this help message and exit.

Environment overrides:
  TASK, NUM_ENVS, MAX_ITERATIONS, IMAGE, PAYLOAD_ROOT, RUN_AZURE_SMOKE_TEST
  CHECKPOINT_URI, CHECKPOINT_MODE, REGISTER_CHECKPOINT, SLEEP_AFTER_UNPACK
  TRAINING_BACKEND, AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, AZUREML_WORKSPACE_NAME

Additional arguments after -- are forwarded to osmo workflow submit.

Values are resolved in order: CLI arguments > Environment variables > Terraform outputs
EOF
}

if ! command -v osmo >/dev/null 2>&1; then
  echo "osmo CLI is required on PATH" >&2
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "zip utility is required on PATH" >&2
  exit 1
fi

if ! command -v base64 >/dev/null 2>&1; then
  echo "base64 utility is required on PATH" >&2
  exit 1
fi

WORKFLOW_TEMPLATE=${WORKFLOW_TEMPLATE:-"$REPO_ROOT/workflows/osmo/train.yaml"}
TMP_DIR=${TMP_DIR:-"$SCRIPT_DIR/.tmp"}
ARCHIVE_PATH=${ARCHIVE_PATH:-"$TMP_DIR/osmo-training.zip"}
B64_PATH=${B64_PATH:-"$TMP_DIR/osmo-training.b64"}
TASK_VALUE=${TASK:-Isaac-Velocity-Rough-Anymal-C-v0}
NUM_ENVS_VALUE=${NUM_ENVS:-2048}
MAX_ITERATIONS_VALUE=${MAX_ITERATIONS:-}
IMAGE_VALUE=${IMAGE:-nvcr.io/nvidia/isaac-lab:2.2.0}
PAYLOAD_ROOT_VALUE=${PAYLOAD_ROOT:-/workspace/isaac_payload}
RUN_AZURE_SMOKE_TEST_VALUE=${RUN_AZURE_SMOKE_TEST:-0}
CHECKPOINT_URI_VALUE=${CHECKPOINT_URI:-}
CHECKPOINT_MODE_VALUE=${CHECKPOINT_MODE:-from-scratch}
REGISTER_CHECKPOINT_VALUE=${REGISTER_CHECKPOINT:-}
SLEEP_AFTER_UNPACK_VALUE=${SLEEP_AFTER_UNPACK:-}
BACKEND_VALUE=${TRAINING_BACKEND:-skrl}

# Three-tier value resolution: CLI > ENV > Terraform
AZURE_SUBSCRIPTION_ID_VALUE="${AZURE_SUBSCRIPTION_ID:-$(get_subscription_id)}"
AZURE_RESOURCE_GROUP_VALUE="${AZURE_RESOURCE_GROUP:-$(get_resource_group)}"
AZURE_WORKSPACE_NAME_VALUE="${AZUREML_WORKSPACE_NAME:-$(get_azureml_workspace)}"

normalize_checkpoint_mode() {
  local mode="$1"
  if [[ -z "$mode" ]]; then
    echo "from-scratch"
    return
  fi
  local lowered
  lowered=$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')
  case "$lowered" in
    from-scratch|warm-start|resume)
      echo "$lowered"
      ;;
    fresh)
      echo "from-scratch"
      ;;
    *)
      echo "Unsupported checkpoint mode: $mode" >&2
      exit 1
      ;;
  esac
}

derive_model_name_from_task() {
  local task="$1"
  # Convert task to model name: lowercase, replace non-alphanumeric with hyphens
  printf '%s' "$task" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

SKIP_REGISTER_CHECKPOINT=0

forward_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--workflow)
      WORKFLOW_TEMPLATE="$2"
      shift 2
      ;;
    -t|--task)
      TASK_VALUE="$2"
      shift 2
      ;;
    -n|--num-envs)
      NUM_ENVS_VALUE="$2"
      shift 2
      ;;
    -m|--max-iterations)
      MAX_ITERATIONS_VALUE="$2"
      shift 2
      ;;
    -i|--image)
      IMAGE_VALUE="$2"
      shift 2
      ;;
    -p|--payload-root)
      PAYLOAD_ROOT_VALUE="$2"
      shift 2
      ;;
    -c|--checkpoint-uri)
      CHECKPOINT_URI_VALUE="$2"
      shift 2
      ;;
    -M|--checkpoint-mode)
      CHECKPOINT_MODE_VALUE="$2"
      shift 2
      ;;
    -r|--register-checkpoint)
      REGISTER_CHECKPOINT_VALUE="$2"
      shift 2
      ;;
    --skip-register-checkpoint)
      SKIP_REGISTER_CHECKPOINT=1
      shift
      ;;
    -s|--run-smoke-test)
      RUN_AZURE_SMOKE_TEST_VALUE="1"
      shift
      ;;
    -b|--backend)
      BACKEND_VALUE="$2"
      shift 2
      ;;
    --sleep-after-unpack)
      SLEEP_AFTER_UNPACK_VALUE="$2"
      shift 2
      ;;
    --azure-subscription-id)
      AZURE_SUBSCRIPTION_ID_VALUE="$2"
      shift 2
      ;;
    --azure-resource-group)
      AZURE_RESOURCE_GROUP_VALUE="$2"
      shift 2
      ;;
    --azure-workspace-name)
      AZURE_WORKSPACE_NAME_VALUE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      forward_args+=("$@")
      break
      ;;
    *)
      forward_args+=("$1")
      shift
      ;;
  esac
done

CHECKPOINT_MODE_VALUE=$(normalize_checkpoint_mode "$CHECKPOINT_MODE_VALUE")

# Derive default model name from task if registration not skipped and no explicit name provided
if [[ $SKIP_REGISTER_CHECKPOINT -eq 0 ]] && [[ -z "$REGISTER_CHECKPOINT_VALUE" ]]; then
  REGISTER_CHECKPOINT_VALUE=$(derive_model_name_from_task "$TASK_VALUE")
  echo "Auto-derived model name: $REGISTER_CHECKPOINT_VALUE"
fi

# Clear register_checkpoint if skipped
if [[ $SKIP_REGISTER_CHECKPOINT -eq 1 ]]; then
  REGISTER_CHECKPOINT_VALUE=""
fi

if [[ ! -f "$WORKFLOW_TEMPLATE" ]]; then
  echo "Workflow template not found: $WORKFLOW_TEMPLATE" >&2
  exit 1
fi

if [[ ! -d "$REPO_ROOT/src/training" ]]; then
  echo "Directory src/training not found under $REPO_ROOT" >&2
  exit 1
fi

mkdir -p "$TMP_DIR"
rm -f "$ARCHIVE_PATH" "$B64_PATH"

pushd "$REPO_ROOT" >/dev/null
# Exclude __pycache__, .pyc files, and other build artifacts to reduce payload size
if ! zip -qr "$ARCHIVE_PATH" src/training \
  -x "**/__pycache__/*" \
  -x "*.pyc" \
  -x "*.pyo" \
  -x "**/.pytest_cache/*" \
  -x "**/.mypy_cache/*" \
  -x "**/*.egg-info/*"; then
  echo "Failed to create training archive" >&2
  popd >/dev/null
  exit 1
fi
popd >/dev/null

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Archive not created: $ARCHIVE_PATH" >&2
  exit 1
fi

if base64 --help 2>&1 | grep -q '\-\-input'; then
  base64 --input "$ARCHIVE_PATH" | tr -d '\n' > "$B64_PATH"
else
  base64 -i "$ARCHIVE_PATH" | tr -d '\n' > "$B64_PATH"
fi

if [[ ! -s "$B64_PATH" ]]; then
  echo "Failed to encode archive to base64" >&2
  exit 1
fi

ENCODED_PAYLOAD=$(cat "$B64_PATH")

submit_args=(
  workflow submit "$WORKFLOW_TEMPLATE"
  --set-string "image=$IMAGE_VALUE"
  "encoded_archive=$ENCODED_PAYLOAD"
  "task=$TASK_VALUE"
  "num_envs=$NUM_ENVS_VALUE"
  "payload_root=$PAYLOAD_ROOT_VALUE"
  "run_azure_smoke_test=$RUN_AZURE_SMOKE_TEST_VALUE"
  "checkpoint_uri=$CHECKPOINT_URI_VALUE"
  "checkpoint_mode=$CHECKPOINT_MODE_VALUE"
  "register_checkpoint=$REGISTER_CHECKPOINT_VALUE"
  "sleep_after_unpack=$SLEEP_AFTER_UNPACK_VALUE"
  "training_backend=$BACKEND_VALUE"
)

# Add Azure context from Terraform outputs
if [[ -n "$AZURE_SUBSCRIPTION_ID_VALUE" ]]; then
  submit_args+=("azure_subscription_id=$AZURE_SUBSCRIPTION_ID_VALUE")
fi
if [[ -n "$AZURE_RESOURCE_GROUP_VALUE" ]]; then
  submit_args+=("azure_resource_group=$AZURE_RESOURCE_GROUP_VALUE")
fi
if [[ -n "$AZURE_WORKSPACE_NAME_VALUE" ]]; then
  submit_args+=("azure_workspace_name=$AZURE_WORKSPACE_NAME_VALUE")
fi

if [[ -n "$MAX_ITERATIONS_VALUE" ]]; then
  submit_args+=("max_iterations=$MAX_ITERATIONS_VALUE")
else
  submit_args+=("max_iterations=")
fi

if [[ ${#forward_args[@]} -gt 0 ]]; then
  submit_args+=("${forward_args[@]}")
fi

echo "Submitting workflow to OSMO..."
if ! osmo "${submit_args[@]}"; then
  echo "Failed to submit workflow to OSMO" >&2
  exit 1
fi

echo "Workflow submitted successfully"
