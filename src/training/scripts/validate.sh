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

# shellcheck source=lib/pkg-installer.sh
source "${SCRIPT_DIR}/lib/pkg-installer.sh"

# Install requirements with Isaac Sim package protection
install_requirements_safe "${TRAINING_DIR}/requirements.txt" "${python_cmd[*]}"

exec "${python_cmd[@]}" -m training.scripts.policy_evaluation "$@"
