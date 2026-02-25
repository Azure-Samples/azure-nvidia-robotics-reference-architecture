<!-- markdownlint-disable-file -->

# OSMO Training Packaging Research

**Date:** 2026-02-23
**Scope:** Package rosbag ACT training pipeline for NVIDIA OSMO instance at 192.168.1.100

## Current Training Pipeline

- `train/train.py` — Standalone ACT training from rosbag data (no lerobot dependency)
- `train/act_model.py` — Pure PyTorch ACT model implementation
- `train/config.yaml` — Training configuration (data paths, model architecture, hyperparameters)
- `train/pyproject.toml` — Python package definition with dependencies

### Dependencies

- `torch>=2.0`, `torchvision>=0.15`
- `rosbags>=0.9` (pure Python rosbag reader, no ROS2 install needed)
- `safetensors>=0.4`, `numpy<2`, `Pillow>=9.0`, `opencv-python-headless>=4.5`
- `pyyaml>=6.0`, `tqdm>=4.60`
- Optional: `azure-identity`, `azure-storage-blob` (for Azure Blob data)

### Data Source

- Rosbags stored in Azure Blob Storage: `https://stosmorbt3dev001.blob.core.windows.net/datasets`
- Also available locally at `rosbag-to-lerobot/local_bags/`
- Training config references `../rosbag-to-lerobot/local_bags` as `bag_dir`

### Output

- Checkpoints at `outputs/train-rosbag-act/checkpoint_NNNNNN/pretrained_model/`
- Contains: `config.json`, `model.safetensors`, normalization stats, pre/post processor JSONs

## NVIDIA OSMO Platform

- Open-source, cloud-native orchestrator for Physical AI workflows
- YAML-based workflow definitions with containerized tasks
- Kubernetes backend; supports heterogeneous compute (GPU clusters, edge devices)
- CLI: `osmo workflow submit my_workflow.yaml`
- Tasks specify: `image`, `command`, `args`, `files` (local upload), `inputs` (dataset), `resources` (GPU/CPU/memory), `credentials` (secrets)

### Workflow YAML Structure

```yaml
workflow:
  name: workflow-name
  resources:
    default:
      gpu: 1
      cpu: 4
      memory: 16Gi
      platform: dgx-a100
  tasks:
  - name: task-name
    image: container-image:tag
    command: ["python"]
    args: ["train.py"]
    files:
    - localpath: local/file.py
      path: /workspace/file.py
    inputs:
    - dataset:
        name: dataset-name
        localpath: ./data
    outputs:
    - dataset:
        name: output-name
    credentials:
      azure_cred:
        AZURE_STORAGE_KEY: azure_storage_key
```

### Submission

```bash
osmo workflow submit workflow.yaml --pool gpu-pool
```

## Selected Approach

Create a self-contained OSMO training package under `train/osmo/`:

1. **Dockerfile** — NVIDIA PyTorch NGC base image with all training deps
2. **osmo-workflow.yaml** — OSMO workflow definition for single-task GPU training
3. **osmo-config.yaml** — OSMO-specific training config (paths adjusted for container)
4. **README.md** — Build, push, and submit instructions targeting 192.168.1.100

### Why This Approach

- OSMO `files` feature uploads training scripts automatically via CLI
- Rosbag data uploaded as a dataset input via `localpath`
- Model checkpoint output as a dataset for downstream consumption
- Single Dockerfile keeps container image focused and reproducible
- OSMO-specific config adjusts paths for container filesystem layout
