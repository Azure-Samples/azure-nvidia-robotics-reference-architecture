#!/usr/bin/env bash
# Submit minimal SKRL training test workflow via OSMO dataset injection
# No Azure ML, no MLflow — pure Isaac Lab + SKRL diagnostic test
set -o errexit -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")"
TMP_DIR="$SCRIPT_DIR/.tmp"
STAGING_DIR="$TMP_DIR/osmo-dataset-staging"

source "$REPO_ROOT/deploy/002-setup/lib/common.sh"

show_help() {
  cat << 'EOF'
Usage: submit-skrl-test.sh [OPTIONS]

Submit a minimal SKRL training test workflow via OSMO.
No MLflow, no Azure libraries — just Isaac Lab + SKRL with diagnostic logging.

OPTIONS:
    -t, --task NAME           IsaacLab task (default: Isaac-Velocity-Rough-Anymal-C-v0)
    -n, --num-envs COUNT      Number of environments (default: 16)
    -m, --max-iterations N    Maximum iterations (default: 5)
    -i, --image IMAGE         Container image (default: nvcr.io/nvidia/isaac-lab:2.3.2)
        --use-local-osmo      Use local osmo-dev CLI
    -h, --help                Show this help message
EOF
}

task="${TASK:-Isaac-Velocity-Rough-Anymal-C-v0}"
num_envs="${NUM_ENVS:-16}"
max_iterations="${MAX_ITERATIONS:-5}"
image="${IMAGE:-nvcr.io/nvidia/isaac-lab:2.3.2}"
use_local_osmo=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)           show_help; exit 0 ;;
    -t|--task)           task="$2"; shift 2 ;;
    -n|--num-envs)       num_envs="$2"; shift 2 ;;
    -m|--max-iterations) max_iterations="$2"; shift 2 ;;
    -i|--image)          image="$2"; shift 2 ;;
    --use-local-osmo)    use_local_osmo=true; shift ;;
    *)                   fatal "Unknown option: $1" ;;
  esac
done

[[ "$use_local_osmo" == "true" ]] && activate_local_osmo
require_tools osmo rsync

workflow="$REPO_ROOT/workflows/osmo/skrl-test.yaml"
[[ -f "$workflow" ]] || fatal "Workflow template not found: $workflow"

training_path="$REPO_ROOT/src/training"
[[ -d "$training_path" ]] || fatal "Training directory not found: $training_path"

# Stage training folder (exclude cache/build artifacts)
info "Staging training folder..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

amlignore_file="$REPO_ROOT/src/.amlignore"
rsync_excludes=()
if [[ -f "$amlignore_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line%/}"
    rsync_excludes+=("--exclude=$line")
  done < "$amlignore_file"
fi

rsync -a --delete "${rsync_excludes[@]}" "$training_path/" "$STAGING_DIR/training/"

workflow_dir="$(dirname "$workflow")"
rel_training_path="$(python3 -c "import os.path; print(os.path.relpath('$STAGING_DIR/training', '$workflow_dir'))")"

info "Submitting SKRL test workflow..."
info "  Task: $task"
info "  Num envs: $num_envs"
info "  Max iterations: $max_iterations"
info "  Image: $image"

osmo workflow submit "$workflow" \
  --set-string \
  "image=$image" \
  "task=$task" \
  "num_envs=$num_envs" \
  "max_iterations=$max_iterations" \
  "training_localpath=$rel_training_path"

info "SKRL test workflow submitted"
