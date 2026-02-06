#!/usr/bin/env bash
# Submit LeRobot behavioral cloning training workflow to OSMO
# Supports ACT and Diffusion policy architectures with WANDB or Azure MLflow logging
set -o errexit -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/deploy/002-setup/lib/common.sh"
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
Usage: submit-osmo-lerobot-training.sh [OPTIONS] [-- osmo-submit-flags]

Submit a LeRobot behavioral cloning training workflow to OSMO.
Supports ACT and Diffusion policy architectures with HuggingFace Hub datasets.

REQUIRED:
    -d, --dataset-repo-id ID     HuggingFace dataset repository (e.g., user/dataset)

TRAINING OPTIONS:
    -w, --workflow PATH           Workflow template (default: workflows/osmo/lerobot-train.yaml)
    -p, --policy-type TYPE        Policy architecture: act, diffusion (default: act)
    -j, --job-name NAME           Job identifier (default: lerobot-act-training)
    -o, --output-dir DIR          Container output directory (default: /workspace/outputs/train)
    -i, --image IMAGE             Container image (default: pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime)
        --policy-repo-id ID       Pre-trained policy for fine-tuning (HuggingFace repo)
        --lerobot-version VER     Specific LeRobot version or "latest" (default: latest)

TRAINING HYPERPARAMETERS:
        --training-steps N        Total training iterations
        --batch-size N            Training batch size
        --eval-freq N             Evaluation frequency
        --save-freq N             Checkpoint save frequency (default: 5000)

LOGGING OPTIONS:
        --wandb-enable            Enable WANDB logging (default)
        --no-wandb                Disable WANDB logging
        --wandb-project NAME      WANDB project name (default: lerobot-training)
        --mlflow-enable           Enable Azure ML MLflow logging
        --experiment-name NAME    MLflow experiment name

CHECKPOINT REGISTRATION:
    -r, --register-checkpoint NAME  Model name for Azure ML registration (requires --mlflow-enable)

AZURE CONTEXT:
        --azure-subscription-id ID    Azure subscription ID
        --azure-resource-group NAME   Azure resource group
        --azure-workspace-name NAME   Azure ML workspace

OTHER:
    -h, --help                    Show this help message

Values resolved: CLI > Environment variables > Terraform outputs
Additional arguments after -- are forwarded to osmo workflow submit.

EXAMPLES:
    # Basic ACT training with WANDB logging
    submit-osmo-lerobot-training.sh -d lerobot/aloha_sim_insertion_human

    # Diffusion policy with MLflow
    submit-osmo-lerobot-training.sh \
      -d user/custom-dataset \
      -p diffusion \
      --mlflow-enable \
      -r my-diffusion-model

    # Fine-tune from existing policy
    submit-osmo-lerobot-training.sh \
      -d user/dataset \
      --policy-repo-id user/pretrained-act \
      --training-steps 50000
EOF
}

#------------------------------------------------------------------------------
# Defaults
#------------------------------------------------------------------------------

workflow="$REPO_ROOT/workflows/osmo/lerobot-train.yaml"
dataset_repo_id="${DATASET_REPO_ID:-}"
policy_type="${POLICY_TYPE:-act}"
job_name="${JOB_NAME:-lerobot-act-training}"
output_dir="${OUTPUT_DIR:-/workspace/outputs/train}"
image="${IMAGE:-pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime}"
policy_repo_id="${POLICY_REPO_ID:-}"
lerobot_version="${LEROBOT_VERSION:-}"

training_steps="${TRAINING_STEPS:-}"
batch_size="${BATCH_SIZE:-}"
eval_freq="${EVAL_FREQ:-}"
save_freq="${SAVE_FREQ:-5000}"

wandb_enable="${WANDB_ENABLE:-true}"
wandb_project="${WANDB_PROJECT:-lerobot-training}"
mlflow_enable="${MLFLOW_ENABLE:-false}"
experiment_name="${EXPERIMENT_NAME:-}"
register_checkpoint="${REGISTER_CHECKPOINT:-}"

subscription_id="${AZURE_SUBSCRIPTION_ID:-$(get_subscription_id)}"
resource_group="${AZURE_RESOURCE_GROUP:-$(get_resource_group)}"
workspace_name="${AZUREML_WORKSPACE_NAME:-$(get_azureml_workspace)}"

forward_args=()

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)                    show_help; exit 0 ;;
    -w|--workflow)                workflow="$2"; shift 2 ;;
    -d|--dataset-repo-id)         dataset_repo_id="$2"; shift 2 ;;
    -p|--policy-type)             policy_type="$2"; shift 2 ;;
    -j|--job-name)                job_name="$2"; shift 2 ;;
    -o|--output-dir)              output_dir="$2"; shift 2 ;;
    -i|--image)                   image="$2"; shift 2 ;;
    --policy-repo-id)             policy_repo_id="$2"; shift 2 ;;
    --lerobot-version)            lerobot_version="$2"; shift 2 ;;
    --training-steps)             training_steps="$2"; shift 2 ;;
    --batch-size)                 batch_size="$2"; shift 2 ;;
    --eval-freq)                  eval_freq="$2"; shift 2 ;;
    --save-freq)                  save_freq="$2"; shift 2 ;;
    --wandb-enable)               wandb_enable="true"; shift ;;
    --no-wandb)                   wandb_enable="false"; shift ;;
    --wandb-project)              wandb_project="$2"; shift 2 ;;
    --mlflow-enable)              mlflow_enable="true"; shift ;;
    --experiment-name)            experiment_name="$2"; shift 2 ;;
    -r|--register-checkpoint)     register_checkpoint="$2"; shift 2 ;;
    --azure-subscription-id)      subscription_id="$2"; shift 2 ;;
    --azure-resource-group)       resource_group="$2"; shift 2 ;;
    --azure-workspace-name)       workspace_name="$2"; shift 2 ;;
    --)                           shift; forward_args=("$@"); break ;;
    *)                            forward_args+=("$1"); shift ;;
  esac
done

#------------------------------------------------------------------------------
# Validation
#------------------------------------------------------------------------------

require_tools osmo

[[ -z "$dataset_repo_id" ]] && fatal "--dataset-repo-id is required"
[[ -f "$workflow" ]] || fatal "Workflow template not found: $workflow"

case "$policy_type" in
  act|diffusion) ;;
  *) fatal "Unsupported policy type: $policy_type (use: act, diffusion)" ;;
esac

if [[ "$mlflow_enable" == "true" ]]; then
  [[ -z "$subscription_id" ]] && fatal "Azure subscription ID required for MLflow logging"
  [[ -z "$resource_group" ]] && fatal "Azure resource group required for MLflow logging"
  [[ -z "$workspace_name" ]] && fatal "Azure ML workspace name required for MLflow logging"
fi

#------------------------------------------------------------------------------
# Build Submission Command
#------------------------------------------------------------------------------

submit_args=(
  workflow submit "$workflow"
  --set-string "image=$image"
  "dataset_repo_id=$dataset_repo_id"
  "policy_type=$policy_type"
  "job_name=$job_name"
  "output_dir=$output_dir"
  "wandb_enable=$wandb_enable"
  "wandb_project=$wandb_project"
  "mlflow_enable=$mlflow_enable"
  "save_freq=$save_freq"
)

[[ -n "$policy_repo_id" ]]      && submit_args+=("policy_repo_id=$policy_repo_id")
[[ -n "$lerobot_version" ]]     && submit_args+=("lerobot_version=$lerobot_version")
[[ -n "$training_steps" ]]      && submit_args+=("training_steps=$training_steps")
[[ -n "$batch_size" ]]          && submit_args+=("batch_size=$batch_size")
[[ -n "$eval_freq" ]]           && submit_args+=("eval_freq=$eval_freq")
[[ -n "$experiment_name" ]]     && submit_args+=("experiment_name=$experiment_name")
[[ -n "$register_checkpoint" ]] && submit_args+=("register_checkpoint=$register_checkpoint")

[[ -n "$subscription_id" ]] && submit_args+=("azure_subscription_id=$subscription_id")
[[ -n "$resource_group" ]]  && submit_args+=("azure_resource_group=$resource_group")
[[ -n "$workspace_name" ]]  && submit_args+=("azure_workspace_name=$workspace_name")

[[ ${#forward_args[@]} -gt 0 ]] && submit_args+=("${forward_args[@]}")

#------------------------------------------------------------------------------
# Submit Workflow
#------------------------------------------------------------------------------

logging_backend="WANDB"
[[ "$mlflow_enable" == "true" ]] && logging_backend="Azure MLflow"

info "Submitting LeRobot training workflow to OSMO..."
info "  Dataset: $dataset_repo_id"
info "  Policy: $policy_type"
info "  Job Name: $job_name"
info "  Image: $image"
info "  Logging: $logging_backend"
[[ -n "$policy_repo_id" ]] && info "  Fine-tune from: $policy_repo_id"
[[ -n "$register_checkpoint" ]] && info "  Register model: $register_checkpoint"

osmo "${submit_args[@]}" || fatal "Failed to submit workflow"

info "Workflow submitted successfully"
