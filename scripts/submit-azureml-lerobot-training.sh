#!/usr/bin/env bash
# Submit LeRobot behavioral cloning training to Azure ML
# Reuses src/training Python orchestrator for Azure ML MLflow logging (no wandb)
set -o errexit -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")"

# shellcheck source=../deploy/002-setup/lib/common.sh
source "$REPO_ROOT/deploy/002-setup/lib/common.sh"
# shellcheck source=lib/terraform-outputs.sh
source "$SCRIPT_DIR/lib/terraform-outputs.sh"
read_terraform_outputs "$REPO_ROOT/deploy/001-iac" 2>/dev/null || true

# Source .env file if present (for credentials and Azure context)
ENV_FILE="${SCRIPT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

show_help() {
  cat << 'EOF'
Usage: submit-azureml-lerobot-training.sh [OPTIONS] [-- az-ml-job-flags]

Submit LeRobot behavioral cloning training to Azure ML.
Uses Azure ML MLflow for logging (same orchestrator as OSMO workflow).

REQUIRED:
    -d, --dataset-repo-id ID     HuggingFace dataset repository (e.g., user/dataset)

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
    # ACT training with defaults
    submit-azureml-lerobot-training.sh -d lerobot/aloha_sim_insertion_human

    # Diffusion policy with custom hyperparameters
    submit-azureml-lerobot-training.sh \
      -d user/custom-dataset \
      -p diffusion \
      --training-steps 50000 \
      --batch-size 16

    # Register trained model and stream logs
    submit-azureml-lerobot-training.sh \
      -d user/dataset \
      -r my-act-model \
      --stream

    # Fine-tune from pre-trained policy
    submit-azureml-lerobot-training.sh \
      -d user/dataset \
      --policy-repo-id user/pretrained-act \
      --training-steps 10000

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

require_tools az
ensure_ml_extension

[[ -z "$dataset_repo_id" ]] && fatal "--dataset-repo-id is required"
[[ -n "$subscription_id" ]] || fatal "AZURE_SUBSCRIPTION_ID required"
[[ -n "$resource_group" ]] || fatal "AZURE_RESOURCE_GROUP required"
[[ -n "$workspace_name" ]] || fatal "AZUREML_WORKSPACE_NAME required"
[[ -n "$compute" ]] || fatal "Compute target required (set AZUREML_COMPUTE or ensure Terraform outputs are available)"
[[ -d "$REPO_ROOT/src/training" ]] || fatal "Directory src/training not found"

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
# Build Training Command
#
# Mirrors the OSMO workflow entry script:
# 1. Installs system dependencies and LeRobot via uv
# 2. Sets PYTHONPATH to include code snapshot (src/training, src/common)
# 3. Runs training via Python orchestrator with Azure ML MLflow logging
# 4. Registers checkpoints to Azure ML model registry
#------------------------------------------------------------------------------

train_cmd='bash -c '"'"'
set -euo pipefail

echo "=== LeRobot AzureML Training ==="
echo "Dataset: ${DATASET_REPO_ID}"
echo "Policy Type: ${POLICY_TYPE}"
echo "Job Name: ${JOB_NAME}"
echo "Output Dir: ${OUTPUT_DIR}"
echo "Logging: Azure ML MLflow"
echo "Val Split: ${VAL_SPLIT:-0.1}"
echo "System Metrics: ${SYSTEM_METRICS:-true}"

# Install system dependencies
echo "Installing system dependencies..."
apt-get update -qq && apt-get install -y -qq \
  ffmpeg \
  libgl1-mesa-glx \
  libglib2.0-0 \
  build-essential \
  gcc \
  unzip \
  python3-dev \
  > /dev/null 2>&1

# Install UV package manager
echo "Installing UV package manager..."
pip install --quiet uv

# Install LeRobot and Azure ML dependencies
LEROBOT_PKG="lerobot"
if [[ -n "${LEROBOT_VERSION:-}" && "${LEROBOT_VERSION}" != "latest" ]]; then
  LEROBOT_PKG="lerobot==${LEROBOT_VERSION}"
fi

PIP_PACKAGES=(
  "${LEROBOT_PKG}" huggingface-hub
  azure-identity azure-ai-ml azureml-mlflow "mlflow>=2.8.0,<3.0.0"
  psutil pynvml
)

echo "Installing LeRobot ${LEROBOT_VERSION:-latest} and dependencies..."
if command -v uv &>/dev/null; then
  uv pip install "${PIP_PACKAGES[@]}" --system
else
  pip install --quiet --no-cache-dir "${PIP_PACKAGES[@]}"
fi

# The code snapshot (src/) is mounted at the working directory by Azure ML
export PYTHONPATH=".:${PYTHONPATH:-}"
echo "Training modules available via code snapshot"

# Run training via Python orchestrator
echo "Starting LeRobot training..."
python3 -m training.scripts.lerobot.train

echo "=== Training Complete ==="
ls -la "${OUTPUT_DIR}/" 2>/dev/null || true

# Upload checkpoints to Azure ML model registry
if [[ -n "${REGISTER_CHECKPOINT:-}" && -n "${AZURE_SUBSCRIPTION_ID:-}" && -n "${AZURE_RESOURCE_GROUP:-}" && -n "${AZUREML_WORKSPACE_NAME:-}" ]]; then
  echo "=== Uploading Checkpoints to Azure ML ==="
  python3 -c "from training.scripts.lerobot.checkpoints import upload_checkpoints_to_azure_ml; upload_checkpoints_to_azure_ml()"
  echo "=== Checkpoint Upload Complete ==="
fi
'"'"''

#------------------------------------------------------------------------------
# Build Submission Command
#------------------------------------------------------------------------------

az_args=(
  az ml job create
  --resource-group "$resource_group"
  --workspace-name "$workspace_name"
  --file "$job_file"
  --set "environment=azureml:${environment_name}:${environment_version}"
  --set "code=$REPO_ROOT/src"
)

[[ -n "$compute" ]] && az_args+=(--set "compute=$compute")
[[ -n "$instance_type" ]] && az_args+=(--set "resources.instance_type=$instance_type")
[[ -n "$display_name" ]] && az_args+=(--set "display_name=$display_name")

az_args+=(--set "command=$train_cmd")

# Environment variables — all set directly via --set flags
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
)

# Optional environment variables — only set when non-empty
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
