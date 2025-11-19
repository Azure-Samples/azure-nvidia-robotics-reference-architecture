#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: submit-azureml-training.sh [options] [-- az-ml-job-flags]

Packages src/training/ as an AzureML code asset, ensures the IsaacLab container
image is registered as an environment, and submits the training command job with
argument parity to the inline OSMO workflow.

AzureML asset options:
  --code-name NAME              AzureML code asset name (default: isaaclab-training-code)
  --code-version VERSION        Code asset version (default: git SHA or UTC timestamp)
  --environment-name NAME       AzureML environment name (default: isaaclab-training-env)
  --environment-version VER     Environment version (default: 2.2.0)
  --image IMAGE                 Container image reference (default: nvcr.io/nvidia/isaac-lab:2.2.0)
  --staging-dir PATH            Directory for intermediate packaging (default: deploy/004-workflow/azureml/.tmp)
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
      --tenant-id ID            Azure tenant ID (default: $AZURE_TENANT_ID)
      --client-id ID            Azure client ID for user-assigned identity (default: $AZURE_CLIENT_ID)
      --authority-host URL      Azure authority host (default: https://login.microsoftonline.com)
      --federated-token-file P  Path to federated token file (default: /var/run/secrets/azure/tokens/azure-identity-token)
      --mlflow-token-retries N  MLflow token refresh retries (default: env or 3)
      --mlflow-http-timeout N   MLflow HTTP timeout seconds (default: env or 60)
      --experiment-name NAME    Azure ML experiment name override
      --compute TARGET          Compute target override for the job YAML
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

default_code_version() {
  local sha
  sha=$(git rev-parse --short HEAD 2>/dev/null || true)
  if [[ -n "$sha" ]]; then
    printf '%s\n' "$sha"
    return
  fi
  date -u +%Y%m%d%H%M%S
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
    printf '0\n'
    return
  fi
  local lowered
  lowered=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  case "$lowered" in
    1|true|yes|on)
      printf '1\n'
      ;;
    0|false|no|off)
      printf '0\n'
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
  mkdir -p "$destination"
  rsync -a --delete "$source/" "$destination/"
}

register_code_asset() {
  local name="$1"
  local version="$2"
  local path="$3"
  local create_args=(az ml code create --name "$name" --version "$version" --path "$path")
  if az ml code show --name "$name" --version "$version" >/dev/null 2>&1; then
    log "Updating AzureML code asset ${name}:${version}"
    az ml code update --name "$name" --version "$version" --path "$path" >/dev/null
    return
  fi
  log "Creating AzureML code asset ${name}:${version}"
  "${create_args[@]}" >/dev/null
}

register_environment() {
  local name="$1"
  local version="$2"
  local image="$3"
  local env_file="$4"
  cat >"$env_file" <<EOF
\$schema: https://azuremlschemas.azureedge.net/latest/environment.schema.json
name: $name
version: $version
image: $image
EOF
  if az ml environment show --name "$name" --version "$version" >/dev/null 2>&1; then
    log "Updating AzureML environment ${name}:${version}"
    az ml environment update --file "$env_file" >/dev/null
    return
  fi
  log "Creating AzureML environment ${name}:${version}"
  az ml environment create --file "$env_file" >/dev/null
}

main() {
  local repo_root
  repo_root=$(resolve_repo_root)

  local code_name="isaaclab-training-code"
  local code_version
  code_version="$(default_code_version)"
  local environment_name="isaaclab-training-env"
  local environment_version="2.2.0"
  local image="nvcr.io/nvidia/isaac-lab:2.2.0"
  local staging_dir="$repo_root/deploy/004-workflow/azureml/.tmp"
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
  local headless_flag="--headless"

  local subscription_id="${AZURE_SUBSCRIPTION_ID:-}"
  local resource_group="${AZURE_RESOURCE_GROUP:-}"
  local workspace_name="${AZUREML_WORKSPACE_NAME:-}"
  local tenant_id="${AZURE_TENANT_ID:-}"
  local client_id="${AZURE_CLIENT_ID:-}"
  local authority_host="${AZURE_AUTHORITY_HOST:-https://login.microsoftonline.com}"
  local federated_token_file="${AZURE_FEDERATED_TOKEN_FILE:-/var/run/secrets/azure/tokens/azure-identity-token}"
  local mlflow_token_retries="${MLFLOW_TRACKING_TOKEN_REFRESH_RETRIES:-3}"
  local mlflow_http_timeout="${MLFLOW_HTTP_REQUEST_TIMEOUT:-60}"

  local experiment_override=""
  local compute_target=""
  local job_name_override=""
  local display_name_override=""
  local stream_logs=0
  local forward_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --code-name)
        code_name="$2"
        shift 2
        ;;
      --code-version)
        code_version="$2"
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
        headless_flag="--headless"
        shift
        ;;
      --gui|--no-headless)
        headless_flag=""
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
      --tenant-id)
        tenant_id="$2"
        shift 2
        ;;
      --client-id)
        client_id="$2"
        shift 2
        ;;
      --authority-host)
        authority_host="$2"
        shift 2
        ;;
      --federated-token-file)
        federated_token_file="$2"
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

  ensure_value AZURE_SUBSCRIPTION_ID "$subscription_id"
  ensure_value AZURE_RESOURCE_GROUP "$resource_group"
  ensure_value AZUREML_WORKSPACE_NAME "$workspace_name"

  checkpoint_mode_value="$(normalize_checkpoint_mode "$checkpoint_mode_value")"
  run_smoke_test_value="$(normalize_boolean_flag "$run_smoke_test_value")"

  local training_src="$repo_root/src/training"
  local code_payload="$staging_dir/code"
  local env_file="$staging_dir/environment.yaml"
  mkdir -p "$staging_dir"

  log "Packaging training payload from $training_src"
  prepare_training_payload "$training_src" "$code_payload"

  log "Registering AzureML assets"
  register_code_asset "$code_name" "$code_version" "$code_payload"
  register_environment "$environment_name" "$environment_version" "$image" "$env_file"

  log "Code asset: ${code_name}:${code_version}"
  log "Environment: ${environment_name}:${environment_version} ($image)"
  log "Reminder: ensure AKS namespace enforces azure.workload.identity/use labels and service account annotations."

  if [[ $assets_only -ne 0 ]]; then
    log "Assets prepared; skipping job submission per --assets-only"
    return 0
  fi

  if [[ ! -f "$job_file" ]]; then
    fail "Job file not found: $job_file"
  fi

  if [[ "$run_smoke_test_value" == "1" ]]; then
    run_local_smoke_test "$repo_root"
  fi

  local az_args=(az ml job create --file "$job_file" --query name -o tsv)
  az_args+=(--set "code=azureml:${code_name}@${code_version}")
  az_args+=(--set "environment=azureml:${environment_name}@${environment_version}")
  if [[ -n "$compute_target" ]]; then
    az_args+=(--set "compute=$compute_target")
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

  az_args+=(--set "inputs.mode.value=$mode")
  if [[ -n "$task_value" ]]; then
    az_args+=(--set "inputs.task.value=$task_value")
  else
    az_args+=(--set "inputs.task.value=")
  fi
  if [[ -n "$num_envs_value" ]]; then
    az_args+=(--set "inputs.num_envs.value=$num_envs_value")
  fi
  if [[ -n "$max_iterations_value" ]]; then
    az_args+=(--set "inputs.max_iterations.value=$max_iterations_value")
  else
    az_args+=(--set "inputs.max_iterations.value=")
  fi
  if [[ -n "$checkpoint_uri_value" ]]; then
    az_args+=(--set "inputs.checkpoint_uri.value=$checkpoint_uri_value")
  else
    az_args+=(--set "inputs.checkpoint_uri.value=")
  fi
  az_args+=(--set "inputs.checkpoint_mode.value=$checkpoint_mode_value")
  if [[ -n "$register_checkpoint_value" ]]; then
    az_args+=(--set "inputs.register_checkpoint.value=$register_checkpoint_value")
  else
    az_args+=(--set "inputs.register_checkpoint.value=")
  fi
  az_args+=(--set "inputs.run_azure_smoke_test.value=$run_smoke_test_value")
  if [[ -n "$headless_flag" ]]; then
    az_args+=(--set "inputs.headless_flag.value=$headless_flag")
  else
    az_args+=(--set "inputs.headless_flag.value=")
  fi
  az_args+=(--set "inputs.subscription_id.value=$subscription_id")
  az_args+=(--set "inputs.resource_group.value=$resource_group")
  az_args+=(--set "inputs.workspace_name.value=$workspace_name")
  az_args+=(--set "inputs.client_id.value=$client_id")
  az_args+=(--set "inputs.tenant_id.value=$tenant_id")
  az_args+=(--set "inputs.authority_host.value=$authority_host")
  az_args+=(--set "inputs.federated_token_file.value=$federated_token_file")
  az_args+=(--set "inputs.mlflow_token_refresh_retries.value=$mlflow_token_retries")
  az_args+=(--set "inputs.mlflow_http_request_timeout.value=$mlflow_http_timeout")

  if [[ ${#forward_args[@]} -gt 0 ]]; then
    az_args+=("${forward_args[@]}")
  fi
  if [[ $stream_logs -ne 0 ]]; then
    az_args+=(--stream)
  fi

  log "Submitting AzureML job with template $job_file"
  local job_name
  if ! job_name=$("${az_args[@]}"); then
    fail "AzureML job submission failed"
  fi

  log "AzureML job submitted: $job_name"
  log "Download checkpoints via: az ml job download --name $job_name --output-name checkpoints"
}

main "$@"
