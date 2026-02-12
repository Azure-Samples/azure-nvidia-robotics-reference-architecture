#!/usr/bin/env bash
# Submit LeRobot inference/evaluation workflow to OSMO
# Evaluates trained LeRobot policies from HuggingFace Hub
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
Usage: submit-osmo-lerobot-inference.sh [OPTIONS] [-- osmo-submit-flags]

Submit a LeRobot inference/evaluation workflow to OSMO.
Evaluates trained policies from HuggingFace Hub repositories.

REQUIRED:
        --policy-repo-id ID       HuggingFace policy repository (e.g., user/trained-policy)

EVALUATION OPTIONS:
    -w, --workflow PATH           Workflow template (default: workflows/osmo/lerobot-infer.yaml)
    -p, --policy-type TYPE        Policy architecture: act, diffusion (default: act)
    -d, --dataset-repo-id ID     Dataset for environment replay evaluation
    -j, --job-name NAME           Job identifier (default: lerobot-eval)
    -o, --output-dir DIR          Container output directory (default: /workspace/outputs/eval)
    -i, --image IMAGE             Container image (default: pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime)
        --lerobot-version VER     Specific LeRobot version (default: latest)
        --eval-episodes N         Number of evaluation episodes (default: 10)
        --eval-batch-size N       Evaluation batch size (default: 10)
        --record-video            Record evaluation videos

MODEL REGISTRATION:
    -r, --register-model NAME     Model name for Azure ML registration

AZURE CONTEXT:
        --azure-subscription-id ID    Azure subscription ID
        --azure-resource-group NAME   Azure resource group
        --azure-workspace-name NAME   Azure ML workspace

OTHER:
    -h, --help                    Show this help message

Values resolved: CLI > Environment variables > Terraform outputs
Additional arguments after -- are forwarded to osmo workflow submit.
EOF
}

#------------------------------------------------------------------------------
# Defaults
#------------------------------------------------------------------------------

workflow="$REPO_ROOT/workflows/osmo/lerobot-infer.yaml"
policy_repo_id="${POLICY_REPO_ID:-}"
policy_type="${POLICY_TYPE:-act}"
dataset_repo_id="${DATASET_REPO_ID:-}"
job_name="${JOB_NAME:-lerobot-eval}"
output_dir="${OUTPUT_DIR:-/workspace/outputs/eval}"
image="${IMAGE:-pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime}"
lerobot_version="${LEROBOT_VERSION:-}"

eval_episodes="${EVAL_EPISODES:-10}"
eval_batch_size="${EVAL_BATCH_SIZE:-10}"
record_video="${RECORD_VIDEO:-false}"
register_model="${REGISTER_MODEL:-}"

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
    --policy-repo-id)             policy_repo_id="$2"; shift 2 ;;
    -p|--policy-type)             policy_type="$2"; shift 2 ;;
    -d|--dataset-repo-id)         dataset_repo_id="$2"; shift 2 ;;
    -j|--job-name)                job_name="$2"; shift 2 ;;
    -o|--output-dir)              output_dir="$2"; shift 2 ;;
    -i|--image)                   image="$2"; shift 2 ;;
    --lerobot-version)            lerobot_version="$2"; shift 2 ;;
    --eval-episodes)              eval_episodes="$2"; shift 2 ;;
    --eval-batch-size)            eval_batch_size="$2"; shift 2 ;;
    --record-video)               record_video="true"; shift ;;
    -r|--register-model)          register_model="$2"; shift 2 ;;
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

[[ -z "$policy_repo_id" ]] && fatal "--policy-repo-id is required"
[[ -f "$workflow" ]] || fatal "Workflow template not found: $workflow"

case "$policy_type" in
  act|diffusion) ;;
  *) fatal "Unsupported policy type: $policy_type (use: act, diffusion)" ;;
esac

if [[ -n "$register_model" ]]; then
  [[ -z "$subscription_id" ]] && fatal "Azure subscription ID required for model registration"
  [[ -z "$resource_group" ]] && fatal "Azure resource group required for model registration"
  [[ -z "$workspace_name" ]] && fatal "Azure ML workspace name required for model registration"
fi

#------------------------------------------------------------------------------
# Build Submission Command
#------------------------------------------------------------------------------

submit_args=(
  workflow submit "$workflow"
  --set-string "image=$image"
  "policy_repo_id=$policy_repo_id"
  "policy_type=$policy_type"
  "job_name=$job_name"
  "output_dir=$output_dir"
  "eval_episodes=$eval_episodes"
  "eval_batch_size=$eval_batch_size"
  "record_video=$record_video"
)

[[ -n "$dataset_repo_id" ]]  && submit_args+=("dataset_repo_id=$dataset_repo_id")
[[ -n "$lerobot_version" ]]  && submit_args+=("lerobot_version=$lerobot_version")
[[ -n "$register_model" ]]   && submit_args+=("register_model=$register_model")

[[ -n "$subscription_id" ]] && submit_args+=("azure_subscription_id=$subscription_id")
[[ -n "$resource_group" ]]  && submit_args+=("azure_resource_group=$resource_group")
[[ -n "$workspace_name" ]]  && submit_args+=("azure_workspace_name=$workspace_name")

[[ ${#forward_args[@]} -gt 0 ]] && submit_args+=("${forward_args[@]}")

#------------------------------------------------------------------------------
# Submit Workflow
#------------------------------------------------------------------------------

info "Submitting LeRobot inference workflow to OSMO..."
info "  Policy: $policy_repo_id"
info "  Policy Type: $policy_type"
info "  Job Name: $job_name"
info "  Eval Episodes: $eval_episodes"
info "  Image: $image"
[[ -n "$dataset_repo_id" ]] && info "  Dataset: $dataset_repo_id"
[[ -n "$register_model" ]] && info "  Register model: $register_model"

osmo "${submit_args[@]}" || fatal "Failed to submit workflow"

info "Workflow submitted successfully"
