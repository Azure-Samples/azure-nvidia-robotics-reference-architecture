#!/usr/bin/env bash
#
# Azure ML Training Job Submission Script
#
# This script packages training code, registers the container environment,
# and submits an Azure ML command job using isaaclab-train.yaml as a template.
#
# Key responsibilities:
# 1. Package src/training/ directory into a staging area
# 2. Register the IsaacLab container image as an AzureML environment
# 3. Build a complete training command with all specified parameters
# 4. Override the YAML template with actual runtime values
# 5. Submit the job to Azure ML
#
# The YAML template (isaaclab-train.yaml) provides structure only.
# This script provides all actual values via --set flags.
#
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'EOF'
Usage: submit-azureml-training.sh [options] [-- az-ml-job-flags]

Packages src/training/ into a staging folder, ensures the IsaacLab container
image is registered as an environment, and submits the training command job with
argument parity to the inline OSMO workflow.

AzureML asset options:
  --environment-name NAME       AzureML environment name (default: isaaclab-training-env)
  --environment-version VER     Environment version (default: 2.2.0)
  --image IMAGE                 Container image reference (default: nvcr.io/nvidia/isaac-lab:2.2.0)
  --staging-dir PATH            Directory for intermediate packaging (default: deploy/004-workflow/azureml/scripts/.tmp)
  --assets-only                 Prepare assets without submitting the job.

Workflow parity options:
  -w, --job-file PATH           Path to command job YAML (default: deploy/004-workflow/azureml/jobs/isaaclab-train.yaml)
  -t, --task NAME               IsaacLab task override (default env TASK or Isaac-Velocity-Rough-Anymal-C-v0)
  -n, --num-envs COUNT          Number of environments override (default env NUM_ENVS or 2048)
  -m, --max-iterations N        Maximum iteration override (empty to unset)
  -i, --image IMAGE             Container image override for environment registration
  -c, --checkpoint-uri URI      MLflow checkpoint artifact URI to resume or warm-start from
  -M, --checkpoint-mode MODE    Checkpoint mode (from-scratch, warm-start, resume, fresh)
  -r, --register-checkpoint ID  Azure ML model name for checkpoint registration
      --headless                Force headless rendering (default)
      --gui                     Disable headless flag
  -s, --run-smoke-test          Run the smoke test locally before submitting and enable job flag
      --mode MODE               Execution mode forwarded to launch.py (default: train)

Azure context overrides:
      --subscription-id ID      Azure subscription ID for job inputs (default: $AZURE_SUBSCRIPTION_ID)
      --resource-group NAME     Azure resource group for job inputs (default: $AZURE_RESOURCE_GROUP)
      --workspace-name NAME     Azure ML workspace for job inputs (default: $AZUREML_WORKSPACE_NAME)
      --mlflow-token-retries N  MLflow token refresh retries (default: env or 3)
      --mlflow-http-timeout N   MLflow HTTP timeout seconds (default: env or 60)
      --experiment-name NAME    Azure ML experiment name override
      --compute TARGET          Compute target override for the job YAML
      --instance-type NAME      Azure ML compute instance type for resources.instance_type
      --job-name NAME           Azure ML job name override
      --display-name NAME       Azure ML job display name override
      --stream                  Stream logs after job submission

General:
  -h, --help                    Show this help message and exit.

Environment requirements:
  AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, and AZUREML_WORKSPACE_NAME must be
  configured for az ml operations. Azure CLI ml extension is required.
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

normalize_checkpoint_mode() {
  local mode="$1"
  if [[ -z "$mode" ]]; then
    printf 'from-scratch\n'
    return
  fi
  local lowered
  lowered=$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')
  case "$lowered" in
    from-scratch|warm-start|resume)
      printf '%s\n' "$lowered"
      ;;
    fresh)
      printf 'from-scratch\n'
      ;;
    *)
      fail "Unsupported checkpoint mode: $mode"
      ;;
  esac
}

ensure_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    fail "Environment variable or option required: $name"
  fi
}

normalize_boolean_flag() {
  local value="$1"
  if [[ -z "$value" ]]; then
    printf 'false\n'
    return
  fi
  local lowered
  lowered=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  case "$lowered" in
    1|true|yes|on)
      printf 'true\n'
      ;;
    0|false|no|off)
      printf 'false\n'
      ;;
    *)
      fail "Unsupported boolean flag value: $value"
      ;;
  esac
}

run_local_smoke_test() {
  local repo_root="$1"
  local python_bin="${PYTHON:-python3}"
  if ! command -v "$python_bin" >/dev/null 2>&1; then
    python_bin="python"
    require_command "$python_bin"
  fi
  local src_dir="$repo_root/src"
  log "Running Azure connectivity smoke test before job submission"
  pushd "$repo_root" >/dev/null
  local pythonpath="$src_dir"
  if [[ -n "${PYTHONPATH:-}" ]]; then
    pythonpath="${src_dir}:${PYTHONPATH}"
  fi
  if ! PYTHONPATH="$pythonpath" "$python_bin" -m training.scripts.smoke_test_azure; then
    popd >/dev/null
    fail "Smoke test failed; aborting AzureML submission"
  fi
  popd >/dev/null
  log "Smoke test completed successfully"
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

main() {
  local repo_root
  repo_root=$(resolve_repo_root)

  local environment_name="isaaclab-training-env"
  local environment_version="2.2.0"
  local image="nvcr.io/nvidia/isaac-lab:2.2.0"
  local staging_dir="${STAGING_DIR:-$SCRIPT_DIR/.tmp}"
  local assets_only=0

  local job_file="$repo_root/deploy/004-workflow/azureml/jobs/isaaclab-train.yaml"
  local mode="train"
  local task_value="${TASK:-Isaac-Velocity-Rough-Anymal-C-v0}"
  local num_envs_value="${NUM_ENVS:-2048}"
  local max_iterations_value="${MAX_ITERATIONS:-}"
  local checkpoint_uri_value="${CHECKPOINT_URI:-}"
  local checkpoint_mode_value="${CHECKPOINT_MODE:-from-scratch}"
  local register_checkpoint_value="${REGISTER_CHECKPOINT:-}"
  local run_smoke_test_value="${RUN_AZURE_SMOKE_TEST:-0}"
  local headless="true"

  local subscription_id="${AZURE_SUBSCRIPTION_ID:-}"
  local resource_group="${AZURE_RESOURCE_GROUP:-}"
  local workspace_name="${AZUREML_WORKSPACE_NAME:-}"
  local mlflow_token_retries="${MLFLOW_TRACKING_TOKEN_REFRESH_RETRIES:-3}"
  local mlflow_http_timeout="${MLFLOW_HTTP_REQUEST_TIMEOUT:-60}"

  local experiment_override=""
  local compute_target=""
  local instance_type=""
  local job_name_override=""
  local display_name_override=""
  local stream_logs=0
  local forward_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
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
      --assets-only)
        assets_only=1
        shift
        ;;
      -w|--job-file)
        job_file="$2"
        shift 2
        ;;
      -t|--task)
        task_value="$2"
        shift 2
        ;;
      -n|--num-envs)
        num_envs_value="$2"
        shift 2
        ;;
      -m|--max-iterations)
        max_iterations_value="$2"
        shift 2
        ;;
      -c|--checkpoint-uri)
        checkpoint_uri_value="$2"
        shift 2
        ;;
      -M|--checkpoint-mode)
        checkpoint_mode_value="$2"
        shift 2
        ;;
      -r|--register-checkpoint)
        register_checkpoint_value="$2"
        shift 2
        ;;
      -s|--run-smoke-test)
        run_smoke_test_value="1"
        shift
        ;;
      --headless)
        headless="true"
        shift
        ;;
      --gui|--no-headless)
        headless="false"
        shift
        ;;
      --mode)
        mode="$2"
        shift 2
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
      --mlflow-token-retries)
        mlflow_token_retries="$2"
        shift 2
        ;;
      --mlflow-http-timeout)
        mlflow_http_timeout="$2"
        shift 2
        ;;
      --experiment-name)
        experiment_override="$2"
        shift 2
        ;;
      --compute)
        compute_target="$2"
        shift 2
        ;;
      --instance-type)
        instance_type="$2"
        shift 2
        ;;
      --job-name)
        job_name_override="$2"
        shift 2
        ;;
      --display-name)
        display_name_override="$2"
        shift 2
        ;;
      --stream)
        stream_logs=1
        shift
        ;;
      -i)
        image="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      --)
        shift
        forward_args=("$@")
        break
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done

  require_command az
  require_command rsync
  ensure_ml_extension

  # Validate required Azure context is available
  ensure_value AZURE_SUBSCRIPTION_ID "$subscription_id"
  ensure_value AZURE_RESOURCE_GROUP "$resource_group"
  ensure_value AZUREML_WORKSPACE_NAME "$workspace_name"

  # Normalize user-provided values
  checkpoint_mode_value="$(normalize_checkpoint_mode "$checkpoint_mode_value")"
  run_smoke_test_value="$(normalize_boolean_flag "$run_smoke_test_value")"

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
    "$resource_group" "$workspace_name"

  log "Using local code path: $code_payload"
  log "Environment: ${environment_name}:${environment_version} ($image)"
  log "Reminder: ensure AKS namespace enforces azure.workload.identity/use labels and service account annotations."

  if [[ $assets_only -ne 0 ]]; then
    log "Assets prepared; skipping job submission per --assets-only"
    return 0
  fi

  # ============================================================================
  # Phase 2: Validate job template and run pre-submission checks
  # ============================================================================

  if [[ ! -f "$job_file" ]]; then
    fail "Job file not found: $job_file"
  fi

  if [[ "$run_smoke_test_value" == "true" ]]; then
    run_local_smoke_test "$repo_root"
  fi

  # ============================================================================
  # Phase 3: Build Azure ML job submission command
  # ============================================================================

# ============================================================================
  # Phase 3: Build Azure ML job submission command
  # ============================================================================

  local az_args=(az ml job create --resource-group "$resource_group" --workspace-name "$workspace_name" --file "$job_file")

  # Override core job configuration from template
  az_args+=(--set "code=$code_payload")
  az_args+=(--set "environment=azureml:${environment_name}:${environment_version}")

  if [[ -n "$compute_target" ]]; then
    az_args+=(--set "compute=$compute_target")
  fi
  if [[ -n "$instance_type" ]]; then
    az_args+=(--set "resources.instance_type=$instance_type")
  fi
  if [[ -n "$experiment_override" ]]; then
    az_args+=(--set "experiment_name=$experiment_override")
  fi
  if [[ -n "$job_name_override" ]]; then
    az_args+=(--set "name=$job_name_override")
  fi
  if [[ -n "$display_name_override" ]]; then
    az_args+=(--set "display_name=$display_name_override")
  fi

  # Build the training command dynamically based on provided parameters
  # The command uses ${{inputs.X}} notation to reference job inputs
  local cmd_args="--mode \${{inputs.mode}} --checkpoint-mode \${{inputs.checkpoint_mode}}"

  # Add optional training parameters (only if provided)
  # Each parameter requires both the command argument AND the input value to be set
  if [[ -n "$task_value" ]]; then
    cmd_args="$cmd_args --task \${{inputs.task}}"
    az_args+=(--set "inputs.task=$task_value")
  fi

  if [[ -n "$num_envs_value" ]]; then
    cmd_args="$cmd_args --num_envs \${{inputs.num_envs}}"
    az_args+=(--set "inputs.num_envs=$num_envs_value")
  fi

  if [[ -n "$max_iterations_value" ]]; then
    cmd_args="$cmd_args --max_iterations \${{inputs.max_iterations}}"
    az_args+=(--set "inputs.max_iterations=$max_iterations_value")
  fi

  if [[ -n "$checkpoint_uri_value" ]]; then
    cmd_args="$cmd_args --checkpoint-uri \${{inputs.checkpoint_uri}}"
    az_args+=(--set "inputs.checkpoint_uri=$checkpoint_uri_value")
  fi

  if [[ -n "$register_checkpoint_value" ]]; then
    cmd_args="$cmd_args --register-checkpoint \${{inputs.register_checkpoint}}"
    az_args+=(--set "inputs.register_checkpoint=$register_checkpoint_value")
  fi

  if [[ "$headless" == "true" ]]; then
    cmd_args="$cmd_args --headless"
  fi

  # Override the command from the template with our constructed command
  az_args+=(--set "command=bash src/training/scripts/train.sh $cmd_args")

  # Set all required input values (these are always provided)
  # These are referenced in environment_variables section of the YAML
  az_args+=(--set "inputs.mode=$mode")
  az_args+=(--set "inputs.checkpoint_mode=$checkpoint_mode_value")
  az_args+=(--set "inputs.headless=$headless")
  az_args+=(--set "inputs.subscription_id=$subscription_id")
  az_args+=(--set "inputs.resource_group=$resource_group")
  az_args+=(--set "inputs.workspace_name=$workspace_name")
  az_args+=(--set "inputs.run_azure_smoke_test=$run_smoke_test_value")
  az_args+=(--set "inputs.mlflow_token_refresh_retries=$mlflow_token_retries")
  az_args+=(--set "inputs.mlflow_http_request_timeout=$mlflow_http_timeout")

  # Set environment variables directly (AzureML ${{inputs.X}} syntax doesn't work for env vars)
  az_args+=(--set "environment_variables.AZURE_SUBSCRIPTION_ID=$subscription_id")
  az_args+=(--set "environment_variables.AZURE_RESOURCE_GROUP=$resource_group")
  az_args+=(--set "environment_variables.AZUREML_WORKSPACE_NAME=$workspace_name")
  az_args+=(--set "environment_variables.RUN_AZURE_SMOKE_TEST=$run_smoke_test_value")
  az_args+=(--set "environment_variables.MLFLOW_TRACKING_TOKEN_REFRESH_RETRIES=$mlflow_token_retries")
  az_args+=(--set "environment_variables.MLFLOW_HTTP_REQUEST_TIMEOUT=$mlflow_http_timeout")

  # Add any additional az ml arguments passed through via --
  if [[ ${#forward_args[@]} -gt 0 ]]; then
    az_args+=("${forward_args[@]}")
  fi

  # Request only the job name in the output for easier scripting
  az_args+=(--query "name" -o "tsv")

  # ============================================================================
  # Phase 4: Submit the job and report results
  # ============================================================================

  log "Submitting AzureML job with template $job_file"
  local job_name
  if ! job_name=$("${az_args[@]}"); then
    fail "AzureML job submission failed"
  fi

  log "AzureML job submitted: $job_name"
  log "Download checkpoints via: az ml job download --name $job_name --output-name checkpoints"

  if [[ $stream_logs -ne 0 ]]; then
    log "Streaming logs for job $job_name..."
    az ml job stream --name "$job_name" --resource-group "$resource_group" --workspace-name "$workspace_name"
  fi
}

main "$@"
