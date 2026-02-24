#!/usr/bin/env bash
# Submit LeRobot behavioral cloning training to Azure ML
# Supports ACT and Diffusion policy architectures with Azure ML MLflow logging
set -o errexit -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")"

# shellcheck source=../deploy/002-setup/lib/common.sh
source "$REPO_ROOT/deploy/002-setup/lib/common.sh"
# shellcheck source=lib/terraform-outputs.sh
source "$SCRIPT_DIR/lib/terraform-outputs.sh"
read_terraform_outputs "$REPO_ROOT/deploy/001-iac" 2>/dev/null || true

# Source .env file if present (for credentials and Azure context)
for env_candidate in "${SCRIPT_DIR}/.env" "${REPO_ROOT}/.env"; do
  if [[ -f "${env_candidate}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_candidate}"
    set +a
    break
  fi
done

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

show_help() {
  cat << 'EOF'
Usage: submit-azureml-lerobot-training.sh [OPTIONS] [-- az-ml-job-flags]

Submit LeRobot behavioral cloning training to Azure ML.
Supports ACT and Diffusion policy architectures with Azure ML MLflow logging.

REQUIRED:
    -d, --dataset-repo-id ID     HuggingFace dataset repository (e.g., user/dataset)

DATA SOURCE:
        --from-blob               Use Azure Blob Storage as data source
        --storage-account NAME    Azure Storage account name
        --storage-container NAME  Blob container name (default: datasets)
        --blob-prefix PREFIX      Blob path prefix for dataset

AZUREML ASSET OPTIONS:
    --environment-name NAME       AzureML environment name (default: lerobot-training-env)
    --environment-version VER     Environment version (default: 1.0.0)
    --image IMAGE                 Container image (default: pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime)
    --assets-only                 Register environment without submitting job

TRAINING OPTIONS:
    -w, --job-file PATH           Job YAML template (default: workflows/azureml/lerobot-train.yaml)
    -p, --policy-type TYPE        Policy architecture: act, diffusion (default: act)
    -j, --job-name NAME           Job identifier (default: lerobot-act-training)
    -o, --output-dir DIR          Container output directory (default: /workspace/outputs/train)
        --policy-repo-id ID       Pre-trained policy for fine-tuning (HuggingFace repo)
        --lerobot-version VER     Specific LeRobot version or "latest" (default: latest)

TRAINING HYPERPARAMETERS:
        --training-steps N        Total training iterations (default: 100000)
        --batch-size N            Training batch size (default: 32)
        --learning-rate LR        Optimizer learning rate (default: 1e-4)
        --lr-warmup-steps N       Learning rate warmup steps (default: 1000)
        --eval-freq N             Evaluation frequency
        --save-freq N             Checkpoint save frequency (default: 5000)

VALIDATION:
        --val-split RATIO         Validation split ratio (default: 0.1 = 10%%)
        --no-val-split            Disable train/val splitting

LOGGING:
        --experiment-name NAME    MLflow experiment name
        --no-system-metrics       Disable GPU/CPU/memory metrics logging

CHECKPOINT REGISTRATION:
    -r, --register-checkpoint NAME  Model name for Azure ML registration

AZURE CONTEXT:
        --subscription-id ID      Azure subscription ID
        --resource-group NAME     Azure resource group
        --workspace-name NAME     Azure ML workspace
        --compute TARGET          Compute target override
        --instance-type NAME      Instance type (default: gpuspot)
        --display-name NAME       Display name override
        --stream                  Stream logs after submission

ADVANCED:
        --mlflow-token-retries N  MLflow token refresh retries (default: 3)
        --mlflow-http-timeout N   MLflow HTTP request timeout in seconds (default: 60)

GENERAL:
    -h, --help                    Show this help message

Values resolved: CLI > Environment variables > Terraform outputs
Additional arguments after -- are forwarded to az ml job create.

EXAMPLES:
    # ACT training with MLflow logging (defaults)
    submit-azureml-lerobot-training.sh -d lerobot/aloha_sim_insertion_human

    # Diffusion policy with custom learning rate
    submit-azureml-lerobot-training.sh \
      -d user/custom-dataset \
      -p diffusion \
      --learning-rate 5e-5 \
      -r my-diffusion-model

    # Train from Azure Blob Storage without validation split
    submit-azureml-lerobot-training.sh \
      -d hve-robo/hve-robo-cell \
      --from-blob \
      --storage-account stosmorbt3dev001 \
      --blob-prefix hve-robo/hve-robo-cell \
      --no-val-split \
      -r my-act-model

    # Register environment only (no job submission)
    submit-azureml-lerobot-training.sh -d placeholder --assets-only
EOF
}

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------

ensure_ml_extension() {
  az extension show --name ml &>/dev/null ||
    fatal "Azure ML CLI extension not installed. Run: az extension add --name ml"
}

register_environment() {
  local name="$1" version="$2" image="$3" rg="$4" ws="$5" sub="$6"
  local env_file
  env_file=$(mktemp)

  cat >"$env_file" <<EOF
\$schema: https://azuremlschemas.azureedge.net/latest/environment.schema.json
name: $name
version: $version
image: $image
EOF

  info "Publishing AzureML environment ${name}:${version}"
  az ml environment create --file "$env_file" \
    --name "$name" --version "$version" \
    --resource-group "$rg" --workspace-name "$ws" \
    --subscription "$sub" >/dev/null 2>&1 || \
    warn "Environment ${name}:${version} already exists or registration failed; continuing"
  rm -f "$env_file"
}

#------------------------------------------------------------------------------
# Defaults
#------------------------------------------------------------------------------

environment_name="lerobot-training-env"
environment_version="1.0.0"
image="${IMAGE:-pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime}"
assets_only=false

job_file="$REPO_ROOT/workflows/azureml/lerobot-train.yaml"
dataset_repo_id="${DATASET_REPO_ID:-}"
policy_type="${POLICY_TYPE:-act}"
job_name="${JOB_NAME:-lerobot-act-training}"
output_dir="${OUTPUT_DIR:-/workspace/outputs/train}"
policy_repo_id="${POLICY_REPO_ID:-}"
lerobot_version="${LEROBOT_VERSION:-}"

from_blob=false
storage_account="${BLOB_STORAGE_ACCOUNT:-${AZURE_STORAGE_ACCOUNT_NAME:-}}"
storage_container="${BLOB_STORAGE_CONTAINER:-datasets}"
blob_prefix="${BLOB_PREFIX:-}"

training_steps="${TRAINING_STEPS:-100000}"
batch_size="${BATCH_SIZE:-32}"
learning_rate="${LEARNING_RATE:-1e-4}"
lr_warmup_steps="${LR_WARMUP_STEPS:-1000}"
eval_freq="${EVAL_FREQ:-}"
save_freq="${SAVE_FREQ:-5000}"

val_split="${VAL_SPLIT:-0.1}"
val_split_enabled=true
system_metrics="${SYSTEM_METRICS:-true}"

experiment_name="${EXPERIMENT_NAME:-}"
register_checkpoint="${REGISTER_CHECKPOINT:-}"

subscription_id="${AZURE_SUBSCRIPTION_ID:-$(get_subscription_id)}"
resource_group="${AZURE_RESOURCE_GROUP:-$(get_resource_group)}"
workspace_name="${AZUREML_WORKSPACE_NAME:-$(get_azureml_workspace)}"
mlflow_retries="${MLFLOW_TRACKING_TOKEN_REFRESH_RETRIES:-3}"
mlflow_timeout="${MLFLOW_HTTP_REQUEST_TIMEOUT:-60}"

compute="${AZUREML_COMPUTE:-$(get_compute_target)}"
instance_type="gpuspot"
display_name=""
stream_logs=false
forward_args=()

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)                    show_help; exit 0 ;;
    --environment-name)           environment_name="$2"; shift 2 ;;
    --environment-version)        environment_version="$2"; shift 2 ;;
    --image|-i)                   image="$2"; shift 2 ;;
    --assets-only)                assets_only=true; shift ;;
    -w|--job-file)                job_file="$2"; shift 2 ;;
    -d|--dataset-repo-id)         dataset_repo_id="$2"; shift 2 ;;
    -p|--policy-type)             policy_type="$2"; shift 2 ;;
    -j|--job-name)                job_name="$2"; shift 2 ;;
    -o|--output-dir)              output_dir="$2"; shift 2 ;;
    --policy-repo-id)             policy_repo_id="$2"; shift 2 ;;
    --lerobot-version)            lerobot_version="$2"; shift 2 ;;
    --from-blob)                  from_blob=true; shift ;;
    --storage-account)            storage_account="$2"; shift 2 ;;
    --storage-container)          storage_container="$2"; shift 2 ;;
    --blob-prefix)                blob_prefix="$2"; shift 2 ;;
    --training-steps)             training_steps="$2"; shift 2 ;;
    --batch-size)                 batch_size="$2"; shift 2 ;;
    --learning-rate)              learning_rate="$2"; shift 2 ;;
    --lr-warmup-steps)            lr_warmup_steps="$2"; shift 2 ;;
    --eval-freq)                  eval_freq="$2"; shift 2 ;;
    --save-freq)                  save_freq="$2"; shift 2 ;;
    --val-split)                  val_split="$2"; shift 2 ;;
    --no-val-split)               val_split_enabled=false; shift ;;
    --no-system-metrics)          system_metrics="false"; shift ;;
    --experiment-name)            experiment_name="$2"; shift 2 ;;
    -r|--register-checkpoint)     register_checkpoint="$2"; shift 2 ;;
    --subscription-id)            subscription_id="$2"; shift 2 ;;
    --resource-group)             resource_group="$2"; shift 2 ;;
    --workspace-name)             workspace_name="$2"; shift 2 ;;
    --mlflow-token-retries)       mlflow_retries="$2"; shift 2 ;;
    --mlflow-http-timeout)        mlflow_timeout="$2"; shift 2 ;;
    --compute)                    compute="$2"; shift 2 ;;
    --instance-type)              instance_type="$2"; shift 2 ;;
    --display-name)               display_name="$2"; shift 2 ;;
    --stream)                     stream_logs=true; shift ;;
    --)                           shift; forward_args=("$@"); break ;;
    *)                            fatal "Unknown option: $1" ;;
  esac
done

#------------------------------------------------------------------------------
# Validation
#------------------------------------------------------------------------------

require_tools az zip base64
ensure_ml_extension

[[ -z "$dataset_repo_id" ]] && fatal "--dataset-repo-id is required"
[[ -d "$REPO_ROOT/src/training" ]] || fatal "Directory src/training not found"

if [[ "$from_blob" == "true" ]]; then
  [[ -z "$storage_account" ]] && fatal "--storage-account is required with --from-blob"
  [[ -z "$blob_prefix" ]] && blob_prefix="$dataset_repo_id"
fi

[[ -n "$subscription_id" ]] || fatal "AZURE_SUBSCRIPTION_ID required"
[[ -n "$resource_group" ]] || fatal "AZURE_RESOURCE_GROUP required"
[[ -n "$workspace_name" ]] || fatal "AZUREML_WORKSPACE_NAME required"

case "$policy_type" in
  act|diffusion) ;;
  *) fatal "Unsupported policy type: $policy_type (use: act, diffusion)" ;;
esac

[[ "$val_split_enabled" == "false" ]] && val_split="0"

#------------------------------------------------------------------------------
# Register Environment
#------------------------------------------------------------------------------

register_environment "$environment_name" "$environment_version" "$image" \
  "$resource_group" "$workspace_name" "$subscription_id"

info "Environment: ${environment_name}:${environment_version}"

if [[ "$assets_only" == "true" ]]; then
  info "Assets prepared; skipping job submission per --assets-only"
  exit 0
fi

#------------------------------------------------------------------------------
# Pre-submission Checks
#------------------------------------------------------------------------------

[[ -f "$job_file" ]] || fatal "Job file not found: $job_file"

#------------------------------------------------------------------------------
# Package Training Payload
#------------------------------------------------------------------------------

TMP_DIR="$SCRIPT_DIR/.tmp"
ARCHIVE_PATH="$TMP_DIR/azureml-lerobot-training.zip"
B64_PATH="$TMP_DIR/azureml-lerobot-training.b64"
payload_root="${PAYLOAD_ROOT:-/workspace/lerobot_payload}"

info "Packaging training payload..."
mkdir -p "$TMP_DIR"
rm -f "$ARCHIVE_PATH" "$B64_PATH"

(cd "$REPO_ROOT" && zip -qr "$ARCHIVE_PATH" src/training src/common \
  -x "**/__pycache__/*" \
  -x "*.pyc" \
  -x "*.pyo" \
  -x "**/.pytest_cache/*" \
  -x "**/.mypy_cache/*" \
  -x "**/*.egg-info/*") || fatal "Failed to create training archive"

[[ -f "$ARCHIVE_PATH" ]] || fatal "Archive not created: $ARCHIVE_PATH"

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

az_args=(
  az ml job create
  --resource-group "$resource_group"
  --workspace-name "$workspace_name"
  --file "$job_file"
  --set "environment=azureml:${environment_name}:${environment_version}"
)

[[ -n "$compute" ]] && az_args+=(--set "compute=$compute")
[[ -n "$instance_type" ]] && az_args+=(--set "resources.instance_type=$instance_type")
[[ -n "$experiment_name" ]] && az_args+=(--set "experiment_name=$experiment_name")
[[ -n "$display_name" ]] && az_args+=(--set "display_name=$display_name")

# Environment variables for the training orchestrator
az_args+=(
  --set "environment_variables.DATASET_REPO_ID=$dataset_repo_id"
  --set "environment_variables.POLICY_TYPE=$policy_type"
  --set "environment_variables.JOB_NAME=$job_name"
  --set "environment_variables.OUTPUT_DIR=$output_dir"
  --set "environment_variables.TRAINING_STEPS=$training_steps"
  --set "environment_variables.BATCH_SIZE=$batch_size"
  --set "environment_variables.LEARNING_RATE=$learning_rate"
  --set "environment_variables.LR_WARMUP_STEPS=$lr_warmup_steps"
  --set "environment_variables.SAVE_FREQ=$save_freq"
  --set "environment_variables.VAL_SPLIT=$val_split"
  --set "environment_variables.SYSTEM_METRICS=$system_metrics"
  --set "environment_variables.AZURE_SUBSCRIPTION_ID=$subscription_id"
  --set "environment_variables.AZURE_RESOURCE_GROUP=$resource_group"
  --set "environment_variables.AZUREML_WORKSPACE_NAME=$workspace_name"
  --set "environment_variables.MLFLOW_TRACKING_TOKEN_REFRESH_RETRIES=$mlflow_retries"
  --set "environment_variables.MLFLOW_HTTP_REQUEST_TIMEOUT=$mlflow_timeout"
  --set "environment_variables.ENCODED_ARCHIVE=$encoded_payload"
  --set "environment_variables.PAYLOAD_ROOT=$payload_root"
  --set "environment_variables.DATASET_ROOT=/workspace/data"
  --set "environment_variables.STORAGE_ACCOUNT=$storage_account"
  --set "environment_variables.STORAGE_CONTAINER=$storage_container"
  --set "environment_variables.BLOB_PREFIX=$blob_prefix"
)

[[ -n "$policy_repo_id" ]]      && az_args+=(--set "environment_variables.POLICY_REPO_ID=$policy_repo_id")
[[ -n "$lerobot_version" ]]     && az_args+=(--set "environment_variables.LEROBOT_VERSION=$lerobot_version")
[[ -n "$eval_freq" ]]           && az_args+=(--set "environment_variables.EVAL_FREQ=$eval_freq")
[[ -n "$experiment_name" ]]     && az_args+=(--set "environment_variables.EXPERIMENT_NAME=$experiment_name")
[[ -n "$register_checkpoint" ]] && az_args+=(--set "environment_variables.REGISTER_CHECKPOINT=$register_checkpoint")

[[ ${#forward_args[@]} -gt 0 ]] && az_args+=("${forward_args[@]}")
az_args+=(--query "name" -o "tsv")

#------------------------------------------------------------------------------
# Submit Job
#------------------------------------------------------------------------------

info "Submitting AzureML LeRobot training job..."
info "  Dataset: $dataset_repo_id"
info "  Policy: $policy_type"
info "  Job Name: $job_name"
info "  Image: $image"
info "  Logging: Azure MLflow"
info "  Training Steps: $training_steps"
info "  Batch Size: $batch_size"
info "  Learning Rate: $learning_rate"
info "  Val Split: $val_split"
info "  System Metrics: $system_metrics"
info "  Payload: ${archive_size} bytes"
[[ "$from_blob" == "true" ]] && info "  Data Source: Azure Blob ($storage_account/$storage_container/$blob_prefix)"
[[ -n "$policy_repo_id" ]] && info "  Fine-tune from: $policy_repo_id"
[[ -n "$register_checkpoint" ]] && info "  Register model: $register_checkpoint"

job_result=$("${az_args[@]}") || fatal "Job submission failed"

info "Job submitted: $job_result"
info "Portal: https://ml.azure.com/runs/$job_result?wsid=/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.MachineLearningServices/workspaces/$workspace_name"

if [[ "$stream_logs" == "true" ]]; then
  info "Streaming job logs (Ctrl+C to stop)..."
  az ml job stream --name "$job_result" \
    --resource-group "$resource_group" --workspace-name "$workspace_name" || true
fi
