#!/usr/bin/env bash
#
# Azure ML Validation Job Submission Script
#
# This script packages training code, ensures the container environment exists,
# and submits an Azure ML validation job using isaaclab-validate.yaml as a template.
#
# Key responsibilities:
# 1. Package src/training/ directory into a staging area
# 2. Ensure the IsaacLab container image is registered as an AzureML environment
# 3. Build a complete validation command with all specified parameters
# 4. Override the YAML template with actual runtime values
# 5. Submit the job to Azure ML
#
# The YAML template (isaaclab-validate.yaml) provides structure only.
# This script provides all actual values via --set flags.
#
# Usage:
#   ./submit-azureml-validation.sh --model-name MODEL --model-version VERSION [options]
#
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'EOF'
Usage: submit-azureml-validation.sh --model-name NAME --model-version VERSION [options]

Packages src/training/ into a staging folder, ensures the IsaacLab container
image is registered as an environment, and submits the validation command job.

Required:
  --model-name NAME             Azure ML registered model name
  --model-version VERSION       Model version (or "latest")

AzureML asset options:
  --environment-name NAME       AzureML environment name (default: isaaclab-training-env)
  --environment-version VER     Environment version (default: 2.2.0)
  --image IMAGE                 Container image reference (default: nvcr.io/nvidia/isaac-lab:2.2.0)
  --staging-dir PATH            Directory for intermediate packaging (default: .tmp)

Validation options:
  --task TASK                   Override task ID (default: from model metadata)
  --framework FRAMEWORK         Override framework (default: from model metadata)
  --eval-episodes N             Number of evaluation episodes (default: 100)
  --num-envs N                  Number of parallel environments (default: 64)
  --success-threshold F         Override success threshold (default: from metadata)
  --headless                    Run headless (default: true)
  --gui                         Disable headless mode

Azure context overrides:
  --job-file PATH               Path to validation job YAML (default: isaaclab-validate.yaml)
  --compute TARGET              Compute target override (e.g., azureml:k8s-compute)
  --instance-type TYPE          Instance type for Kubernetes compute (e.g., gpuspot)
  --experiment-name NAME        Azure ML experiment name override
  --job-name NAME               Azure ML job name override
  --stream                      Stream job logs after submission
  -h, --help                    Show this help message

Environment requirements:
  AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, and AZUREML_WORKSPACE_NAME must be set.
  Azure CLI ml extension must be installed.
EOF
}

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Command not found: $1"
  fi
}

resolve_repo_root() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -z "$root" ]]; then
    fail "Run inside the repository working tree"
  fi
  printf '%s\n' "$root"
}

ensure_ml_extension() {
  if az extension show --name ml >/dev/null 2>&1; then
    return
  fi
  fail "Azure ML CLI extension not installed. Run: az extension add --name ml"
}

prepare_training_payload() {
  local source="$1"
  local destination="$2"
  if [[ ! -d "$source" ]]; then
    fail "Training source not found: $source"
  fi
  rm -rf "$destination"
  mkdir -p "$destination/src"
  rsync -a --delete "$source/" "$destination/src/training/"
}

register_environment() {
  local name="$1"
  local version="$2"
  local image="$3"
  local env_file="$4"
  local resource_group="$5"
  local workspace_name="$6"
  cat >"$env_file" <<EOF
\$schema: https://azuremlschemas.azureedge.net/latest/environment.schema.json
name: $name
version: $version
image: $image
EOF
  log "Publishing AzureML environment ${name}:${version}"
  az ml environment create --file "$env_file" \
    --name "$name" --version "$version" \
    --resource-group "$resource_group" --workspace-name "$workspace_name" >/dev/null
}

stream_job_logs() {
  local job_name="$1"

  log "Streaming job logs for ${job_name}"
  log "Note: For Kubernetes compute, 'az ml job stream' shows status only, not training output."
  log "To view logs: az ml job download --name ${job_name} --all"
  log "Then check: ./${job_name}/user_logs/std_log.txt"

  az ml job stream --name "${job_name}" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --workspace-name "${AZUREML_WORKSPACE_NAME}" || true
}

main() {
  local repo_root
  repo_root=$(resolve_repo_root)

  # AzureML asset options
  local environment_name="isaaclab-training-env"
  local environment_version="2.2.0"
  local image="nvcr.io/nvidia/isaac-lab:2.2.0"
  local staging_dir="${STAGING_DIR:-$SCRIPT_DIR/.tmp}"

  # Required arguments
  local model_name=""
  local model_version=""

  # Validation options
  local task=""
  local framework=""
  local episodes=100
  local num_envs=64
  local threshold=""
  local headless="true"

  # Azure context
  local job_file="${SCRIPT_DIR}/../jobs/isaaclab-validate.yaml"
  local compute=""
  local instance_type=""
  local experiment_name=""
  local job_name_override=""
  local stream_logs=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --model-name)
        model_name="$2"
        shift 2
        ;;
      --model-version)
        model_version="$2"
        shift 2
        ;;
      --environment-name)
        environment_name="$2"
        shift 2
        ;;
      --environment-version)
        environment_version="$2"
        shift 2
        ;;
      --image)
        image="$2"
        shift 2
        ;;
      --staging-dir)
        staging_dir="$2"
        shift 2
        ;;
      --task)
        task="$2"
        shift 2
        ;;
      --framework)
        framework="$2"
        shift 2
        ;;
      --eval-episodes)
        episodes="$2"
        shift 2
        ;;
      --num-envs)
        num_envs="$2"
        shift 2
        ;;
      --success-threshold)
        threshold="$2"
        shift 2
        ;;
      --headless)
        headless="true"
        shift
        ;;
      --gui)
        headless="false"
        shift
        ;;
      --job-file)
        job_file="$2"
        shift 2
        ;;
      --compute)
        compute="$2"
        shift 2
        ;;
      --instance-type)
        instance_type="$2"
        shift 2
        ;;
      --experiment-name)
        experiment_name="$2"
        shift 2
        ;;
      --job-name)
        job_name_override="$2"
        shift 2
        ;;
      --stream)
        stream_logs=true
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done

  require_command az
  require_command rsync
  ensure_ml_extension

  # Validate required arguments
  if [[ -z "${model_name}" ]]; then
    fail "--model-name is required"
  fi

  if [[ -z "${model_version}" ]]; then
    fail "--model-version is required (use 'latest' for most recent)"
  fi

  if [[ ! -f "${job_file}" ]]; then
    fail "Job file not found: ${job_file}"
  fi

  # Resolve "latest" version if specified
  if [[ "${model_version}" == "latest" ]]; then
    log "Resolving latest version for model: ${model_name}"
    model_version=$(az ml model list \
      --name "${model_name}" \
      --resource-group "${AZURE_RESOURCE_GROUP}" \
      --workspace-name "${AZUREML_WORKSPACE_NAME}" \
      --query "[0].version" -o tsv 2>/dev/null || echo "")
    if [[ -z "${model_version}" ]]; then
      fail "Could not find model: ${model_name}"
    fi
    log "Using version: ${model_version}"
  fi

  local model_uri="azureml:${model_name}:${model_version}"

  # ============================================================================
  # Phase 1: Package training code and register environment
  # ============================================================================

  local training_src="$repo_root/src/training"
  local code_payload="$staging_dir/code"
  local env_file="$staging_dir/environment.yaml"
  mkdir -p "$staging_dir"

  log "Packaging training payload from $training_src"
  prepare_training_payload "$training_src" "$code_payload"

  log "Registering AzureML assets"
  register_environment "$environment_name" "$environment_version" "$image" "$env_file" \
    "$AZURE_RESOURCE_GROUP" "$AZUREML_WORKSPACE_NAME"

  log "Using local code path: $code_payload"
  log "Environment: ${environment_name}:${environment_version} ($image)"

  # ============================================================================
  # Phase 2: Build Azure ML job submission command
  # ============================================================================

  log "Submitting validation job"
  log "  Model: ${model_uri}"
  log "  Task: ${task:-'(from metadata)'}"
  log "  Framework: ${framework:-'(from metadata)'}"
  log "  Episodes: ${episodes}"
  log "  Threshold: ${threshold:-'(from metadata)'}"

  local az_args=(
    az ml job create
    --resource-group "${AZURE_RESOURCE_GROUP}"
    --workspace-name "${AZUREML_WORKSPACE_NAME}"
    --file "${job_file}"
  )

  # Override core job configuration from template
  az_args+=(--set "code=$code_payload")
  az_args+=(--set "environment=azureml:${environment_name}:${environment_version}")

  # Set model input with proper structure
  az_args+=(--set "inputs.trained_model.path=${model_uri}")

  # Override compute and resources
  [[ -n "${compute}" ]] && az_args+=(--set "compute=${compute}")
  [[ -n "${instance_type}" ]] && az_args+=(--set "resources.instance_type=${instance_type}")
  [[ -n "${experiment_name}" ]] && az_args+=(--set "experiment_name=${experiment_name}")
  [[ -n "${job_name_override}" ]] && az_args+=(--set "name=${job_name_override}")

  # Build the validation command dynamically
  local cmd_args="--model-path \${{inputs.trained_model}}"
  cmd_args="$cmd_args --eval-episodes \${{inputs.eval_episodes}}"
  cmd_args="$cmd_args --num-envs \${{inputs.num_envs}}"
  cmd_args="$cmd_args --task \${{inputs.task}}"
  cmd_args="$cmd_args --framework \${{inputs.framework}}"
  cmd_args="$cmd_args --success-threshold \${{inputs.success_threshold}}"

  # Set input values - use "auto" sentinel for task/framework when not specified
  # The validate.sh script will handle "auto" by detecting from model metadata
  az_args+=(--set "inputs.task=${task:-auto}")
  az_args+=(--set "inputs.framework=${framework:-auto}")
  az_args+=(--set "inputs.success_threshold=${threshold:--1.0}")

  if [[ "${headless}" == "true" ]]; then
    cmd_args="$cmd_args --headless"
  fi

  # Set the command
  az_args+=(--set "command=bash src/training/scripts/validate.sh $cmd_args")

  # Set required input values
  az_args+=(--set "inputs.eval_episodes=${episodes}")
  az_args+=(--set "inputs.num_envs=${num_envs}")

  # Request job name for output
  az_args+=(--query "name" -o "tsv")

  # ============================================================================
  # Phase 3: Submit the job and report results
  # ============================================================================

  log "Submitting job..."
  local job_name_result
  if ! job_name_result=$("${az_args[@]}"); then
    fail "Job submission failed"
  fi

  if [[ -z "${job_name_result}" ]]; then
    fail "Job submission failed - no job name returned"
  fi

  log "Job submitted: ${job_name_result}"
  log "View in portal: https://ml.azure.com/runs/${job_name_result}?wsid=/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${AZUREML_WORKSPACE_NAME}"

  # Stream logs if requested
  if [[ "${stream_logs}" == "true" ]]; then
    stream_job_logs "${job_name_result}"
  fi
}

main "$@"
