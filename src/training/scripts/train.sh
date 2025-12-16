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

if ! "${python_cmd[@]}" -m pip --version >/dev/null 2>&1; then
  if "${python_cmd[@]}" -m ensurepip --version >/dev/null 2>&1; then
    "${python_cmd[@]}" -m ensurepip --upgrade
  else
    echo "Error: pip not available and ensurepip failed" >&2
    exit 1
  fi
fi

"${python_cmd[@]}" -m pip install --no-cache-dir -r "${TRAINING_DIR}/requirements.txt"

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
