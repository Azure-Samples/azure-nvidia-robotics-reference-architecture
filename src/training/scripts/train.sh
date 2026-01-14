#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAINING_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="$(cd "${TRAINING_DIR}/.." && pwd)"

ENV_FILE="${TRAINING_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

declare -a python_cmd
if [[ -n "${PYTHON:-}" ]]; then
  IFS=' ' read -r -a python_cmd <<< "${PYTHON}"
else
  python_cmd=(python)
fi

export PYTHONPATH="${SRC_DIR}:${PYTHONPATH:-}"

# Resolve actual Python executable and environment for uv (handles wrapper scripts like isaaclab.sh -p)
if [[ -z "${UV_PYTHON:-}" ]]; then
  resolved_python="$("${python_cmd[@]}" -c 'import sys; print(sys.executable)' 2>/dev/null || true)"
  resolved_env="$("${python_cmd[@]}" -c 'import sys; print(sys.prefix)' 2>/dev/null || true)"
  if [[ -n "${resolved_python}" && -x "${resolved_python}" ]]; then
    export UV_PYTHON="${resolved_python}"
    if [[ -n "${resolved_env}" && -d "${resolved_env}" ]]; then
      export UV_PROJECT_ENVIRONMENT="${resolved_env}"
    fi
  fi
fi

# Ensure uv scripts directory is on PATH (for pip-installed uv)
if [[ -z "$(command -v uv 2>/dev/null)" ]]; then
  uv_bin_dir="$("${python_cmd[@]}" -c 'import sysconfig; print(sysconfig.get_path("scripts"))' 2>/dev/null || true)"
  if [[ -n "${uv_bin_dir}" && -d "${uv_bin_dir}" ]]; then
    export PATH="${uv_bin_dir}:${PATH}"
  fi
fi

# shellcheck source=lib/pkg-installer.sh
source "${SCRIPT_DIR}/lib/pkg-installer.sh"

# Install requirements with Isaac Sim package protection
install_requirements_safe "${TRAINING_DIR}/requirements.txt" "${python_cmd[*]}"

backend="${TRAINING_BACKEND:-skrl}"
backend_lc=$(printf '%s' "$backend" | tr '[:upper:]' '[:lower:]')

case "${backend_lc}" in
  rsl-rl|rsl_rl|rslrl)
    exec "${python_cmd[@]}" -m training.scripts.launch_rsl_rl "$@"
    ;;
  *)
    exec "${python_cmd[@]}" -m training.scripts.launch "$@"
    ;;
esac
