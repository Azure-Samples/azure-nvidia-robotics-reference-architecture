#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: submit-azureml-training.sh [options]

Packages src/training/ as an AzureML code asset and ensures the NVIDIA IsaacLab
container image is registered as an environment.

Options:
  --code-name NAME            AzureML code asset name (default: isaaclab-training-code)
  --code-version VERSION      Code asset version (default: git SHA or UTC timestamp)
  --environment-name NAME     AzureML environment name (default: isaaclab-training-env)
  --environment-version VER   Environment version (default: 2.2.0)
  --image IMAGE               Container image reference (default: nvcr.io/nvidia/isaac-lab:2.2.0)
  --staging-dir PATH          Directory for intermediate packaging (default: deploy/004-workflow/azureml/.tmp)
  --assets-only               Skip job submission after assets are prepared.
  -h, --help                  Show this help message and exit.

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
      -h|--help)
        usage
        return 0
        ;;
      --)
        shift
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

  if [[ $assets_only -eq 0 ]]; then
    log "Assets prepared; job submission not requested"
  fi
}

main "$@"
