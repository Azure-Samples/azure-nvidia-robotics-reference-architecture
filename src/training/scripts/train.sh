#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAINING_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="$(cd "${TRAINING_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON:-python}"

export PYTHONPATH="${SRC_DIR}:${PYTHONPATH:-}"

if ! "${PYTHON_BIN}" -m pip --version >/dev/null 2>&1; then
	if "${PYTHON_BIN}" -m ensurepip --version >/dev/null 2>&1; then
		"${PYTHON_BIN}" -m ensurepip --upgrade
	else
		echo "Error: pip not available and ensurepip failed" >&2
		exit 1
	fi
fi

"${PYTHON_BIN}" -m pip install --no-cache-dir -r "${TRAINING_DIR}/requirements.txt"

if [[ "${RUN_AZURE_SMOKE_TEST:-}" == "1" ]]; then
	echo "Starting smoke test..."
	SMOKE_EXPERIMENT="${AZUREML_SMOKE_EXPERIMENT:-isaaclab-smoke-test}"
	SMOKE_RUN_NAME="${AZUREML_SMOKE_RUN_NAME:-preflight-$(date -u +%Y%m%dT%H%M%SZ)}"

	if [[ -n "${AZUREML_WORKSPACE_NAME:-}" ]]; then
		smoke_test_cmd=(
			"${PYTHON_BIN}" "${SCRIPT_DIR}/smoke-test-azure.py"
			--experiment-name "${SMOKE_EXPERIMENT}"
			--run-name "${SMOKE_RUN_NAME}"
			--metric-name "connectivity"
		)
		echo "Executing smoke test: ${smoke_test_cmd[*]}"
		"${smoke_test_cmd[@]}"
	else
		echo "Skipping smoke test: AZUREML_WORKSPACE_NAME not set"
	fi
	echo "Finished smoke test..."
	exit 0
fi

exec "${PYTHON_BIN}" "${SCRIPT_DIR}/train.py" "$@"
