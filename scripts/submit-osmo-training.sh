#!/usr/bin/env bash
# Submit OSMO training workflow with src/training/ packaged as base64 payload
# Excludes __pycache__ and build artifacts to reduce payload size
set -o errexit -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/deploy/002-setup/lib/common.sh"
source "$SCRIPT_DIR/lib/terraform-outputs.sh"
read_terraform_outputs "$REPO_ROOT/deploy/001-iac" 2>/dev/null || true

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

show_help() {
  cat << 'EOF'
Usage: submit-osmo-training.sh [OPTIONS] [-- osmo-submit-flags]

Package src/training/, encode as base64, and submit an OSMO workflow.

WORKFLOW OPTIONS:
    -w, --workflow PATH           Workflow template (default: workflows/osmo/train.yaml)
    -t, --task NAME               IsaacLab task (default: Isaac-Velocity-Rough-Anymal-C-v0)
    -n, --num-envs COUNT          Number of environments (default: 2048)
    -m, --max-iterations N        Maximum iterations (empty to unset)
    -i, --image IMAGE             Container image (default: nvcr.io/nvidia/isaac-lab:2.2.0)
    -p, --payload-root DIR        Runtime extraction root (default: /workspace/isaac_payload)
    -b, --backend BACKEND         Training backend: skrl (default), rsl_rl

CHECKPOINT OPTIONS:
    -c, --checkpoint-uri URI      MLflow checkpoint artifact URI
    -M, --checkpoint-mode MODE    from-scratch, warm-start, resume, fresh (default: from-scratch)
    -r, --register-checkpoint NAME  Model name for checkpoint registration
        --skip-register-checkpoint  Skip automatic model registration

AZURE CONTEXT:
        --azure-subscription-id ID    Azure subscription ID
        --azure-resource-group NAME   Azure resource group
        --azure-workspace-name NAME   Azure ML workspace

OTHER:
        --sleep-after-unpack VALUE  Sleep seconds post-unpack (for debugging)
    -s, --run-smoke-test          Enable Azure connectivity smoke test
    -h, --help                    Show this help message

Values resolved: CLI > Environment variables > Terraform outputs
Additional arguments after -- are forwarded to osmo workflow submit.
EOF
}

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------

derive_model_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

normalize_checkpoint_mode() {
  local mode="$1"
  [[ -z "$mode" ]] && { echo "from-scratch"; return; }
  lowered=$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')
  case "$lowered" in
    from-scratch|warm-start|resume) echo "$lowered" ;;
    fresh) echo "from-scratch" ;;
    *) fatal "Unsupported checkpoint mode: $mode" ;;
  esac
}

#------------------------------------------------------------------------------
# Defaults
#------------------------------------------------------------------------------

TMP_DIR="$SCRIPT_DIR/.tmp"
ARCHIVE_PATH="$TMP_DIR/osmo-training.zip"
B64_PATH="$TMP_DIR/osmo-training.b64"

workflow="$REPO_ROOT/workflows/osmo/train.yaml"
task="${TASK:-Isaac-Velocity-Rough-Anymal-C-v0}"
num_envs="${NUM_ENVS:-2048}"
max_iterations="${MAX_ITERATIONS:-}"
image="${IMAGE:-nvcr.io/nvidia/isaac-lab:2.2.0}"
payload_root="${PAYLOAD_ROOT:-/workspace/isaac_payload}"
backend="${TRAINING_BACKEND:-skrl}"

checkpoint_uri="${CHECKPOINT_URI:-}"
checkpoint_mode="${CHECKPOINT_MODE:-from-scratch}"
register_checkpoint="${REGISTER_CHECKPOINT:-}"
skip_register=false

subscription_id="${AZURE_SUBSCRIPTION_ID:-$(get_subscription_id)}"
resource_group="${AZURE_RESOURCE_GROUP:-$(get_resource_group)}"
workspace_name="${AZUREML_WORKSPACE_NAME:-$(get_azureml_workspace)}"

sleep_after_unpack="${SLEEP_AFTER_UNPACK:-}"
run_smoke="${RUN_AZURE_SMOKE_TEST:-0}"
forward_args=()

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)                    show_help; exit 0 ;;
    -w|--workflow)                workflow="$2"; shift 2 ;;
    -t|--task)                    task="$2"; shift 2 ;;
    -n|--num-envs)                num_envs="$2"; shift 2 ;;
    -m|--max-iterations)          max_iterations="$2"; shift 2 ;;
    -i|--image)                   image="$2"; shift 2 ;;
    -p|--payload-root)            payload_root="$2"; shift 2 ;;
    -b|--backend)                 backend="$2"; shift 2 ;;
    -c|--checkpoint-uri)          checkpoint_uri="$2"; shift 2 ;;
    -M|--checkpoint-mode)         checkpoint_mode="$2"; shift 2 ;;
    -r|--register-checkpoint)     register_checkpoint="$2"; shift 2 ;;
    --skip-register-checkpoint)   skip_register=true; shift ;;
    --azure-subscription-id)      subscription_id="$2"; shift 2 ;;
    --azure-resource-group)       resource_group="$2"; shift 2 ;;
    --azure-workspace-name)       workspace_name="$2"; shift 2 ;;
    --sleep-after-unpack)         sleep_after_unpack="$2"; shift 2 ;;
    -s|--run-smoke-test)          run_smoke="1"; shift ;;
    --)                           shift; forward_args=("$@"); break ;;
    *)                            forward_args+=("$1"); shift ;;
  esac
done

#------------------------------------------------------------------------------
# Validation
#------------------------------------------------------------------------------

require_tools osmo zip base64

[[ -f "$workflow" ]] || fatal "Workflow template not found: $workflow"
[[ -d "$REPO_ROOT/src/training" ]] || fatal "Directory src/training not found"

checkpoint_mode="$(normalize_checkpoint_mode "$checkpoint_mode")"

if [[ "$skip_register" == "false" && -z "$register_checkpoint" ]]; then
  register_checkpoint="$(derive_model_name "$task")"
  info "Auto-derived model name: $register_checkpoint"
fi

[[ "$skip_register" == "true" ]] && register_checkpoint=""

#------------------------------------------------------------------------------
# Package Training Payload
#------------------------------------------------------------------------------

info "Packaging training payload..."
mkdir -p "$TMP_DIR"
rm -f "$ARCHIVE_PATH" "$B64_PATH"

# Exclude __pycache__, .pyc, and build artifacts to reduce payload size
(cd "$REPO_ROOT" && zip -qr "$ARCHIVE_PATH" src/training \
  -x "**/__pycache__/*" \
  -x "*.pyc" \
  -x "*.pyo" \
  -x "**/.pytest_cache/*" \
  -x "**/.mypy_cache/*" \
  -x "**/*.egg-info/*") || fatal "Failed to create training archive"

[[ -f "$ARCHIVE_PATH" ]] || fatal "Archive not created: $ARCHIVE_PATH"

# Base64 encode (macOS vs Linux compatible)
if base64 --help 2>&1 | grep -q '\-\-input'; then
  base64 --input "$ARCHIVE_PATH" | tr -d '\n' > "$B64_PATH"
else
  base64 -i "$ARCHIVE_PATH" | tr -d '\n' > "$B64_PATH"
fi

[[ -s "$B64_PATH" ]] || fatal "Failed to encode archive"

archive_size=$(wc -c < "$ARCHIVE_PATH" | tr -d ' ')
b64_size=$(wc -c < "$B64_PATH" | tr -d ' ')
info "Payload: ${archive_size} bytes (${b64_size} bytes base64)"

encoded_payload=$(<"$B64_PATH")

#------------------------------------------------------------------------------
# Build Submission Command
#------------------------------------------------------------------------------

submit_args=(
  workflow submit "$workflow"
  --set-string "image=$image"
  "encoded_archive=$encoded_payload"
  "task=$task"
  "num_envs=$num_envs"
  "payload_root=$payload_root"
  "run_azure_smoke_test=$run_smoke"
  "checkpoint_uri=$checkpoint_uri"
  "checkpoint_mode=$checkpoint_mode"
  "register_checkpoint=$register_checkpoint"
  "sleep_after_unpack=$sleep_after_unpack"
  "training_backend=$backend"
)

[[ -n "$subscription_id" ]] && submit_args+=("azure_subscription_id=$subscription_id")
[[ -n "$resource_group" ]] && submit_args+=("azure_resource_group=$resource_group")
[[ -n "$workspace_name" ]] && submit_args+=("azure_workspace_name=$workspace_name")

if [[ -n "$max_iterations" ]]; then
  submit_args+=("max_iterations=$max_iterations")
else
  submit_args+=("max_iterations=")
fi

[[ ${#forward_args[@]} -gt 0 ]] && submit_args+=("${forward_args[@]}")

#------------------------------------------------------------------------------
# Submit Workflow
#------------------------------------------------------------------------------

info "Submitting workflow to OSMO..."
info "  Task: $task"
info "  Backend: $backend"
info "  Image: $image"

osmo "${submit_args[@]}" || fatal "Failed to submit workflow"

info "Workflow submitted successfully"
