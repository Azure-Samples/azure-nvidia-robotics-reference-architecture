#!/bin/bash
# Run exported ONNX model against Isaac Sim ant environment
# Usage: ./run-onnx-inference.sh [--video] [--max-steps N]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default paths
ONNX_MODEL="${ONNX_MODEL:-logs/rsl_rl/ant/2025-11-19_21-47-59/exported/policy.onnx}"
TASK="${TASK:-Isaac-Ant-v0}"
NUM_ENVS="${NUM_ENVS:-16}"
MAX_STEPS="${MAX_STEPS:-500}"

# Parse arguments
VIDEO_FLAG=""
USE_GPU_FLAG=""
EXTRA_ARGS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --video)
            VIDEO_FLAG="--video"
            shift
            ;;
        --use-gpu)
            USE_GPU_FLAG="--use-gpu"
            shift
            ;;
        --max-steps)
            MAX_STEPS="$2"
            shift 2
            ;;
        --num-envs)
            NUM_ENVS="$2"
            shift 2
            ;;
        --onnx-model)
            ONNX_MODEL="$2"
            shift 2
            ;;
        *)
            EXTRA_ARGS="$EXTRA_ARGS $1"
            shift
            ;;
    esac
done

echo "=============================================="
echo "ONNX Policy Inference Test"
echo "=============================================="
echo "Task: $TASK"
echo "ONNX Model: $ONNX_MODEL"
echo "Num Envs: $NUM_ENVS"
echo "Max Steps: $MAX_STEPS"
echo "=============================================="

# Check if model exists
if [[ ! -f "$ONNX_MODEL" ]]; then
    echo "ERROR: ONNX model not found at: $ONNX_MODEL"
    echo "Run the export script first:"
    echo "  .venv/bin/python deploy/export_policy.py --checkpoint logs/rsl_rl/ant/2025-11-19_21-47-59/model_2250.pt"
    exit 1
fi

# Run with Isaac Sim Python
~/.local/share/ov/pkg/isaac-sim-4.5.0/python.sh \
    src/training/scripts/rsl_rl/play_onnx.py \
    --task "$TASK" \
    --num_envs "$NUM_ENVS" \
    --onnx-model "$ONNX_MODEL" \
    --max-steps "$MAX_STEPS" \
    --headless \
    $VIDEO_FLAG \
    $USE_GPU_FLAG \
    $EXTRA_ARGS
