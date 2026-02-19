#!/usr/bin/env bash
# Run LeRobot behavioral cloning training locally on an NVIDIA GPU (RTX 4090/5090)
# Supports ACT and Diffusion policy architectures with optional Azure ML MLflow logging
set -o errexit -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/deploy/002-setup/lib/common.sh"

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
Usage: run-local-lerobot-training.sh [OPTIONS] [-- lerobot-train-flags]

Run LeRobot behavioral cloning training locally on an NVIDIA GPU.
Intended for RTX 4090/5090 workstations with local or HuggingFace data.

REQUIRED:
    -d, --dataset-repo-id ID     HuggingFace dataset repository (e.g., user/dataset)

DATA SOURCE:
    -D, --dataset-root DIR        Local dataset root directory
                                  (default: ~/.cache/huggingface/lerobot)
        --local-files-only        Skip HuggingFace Hub downloads, use cached data only

TRAINING OPTIONS:
    -p, --policy-type TYPE        Policy architecture: act, diffusion (default: act)
    -j, --job-name NAME           Job identifier (default: lerobot-act-training)
    -o, --output-dir DIR          Output directory (default: outputs/train)
        --policy-repo-id ID       Pre-trained policy for fine-tuning (HuggingFace repo)
        --lerobot-version VER     Required LeRobot version (validated, not installed)
        --device DEVICE           Torch device (default: cuda)

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
        --wandb                   Enable Weights & Biases logging
        --wandb-project NAME      WANDB project name (default: lerobot-training)
        --mlflow                  Enable Azure ML MLflow logging (requires Azure credentials)
        --experiment-name NAME    MLflow experiment name

GENERAL:
    -h, --help                    Show this help message
        --dry-run                 Print the training command without executing

Additional arguments after -- are forwarded directly to lerobot-train.

EXAMPLES:
    # ACT training on a HuggingFace dataset
    run-local-lerobot-training.sh -d lerobot/aloha_sim_insertion_human

    # Diffusion policy with custom hyperparameters
    run-local-lerobot-training.sh \
      -d user/custom-dataset \
      -p diffusion \
      --learning-rate 5e-5 \
      --batch-size 16

    # Train from a local dataset directory
    run-local-lerobot-training.sh \
      -d user/my-dataset \
      -D /data/lerobot-datasets \
      --local-files-only

    # Fine-tune with W&B logging
    run-local-lerobot-training.sh \
      -d user/dataset \
      --policy-repo-id user/pretrained-act \
      --training-steps 50000 \
      --wandb

    # Forward extra flags to lerobot-train
    run-local-lerobot-training.sh \
      -d lerobot/aloha_sim_insertion_human \
      -- --dataset.use_imagenet_stats=false
EOF
}

#------------------------------------------------------------------------------
# Defaults
#------------------------------------------------------------------------------

dataset_repo_id="${DATASET_REPO_ID:-}"
dataset_root="${DATASET_ROOT:-}"
local_files_only=false

policy_type="${POLICY_TYPE:-act}"
job_name="${JOB_NAME:-lerobot-act-training}"
output_dir="${OUTPUT_DIR:-outputs/train}"
policy_repo_id="${POLICY_REPO_ID:-}"
lerobot_version="${LEROBOT_VERSION:-}"
device="${DEVICE:-cuda}"

training_steps="${TRAINING_STEPS:-100000}"
batch_size="${BATCH_SIZE:-32}"
learning_rate="${LEARNING_RATE:-1e-4}"
lr_warmup_steps="${LR_WARMUP_STEPS:-1000}"
eval_freq="${EVAL_FREQ:-}"
save_freq="${SAVE_FREQ:-5000}"

val_split="${VAL_SPLIT:-0.1}"
val_split_enabled=true

wandb_enable=false
wandb_project="${WANDB_PROJECT:-lerobot-training}"
mlflow_enable=false
experiment_name="${EXPERIMENT_NAME:-}"

dry_run=false
forward_args=()

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)                    show_help; exit 0 ;;
    -d|--dataset-repo-id)         dataset_repo_id="$2"; shift 2 ;;
    -D|--dataset-root)            dataset_root="$2"; shift 2 ;;
    --local-files-only)           local_files_only=true; shift ;;
    -p|--policy-type)             policy_type="$2"; shift 2 ;;
    -j|--job-name)                job_name="$2"; shift 2 ;;
    -o|--output-dir)              output_dir="$2"; shift 2 ;;
    --policy-repo-id)             policy_repo_id="$2"; shift 2 ;;
    --lerobot-version)            lerobot_version="$2"; shift 2 ;;
    --device)                     device="$2"; shift 2 ;;
    --training-steps)             training_steps="$2"; shift 2 ;;
    --batch-size)                 batch_size="$2"; shift 2 ;;
    --learning-rate)              learning_rate="$2"; shift 2 ;;
    --lr-warmup-steps)            lr_warmup_steps="$2"; shift 2 ;;
    --eval-freq)                  eval_freq="$2"; shift 2 ;;
    --save-freq)                  save_freq="$2"; shift 2 ;;
    --val-split)                  val_split="$2"; shift 2 ;;
    --no-val-split)               val_split_enabled=false; shift ;;
    --wandb)                      wandb_enable=true; shift ;;
    --wandb-project)              wandb_project="$2"; shift 2 ;;
    --mlflow)                     mlflow_enable=true; shift ;;
    --experiment-name)            experiment_name="$2"; shift 2 ;;
    --dry-run)                    dry_run=true; shift ;;
    --)                           shift; forward_args=("$@"); break ;;
    *)                            fatal "Unknown option: $1" ;;
  esac
done

#------------------------------------------------------------------------------
# Validation
#------------------------------------------------------------------------------

require_tools python3

[[ -z "$dataset_repo_id" ]] && fatal "--dataset-repo-id is required"

case "$policy_type" in
  act|diffusion) ;;
  *) fatal "Unsupported policy type: $policy_type (use: act, diffusion)" ;;
esac

[[ "$val_split_enabled" == "false" ]] && val_split="0"

# Validate CUDA availability for GPU devices
if [[ "$device" == "cuda" ]]; then
  if ! python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
    fatal "CUDA is not available. Install PyTorch with CUDA support or use --device cpu"
  fi
  gpu_name=$(python3 -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null || echo "unknown")
  gpu_mem=$(python3 -c "
import torch
mem = torch.cuda.get_device_properties(0).total_mem / (1024**3)
print(f'{mem:.0f}')
" 2>/dev/null || echo "?")
  info "GPU detected: ${gpu_name} (${gpu_mem} GB)"
fi

# Validate lerobot is installed
if ! python3 -c "import lerobot" 2>/dev/null; then
  fatal "lerobot is not installed. Install with: pip install lerobot"
fi

if [[ -n "$lerobot_version" && "$lerobot_version" != "latest" ]]; then
  installed_ver=$(python3 -c "import lerobot; print(lerobot.__version__)" 2>/dev/null || echo "")
  if [[ -n "$installed_ver" && "$installed_ver" != "$lerobot_version" ]]; then
    warn "Installed lerobot version ($installed_ver) differs from requested ($lerobot_version)"
  fi
fi

# Validate MLflow dependencies when enabled
if [[ "$mlflow_enable" == "true" ]]; then
  python3 -c "import mlflow; import azure.ai.ml" 2>/dev/null || \
    fatal "MLflow logging requires: pip install mlflow azure-ai-ml azure-identity azureml-mlflow"
  [[ -z "${AZURE_SUBSCRIPTION_ID:-}" ]] && fatal "MLflow logging requires AZURE_SUBSCRIPTION_ID"
  [[ -z "${AZURE_RESOURCE_GROUP:-}" ]] && fatal "MLflow logging requires AZURE_RESOURCE_GROUP"
  [[ -z "${AZUREML_WORKSPACE_NAME:-}" ]] && fatal "MLflow logging requires AZUREML_WORKSPACE_NAME"
fi

# Validate dataset root when local-files-only
if [[ "$local_files_only" == "true" && -n "$dataset_root" ]]; then
  [[ -d "$dataset_root" ]] || fatal "Dataset root not found: $dataset_root"
fi

#------------------------------------------------------------------------------
# Build Training Command
#------------------------------------------------------------------------------

train_cmd=(lerobot-train)

train_cmd+=(
  "--dataset.repo_id=${dataset_repo_id}"
  "--policy.type=${policy_type}"
  "--output_dir=${output_dir}"
  "--job_name=${job_name}"
  "--policy.device=${device}"
  "--steps=${training_steps}"
  "--batch_size=${batch_size}"
  "--save_freq=${save_freq}"
)

[[ -n "$dataset_root" ]]     && train_cmd+=("--dataset.root=${dataset_root}")
[[ -n "$policy_repo_id" ]]   && train_cmd+=("--policy.repo_id=${policy_repo_id}")
[[ -n "$eval_freq" ]]        && train_cmd+=("--eval_freq=${eval_freq}")

if [[ "$local_files_only" == "true" ]]; then
  train_cmd+=("--dataset.local_files_only=true")
fi

# W&B logging
if [[ "$wandb_enable" == "true" ]]; then
  train_cmd+=("--wandb.enable=true" "--wandb.project=${wandb_project}")
else
  train_cmd+=("--wandb.enable=false")
fi

# Forward extra arguments
[[ ${#forward_args[@]} -gt 0 ]] && train_cmd+=("${forward_args[@]}")

#------------------------------------------------------------------------------
# Configure MLflow (optional)
#------------------------------------------------------------------------------

if [[ "$mlflow_enable" == "true" ]]; then
  export DATASET_REPO_ID="$dataset_repo_id"
  export POLICY_TYPE="$policy_type"
  export JOB_NAME="$job_name"
  export OUTPUT_DIR="$output_dir"
  export TRAINING_STEPS="$training_steps"
  export BATCH_SIZE="$batch_size"
  export LEARNING_RATE="$learning_rate"
  export LR_WARMUP_STEPS="$lr_warmup_steps"
  export SAVE_FREQ="$save_freq"
  export VAL_SPLIT="$val_split"
  export SYSTEM_METRICS="true"
  [[ -n "$experiment_name" ]] && export EXPERIMENT_NAME="$experiment_name"
  export PYTHONPATH="${REPO_ROOT}/src:${PYTHONPATH:-}"
fi

#------------------------------------------------------------------------------
# Print Configuration
#------------------------------------------------------------------------------

section "Local LeRobot Training"
print_kv "Dataset" "$dataset_repo_id"
print_kv "Policy" "$policy_type"
print_kv "Job Name" "$job_name"
print_kv "Device" "$device"
print_kv "Output Dir" "$output_dir"
print_kv "Training Steps" "$training_steps"
print_kv "Batch Size" "$batch_size"
print_kv "Learning Rate" "$learning_rate"
print_kv "LR Warmup" "$lr_warmup_steps"
print_kv "Save Freq" "$save_freq"
print_kv "Val Split" "$val_split"
print_kv "W&B" "$([[ "$wandb_enable" == "true" ]] && echo "enabled ($wandb_project)" || echo "disabled")"
print_kv "MLflow" "$([[ "$mlflow_enable" == "true" ]] && echo "enabled" || echo "disabled")"
[[ -n "$dataset_root" ]] && print_kv "Dataset Root" "$dataset_root"
[[ "$local_files_only" == "true" ]] && print_kv "Local Only" "true"
[[ -n "$policy_repo_id" ]] && print_kv "Fine-tune from" "$policy_repo_id"

#------------------------------------------------------------------------------
# Execute Training
#------------------------------------------------------------------------------

if [[ "$dry_run" == "true" ]]; then
  section "Dry Run"
  info "Command: ${train_cmd[*]}"
  exit 0
fi

mkdir -p "$output_dir"

if [[ "$mlflow_enable" == "true" ]]; then
  info "Running training with MLflow logging via Python orchestrator..."
  exec python3 -m training.scripts.lerobot.train "${train_cmd[@]:1}"
else
  info "Running: ${train_cmd[*]}"
  exec "${train_cmd[@]}"
fi
