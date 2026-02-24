#!/bin/bash
set -euo pipefail

echo "=== LeRobot AzureML Training ==="
echo "Dataset: ${DATASET_REPO_ID}"
echo "Policy Type: ${POLICY_TYPE}"
echo "Job Name: ${JOB_NAME}"
echo "Output Dir: ${OUTPUT_DIR}"
echo "Logging: Azure ML MLflow"
echo "Val Split: ${VAL_SPLIT:-0.1}"
echo "System Metrics: ${SYSTEM_METRICS:-true}"
if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
  echo "Data Source: Azure Blob (${STORAGE_ACCOUNT}/${STORAGE_CONTAINER}/${BLOB_PREFIX})"
else
  echo "Data Source: HuggingFace Hub"
fi

echo "Installing system dependencies..."
if command -v apt-get &>/dev/null; then
  apt-get update -qq && apt-get install -y -qq \
    ffmpeg \
    libgl1-mesa-glx \
    libglib2.0-0 \
    build-essential \
    gcc \
    unzip \
    python3-dev || echo "WARNING: apt-get install failed (non-root?); continuing with available packages"
else
  echo "WARNING: apt-get not available; skipping system package installation"
fi

echo "Installing UV package manager..."
pip install --quiet uv

LEROBOT_PKG="lerobot"
if [[ -n "${LEROBOT_VERSION:-}" && "${LEROBOT_VERSION}" != "latest" ]]; then
  LEROBOT_PKG="lerobot==${LEROBOT_VERSION}"
fi

PIP_PACKAGES=(
  "${LEROBOT_PKG}" huggingface-hub
  azure-identity azure-ai-ml azureml-mlflow "mlflow>=2.8.0"
  psutil pynvml
)

if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
  PIP_PACKAGES+=(azure-storage-blob pyarrow)
fi

echo "Installing LeRobot ${LEROBOT_VERSION:-latest} and dependencies..."
if command -v uv &>/dev/null; then
  uv pip install "${PIP_PACKAGES[@]}" --system
else
  pip install --quiet --no-cache-dir "${PIP_PACKAGES[@]}"
fi

ARCHIVE_PATH="/tmp/lerobot_payload.zip"
PAYLOAD_ROOT="${PAYLOAD_ROOT:-/workspace/lerobot_payload}"
mkdir -p "${PAYLOAD_ROOT}"
if [[ -z "${ENCODED_ARCHIVE:-}" ]]; then
  echo "ERROR: ENCODED_ARCHIVE is not set or empty; training payload is required." >&2
  exit 1
fi
printf '%s' "${ENCODED_ARCHIVE}" | base64 -d > "${ARCHIVE_PATH}"
unzip -oq "${ARCHIVE_PATH}" -d "${PAYLOAD_ROOT}"
export PYTHONPATH="${PAYLOAD_ROOT}/src:${PYTHONPATH:-}"
echo "Training scripts unpacked to ${PAYLOAD_ROOT}/src"

TRAIN_ARGS=()

if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
  echo "Downloading dataset from Azure Blob Storage..."
  python3 -m training.scripts.lerobot.download_dataset

  FULL_DATASET_PATH="${DATASET_ROOT}/${DATASET_REPO_ID}"
  echo "Dataset downloaded to: ${FULL_DATASET_PATH}"
  TRAIN_ARGS+=(
    "--dataset.root=${FULL_DATASET_PATH}"
    "--dataset.use_imagenet_stats=false"
    "--dataset.video_backend=pyav"
    "--tolerance_s=0.04"
  )
fi

echo "Starting LeRobot training..."
python3 -m training.scripts.lerobot.train "${TRAIN_ARGS[@]}"

echo "=== Training Complete ==="
ls -la "${OUTPUT_DIR}/" 2>/dev/null || true

if [[ -n "${REGISTER_CHECKPOINT:-}" && -n "${AZURE_SUBSCRIPTION_ID:-}" && -n "${AZURE_RESOURCE_GROUP:-}" && -n "${AZUREML_WORKSPACE_NAME:-}" ]]; then
  echo "=== Uploading Checkpoints to Azure ML ==="
  python3 -c "from training.scripts.lerobot.checkpoints import upload_checkpoints_to_azure_ml; upload_checkpoints_to_azure_ml()"
  echo "=== Checkpoint Upload Complete ==="
fi
