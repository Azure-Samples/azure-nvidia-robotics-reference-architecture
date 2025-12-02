#!/usr/bin/env bash
#
# Azure ML Validation Job Submission Script
#
# This script submits an Azure ML validation job using isaaclab-validate.yaml.
# Task and framework are auto-detected from model metadata when not specified.
#
# Usage:
#   ./submit-azureml-validation.sh --model azureml:isaaclab-anymal:1 [options]
#
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'EOF'
Usage: submit-azureml-validation.sh --model MODEL_URI [options]

Submit an Azure ML validation job to evaluate a trained IsaacLab policy.

Required:
  --model URI                   Azure ML model URI (e.g., azureml:isaaclab-anymal:1)

Options:
  --task TASK                   Override task ID (default: from model metadata)
  --framework FRAMEWORK         Override framework (default: from model metadata)
  --episodes N                  Number of evaluation episodes (default: 100)
  --num-envs N                  Number of parallel environments (default: 64)
  --threshold F                 Override success threshold (default: from metadata)
  --stream                      Stream job logs after submission
  --wait                        Wait for job completion
  --job-file PATH               Path to validation job YAML (default: isaaclab-validate.yaml)
  --compute TARGET              Compute target override
  --experiment-name NAME        Azure ML experiment name override
  --job-name NAME               Azure ML job name override
  -h, --help                    Show this help message

Environment requirements:
  Azure CLI ml extension must be installed and configured.
EOF
}

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# Defaults
MODEL=""
TASK=""
FRAMEWORK=""
EPISODES=100
NUM_ENVS=64
THRESHOLD=""
STREAM=false
WAIT=false
JOB_FILE="${SCRIPT_DIR}/../jobs/isaaclab-validate.yaml"
COMPUTE=""
EXPERIMENT_NAME=""
JOB_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --model)
      MODEL="$2"
      shift 2
      ;;
    --task)
      TASK="$2"
      shift 2
      ;;
    --framework)
      FRAMEWORK="$2"
      shift 2
      ;;
    --episodes)
      EPISODES="$2"
      shift 2
      ;;
    --num-envs)
      NUM_ENVS="$2"
      shift 2
      ;;
    --threshold)
      THRESHOLD="$2"
      shift 2
      ;;
    --stream)
      STREAM=true
      shift
      ;;
    --wait)
      WAIT=true
      shift
      ;;
    --job-file)
      JOB_FILE="$2"
      shift 2
      ;;
    --compute)
      COMPUTE="$2"
      shift 2
      ;;
    --experiment-name)
      EXPERIMENT_NAME="$2"
      shift 2
      ;;
    --job-name)
      JOB_NAME="$2"
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

# Validate required arguments
if [[ -z "${MODEL}" ]]; then
  fail "--model is required (e.g., azureml:isaaclab-anymal:1)"
fi

if [[ ! -f "${JOB_FILE}" ]]; then
  fail "Job file not found: ${JOB_FILE}"
fi

log "Submitting validation job"
log "  Model: ${MODEL}"
log "  Task: ${TASK:-'(from metadata)'}"
log "  Framework: ${FRAMEWORK:-'(from metadata)'}"
log "  Episodes: ${EPISODES}"
log "  Threshold: ${THRESHOLD:-'(from metadata)'}"

# Build job creation command
CMD=(
  az ml job create
  --file "${JOB_FILE}"
  --set "inputs.trained_model.path=${MODEL}"
  --set "inputs.eval_episodes=${EPISODES}"
  --set "inputs.num_envs=${NUM_ENVS}"
)

# Add optional overrides
[[ -n "${TASK}" ]] && CMD+=(--set "inputs.task=${TASK}")
[[ -n "${FRAMEWORK}" ]] && CMD+=(--set "inputs.framework=${FRAMEWORK}")
[[ -n "${THRESHOLD}" ]] && CMD+=(--set "inputs.success_threshold=${THRESHOLD}")
[[ -n "${COMPUTE}" ]] && CMD+=(--set "compute=azureml:${COMPUTE}")
[[ -n "${EXPERIMENT_NAME}" ]] && CMD+=(--set "experiment_name=${EXPERIMENT_NAME}")
[[ -n "${JOB_NAME}" ]] && CMD+=(--set "name=${JOB_NAME}")

# Add streaming/wait flags
if [[ "${STREAM}" == "true" ]]; then
  CMD+=(--stream)
elif [[ "${WAIT}" == "true" ]]; then
  CMD+=(--web)
fi

# Execute
log "Running: ${CMD[*]}"
"${CMD[@]}"
