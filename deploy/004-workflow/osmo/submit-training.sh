#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: submit-training.sh [options] [-- osmo-submit-flags]

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
  -r, --register-checkpoint NAME  Azure ML model name to register the final checkpoint under.
      --sleep-after-unpack VALUE  Provide a non-empty value to sleep post-unpack (ex. 7200 to sleep 2 hours).
      --azure-client-id VALUE       Azure Client ID to inject into the workflow.
      --azure-tenant-id VALUE       Azure Tenant ID to inject into the workflow.
      --azure-subscription-id VALUE Azure subscription ID for the workspace.
      --azure-resource-group VALUE  Azure resource group for the workspace.
      --azure-workspace-name VALUE  Azure ML workspace name override.
      --azure-authority-host VALUE  Azure authority host for the identity endpoint.
      --azure-federated-token-file PATH  Path to the federated token file inside the pod.
      --mlflow-token-refresh-retries COUNT  MLflow token refresh retry count.
      --mlflow-http-request-timeout SECONDS MLflow HTTP timeout in seconds.
      --python CMD                  Override python launcher prefix (applied to workflow template).
  -s, --run-smoke-test    Enable the Azure connectivity smoke test before training.
  -h, --help              Show this help message and exit.

Environment overrides:
  TASK, NUM_ENVS, MAX_ITERATIONS, IMAGE, PAYLOAD_ROOT, RUN_AZURE_SMOKE_TEST
  CHECKPOINT_URI, CHECKPOINT_MODE, REGISTER_CHECKPOINT, SLEEP_AFTER_UNPACK, TRAINING_BACKEND
  AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP,
  AZURE_WORKSPACE_NAME, AZURE_AUTHORITY_HOST, AZURE_FEDERATED_TOKEN_FILE,
  MLFLOW_TOKEN_REFRESH_RETRIES, MLFLOW_HTTP_REQUEST_TIMEOUT, PYTHON_OVERRIDE

Additional arguments after -- are forwarded to osmo workflow submit.
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

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "${REPO_ROOT}" ]]; then
  echo "Run inside the repository working tree" >&2
  exit 1
fi

WORKFLOW_TEMPLATE=${WORKFLOW_TEMPLATE:-"$REPO_ROOT/deploy/004-workflow/osmo/templates/isaaclab-inline.yaml"}
TMP_DIR=${TMP_DIR:-"$REPO_ROOT/deploy/004-workflow/osmo/.tmp"}
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
TRAINING_BACKEND_VALUE=${TRAINING_BACKEND:-skrl}
AZURE_CLIENT_ID_VALUE=${AZURE_CLIENT_ID:-}
AZURE_TENANT_ID_VALUE=${AZURE_TENANT_ID:-}
AZURE_SUBSCRIPTION_ID_VALUE=${AZURE_SUBSCRIPTION_ID:-}
AZURE_RESOURCE_GROUP_VALUE=${AZURE_RESOURCE_GROUP:-}
AZURE_WORKSPACE_NAME_VALUE=${AZURE_WORKSPACE_NAME:-}
AZURE_AUTHORITY_HOST_VALUE=${AZURE_AUTHORITY_HOST:-https://login.microsoftonline.com}
AZURE_FEDERATED_TOKEN_FILE_VALUE=${AZURE_FEDERATED_TOKEN_FILE:-/var/run/secrets/azure/tokens/azure-identity-token}
MLFLOW_TOKEN_REFRESH_RETRIES_VALUE=${MLFLOW_TOKEN_REFRESH_RETRIES:-3}
MLFLOW_HTTP_REQUEST_TIMEOUT_VALUE=${MLFLOW_HTTP_REQUEST_TIMEOUT:-60}
PYTHON_VALUE=${PYTHON_OVERRIDE:-${PYTHON:-}}

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
    -s|--run-smoke-test)
      RUN_AZURE_SMOKE_TEST_VALUE="1"
      shift
      ;;
    --sleep-after-unpack)
      SLEEP_AFTER_UNPACK_VALUE="$2"
      shift 2
      ;;
    -B|--training-backend)
      TRAINING_BACKEND_VALUE="$2"
      shift 2
      ;;
    --azure-client-id)
      AZURE_CLIENT_ID_VALUE="$2"
      shift 2
      ;;
    --azure-tenant-id)
      AZURE_TENANT_ID_VALUE="$2"
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
    --azure-authority-host)
      AZURE_AUTHORITY_HOST_VALUE="$2"
      shift 2
      ;;
    --azure-federated-token-file)
      AZURE_FEDERATED_TOKEN_FILE_VALUE="$2"
      shift 2
      ;;
    --mlflow-token-refresh-retries)
      MLFLOW_TOKEN_REFRESH_RETRIES_VALUE="$2"
      shift 2
      ;;
    --mlflow-http-request-timeout)
      MLFLOW_HTTP_REQUEST_TIMEOUT_VALUE="$2"
      shift 2
      ;;
    --python)
      PYTHON_VALUE="$2"
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
if ! zip -qr "$ARCHIVE_PATH" src/training; then
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
  --set-string
  "image=$IMAGE_VALUE"
  "encoded_archive=$ENCODED_PAYLOAD"
  "task=$TASK_VALUE"
  "num_envs=$NUM_ENVS_VALUE"
  "payload_root=$PAYLOAD_ROOT_VALUE"
  "run_azure_smoke_test=$RUN_AZURE_SMOKE_TEST_VALUE"
  "checkpoint_uri=$CHECKPOINT_URI_VALUE"
  "checkpoint_mode=$CHECKPOINT_MODE_VALUE"
  "register_checkpoint=$REGISTER_CHECKPOINT_VALUE"
  "sleep_after_unpack=$SLEEP_AFTER_UNPACK_VALUE"
  "training_backend=$TRAINING_BACKEND_VALUE"
  "azure_client_id=$AZURE_CLIENT_ID_VALUE"
  "azure_tenant_id=$AZURE_TENANT_ID_VALUE"
  "azure_subscription_id=$AZURE_SUBSCRIPTION_ID_VALUE"
  "azure_resource_group=$AZURE_RESOURCE_GROUP_VALUE"
  "azure_workspace_name=$AZURE_WORKSPACE_NAME_VALUE"
  "azure_authority_host=$AZURE_AUTHORITY_HOST_VALUE"
  "azure_federated_token_file=$AZURE_FEDERATED_TOKEN_FILE_VALUE"
  "mlflow_token_refresh_retries=$MLFLOW_TOKEN_REFRESH_RETRIES_VALUE"
  "mlflow_http_request_timeout=$MLFLOW_HTTP_REQUEST_TIMEOUT_VALUE"
)

if [[ -n "$PYTHON_VALUE" ]]; then
  submit_args+=("python=$PYTHON_VALUE")
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
