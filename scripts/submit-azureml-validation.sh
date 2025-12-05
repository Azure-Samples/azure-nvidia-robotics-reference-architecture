#!/usr/bin/env bash
#
# Azure ML Validation Job Submission Script
#
# This script packages training code, ensures the container environment exists,
# and submits an Azure ML validation job using validate.yaml as a template.
#
# Key responsibilities:
# 1. Package src/training/ directory into a staging area
# 2. Ensure the IsaacLab container image is registered as an AzureML environment
# 3. Build a complete validation command with all specified parameters
# 4. Override the YAML template with actual runtime values
# 5. Submit the job to Azure ML
#
# The YAML template (workflows/azureml/validate.yaml) provides structure only.
# This script provides all actual values via --set flags.
#
# Usage:
#   ./submit-azureml-validation.sh --model-name MODEL --model-version VERSION [options]
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
Usage: submit-azureml-validation.sh [options]

Packages src/training/ into a staging folder, ensures the IsaacLab container
image is registered as an environment, and submits the validation command job.

Model options:
  --model-name NAME             Azure ML registered model name (default: derived from task)
  --model-version VERSION       Model version (default: latest)

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
  --job-file PATH               Path to validation job YAML (default: workflows/azureml/validate.yaml)
  --compute TARGET              Compute target override (e.g., azureml:k8s-compute)
  --instance-type TYPE          Instance type for Kubernetes compute (default: gpuspot)
  --experiment-name NAME        Azure ML experiment name override
  --job-name NAME               Azure ML job name override
  --stream                      Stream job logs after submission
  -h, --help                    Show this help message

Environment requirements:
  AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, and AZUREML_WORKSPACE_NAME must be set.
  Azure CLI ml extension must be installed.

  Values are resolved in order: CLI arguments > Environment variables > Terraform outputs
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

ensure_ml_extension() {
  if az extension show --name ml >/dev/null 2>&1; then
    return
  fi
  fail "Azure ML CLI extension not installed. Run: az extension add --name ml"
}

derive_model_name_from_task() {
  local task="$1"
  # Convert IsaacLab task to model name:
  # Isaac-Velocity-Rough-Anymal-C-v0 -> anymal-c-velocity-rough
  # Isaac-Reach-Franka-v0 -> franka-reach
  local name="$task"
  # Remove Isaac- prefix and version suffix
  name="${name#Isaac-}"
  name="$(printf '%s' "$name" | sed -E 's/-v[0-9]+$//')"
  # Convert to lowercase
  name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  # Reorder: move robot name (last segment(s) before version) to front
  # e.g., velocity-rough-anymal-c -> anymal-c-velocity-rough
  local parts robot_part task_parts
  IFS='-' read -ra parts <<< "$name"
  if [[ ${#parts[@]} -ge 3 ]]; then
    local last_idx=$((${#parts[@]} - 1))
    local second_last_idx=$((${#parts[@]} - 2))
    # If last segment is short (1-2 chars like "c" in "anymal-c"), it's a two-part robot name
    if [[ ${#parts[$last_idx]} -le 2 ]]; then
      # Two-part robot name like "anymal-c"
      robot_part="${parts[$second_last_idx]}-${parts[$last_idx]}"
      task_parts="$(IFS='-'; echo "${parts[*]:0:$second_last_idx}")"
    else
      # Single-part robot name like "franka" or "spot"
      robot_part="${parts[$last_idx]}"
      task_parts="$(IFS='-'; echo "${parts[*]:0:$last_idx}")"
    fi
    name="${robot_part}-${task_parts}"
  fi
  printf '%s' "$name"
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
  local resource_group="$2"
  local workspace_name="$3"

  log "Streaming job logs for ${job_name}"
  log "Note: For Kubernetes compute, 'az ml job stream' shows status only, not training output."
  log "To view logs: az ml job download --name ${job_name} --all"
  log "Then check: ./${job_name}/user_logs/std_log.txt"

  az ml job stream --name "${job_name}" \
    --resource-group "${resource_group}" \
    --workspace-name "${workspace_name}" || true
}

main() {
  # AzureML asset options
  local environment_name="isaaclab-training-env"
  local environment_version="2.2.0"
  local image="nvcr.io/nvidia/isaac-lab:2.2.0"
  local staging_dir="${STAGING_DIR:-$SCRIPT_DIR/.tmp}"

  # Model options (model_name derived from task if not provided)
  local model_name=""
  local model_version="latest"

  # Validation options (task used for model name derivation if model_name not set)
  local task="${TASK:-Isaac-Velocity-Rough-Anymal-C-v0}"
  local framework=""
  local episodes=100
  local num_envs=64
  local threshold=""
  local headless="true"

  # Three-tier value resolution: CLI > ENV > Terraform
  local subscription_id="${AZURE_SUBSCRIPTION_ID:-$(get_subscription_id)}"
  local resource_group="${AZURE_RESOURCE_GROUP:-$(get_resource_group)}"
  local workspace_name="${AZUREML_WORKSPACE_NAME:-$(get_azureml_workspace)}"

  # Azure context
  local job_file="${REPO_ROOT}/workflows/azureml/validate.yaml"
  local compute="${AZUREML_COMPUTE:-$(get_compute_target)}"
  local instance_type="gpuspot"
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
      --subscription-id)
        subscription_id="$2"
        shift 2
        ;;
      --resource-group)
        resource_group="$2"
        shift 2
        ;;
      --workspace-name)
        workspace_name="$2"
        shift 2
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
  require_command jq
  ensure_ml_extension

  # Derive model_name from task if not explicitly provided
  if [[ -z "${model_name}" ]]; then
    model_name="$(derive_model_name_from_task "${task}")"
    log "Auto-derived model name: ${model_name}"
  fi

  if [[ -z "${resource_group}" ]]; then
    fail "Resource group is required (set AZURE_RESOURCE_GROUP or use --resource-group)"
  fi

  if [[ -z "${workspace_name}" ]]; then
    fail "Workspace name is required (set AZUREML_WORKSPACE_NAME or use --workspace-name)"
  fi

  if [[ ! -f "${job_file}" ]]; then
    fail "Job file not found: ${job_file}"
  fi

  # Resolve "latest" version if specified
  if [[ "${model_version}" == "latest" ]]; then
    log "Resolving latest version for model: ${model_name}"
    model_version=$(az ml model list \
      --name "${model_name}" \
      --resource-group "${resource_group}" \
      --workspace-name "${workspace_name}" \
      --query "[0].version" -o tsv 2>/dev/null || echo "")
    if [[ -z "${model_version}" ]]; then
      fail "Could not find model: ${model_name}"
    fi
    log "Using version: ${model_version}"
  fi

  local model_uri="azureml:${model_name}:${model_version}"

  # ============================================================================
  # Phase 1: Fetch model metadata from Azure ML tags
  # ============================================================================

  log "Fetching model metadata from Azure ML"
  local model_json
  model_json=$(az ml model show \
    --name "${model_name}" \
    --version "${model_version}" \
    --resource-group "${resource_group}" \
    --workspace-name "${workspace_name}" \
    -o json 2>/dev/null || echo "{}")

  # Extract metadata from model tags/properties if not provided via CLI
  if [[ -z "${task}" ]]; then
    task=$(echo "${model_json}" | jq -r '.tags.task // "auto"')
    log "  Task from model tags: ${task}"
  fi
  if [[ -z "${framework}" ]]; then
    framework=$(echo "${model_json}" | jq -r '.tags.framework // "auto"')
    log "  Framework from model tags: ${framework}"
  fi
  if [[ -z "${threshold}" ]]; then
    threshold=$(echo "${model_json}" | jq -r '.properties.success_threshold // "-1.0"')
    log "  Threshold from model properties: ${threshold}"
  fi

  # ============================================================================
  # Phase 2: Package training code and register environment
  # ============================================================================

  local training_src="$REPO_ROOT/src/training"
  local code_payload="$staging_dir/code"
  local env_file="$staging_dir/environment.yaml"
  mkdir -p "$staging_dir"

  log "Packaging training payload from $training_src"
  prepare_training_payload "$training_src" "$code_payload"

  log "Registering AzureML assets"
  register_environment "$environment_name" "$environment_version" "$image" "$env_file" \
    "$resource_group" "$workspace_name"

  log "Using local code path: $code_payload"
  log "Environment: ${environment_name}:${environment_version} ($image)"

  # ============================================================================
  # Phase 3: Build Azure ML job submission command
  # ============================================================================

  log "Submitting validation job"
  log "  Model: ${model_uri}"
  log "  Task: ${task}"
  log "  Framework: ${framework}"
  log "  Episodes: ${episodes}"
  log "  Threshold: ${threshold}"

  local az_args=(
    az ml job create
    --resource-group "${resource_group}"
    --workspace-name "${workspace_name}"
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

  # Set input values
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
  # Phase 4: Submit the job and report results
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
  log "View in portal: https://ml.azure.com/runs/${job_name_result}?wsid=/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.MachineLearningServices/workspaces/${workspace_name}"

  # Stream logs if requested
  if [[ "${stream_logs}" == "true" ]]; then
    stream_job_logs "${job_name_result}" "${resource_group}" "${workspace_name}"
  fi
}

main "$@"
