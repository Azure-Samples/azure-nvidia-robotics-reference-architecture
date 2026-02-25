#!/usr/bin/env bash
# Offline evaluation entrypoint for OSMO eval container.
#
# Locates the latest pretrained_model checkpoint, runs offline_eval,
# and copies results to the output directory.
#
# Environment variables:
#   CHECKPOINT_DIR     — Root of the checkpoint dataset (default: /data/checkpoint)
#   EVAL_DATASET_DIR   — LeRobot v3 dataset root (default: /data/eval-dataset)
#   EVAL_OUTPUT_DIR    — Output directory for parquet results (default: /output/eval-results)
#   EVAL_EPISODES      — Space-separated episode indices (default: 0)
#   EVAL_DEVICE        — Torch device (default: cuda)
set -euo pipefail

CKPT_ROOT="${CHECKPOINT_DIR:-/data/checkpoint}"
DATASET="${EVAL_DATASET_DIR:-/data/eval-dataset}"
OUTPUT="${EVAL_OUTPUT_DIR:-/output/eval-results}"
EPISODES="${EVAL_EPISODES:-0}"
DEVICE="${EVAL_DEVICE:-cuda}"

# Find the latest pretrained_model directory
CKPT_DIR=$(find "${CKPT_ROOT}" -type d -name "pretrained_model" | sort | tail -1)

if [ -z "${CKPT_DIR}" ]; then
    echo "ERROR: No pretrained_model directory found under ${CKPT_ROOT}"
    echo "Contents of checkpoint root:"
    find "${CKPT_ROOT}" -maxdepth 3 -type d
    exit 1
fi

echo "Running offline evaluation..."
echo "  Checkpoint: ${CKPT_DIR}"
echo "  Dataset:    ${DATASET}"
echo "  Episodes:   ${EPISODES}"
echo "  Device:     ${DEVICE}"
echo "  Output:     ${OUTPUT}"

# shellcheck disable=SC2086
python -m ur10e_deploy.offline_eval \
    --checkpoint "${CKPT_DIR}" \
    --dataset "${DATASET}" \
    --episode ${EPISODES} \
    --device "${DEVICE}" \
    --output "${OUTPUT}"

echo "Evaluation complete — results in ${OUTPUT}"
