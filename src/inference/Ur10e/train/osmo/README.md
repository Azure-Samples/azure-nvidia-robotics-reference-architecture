# OSMO Training Package — UR10e ACT

Run the rosbag ACT training pipeline on an NVIDIA OSMO instance.

## Prerequisites

| Component | Requirement |
|-----------|-------------|
| Docker | 20.10+ with NVIDIA Container Toolkit |
| OSMO CLI | Installed and configured |
| OSMO Instance | Accessible at `192.168.1.100` |
| Rosbag Data | Available at `../rosbag-to-lerobot/local_bags/` |

## 1. Configure OSMO CLI

Point the OSMO CLI at your instance:

```bash
osmo login --url https://192.168.1.100
```

## 2. Build the Container Image

From the `train/` directory:

```bash
docker build -t ur10e-act-train:latest -f osmo/Dockerfile .
```

## 3. Push the Image to Your Registry

Tag and push to a registry accessible by the OSMO cluster:

```bash
# Example: push to a local registry on the OSMO host
docker tag ur10e-act-train:latest 192.168.1.100:5000/ur10e-act-train:latest
docker push 192.168.1.100:5000/ur10e-act-train:latest
```

Then update `osmo-workflow.yaml` to use the full registry path:

```yaml
image: 192.168.1.100:5000/ur10e-act-train:latest
```

## 4. Submit the Workflow

From the `train/` directory (so `localpath` references resolve):

```bash
osmo workflow submit osmo/osmo-workflow.yaml
```

Override parameters at submission time:

```bash
osmo workflow submit osmo/osmo-workflow.yaml \
    --set-env CUDA_VISIBLE_DEVICES=0
```

Target a specific pool:

```bash
osmo workflow submit osmo/osmo-workflow.yaml --pool gpu-pool
```

## 5. Monitor the Job

```bash
# List running workflows
osmo workflow list

# Stream logs from the training task
osmo workflow logs <workflow-id> --task train-act --follow
```

## 6. Retrieve the Trained Model

After training completes, the checkpoint is available as the `ur10e-act-checkpoint` dataset:

```bash
osmo dataset download ur10e-act-checkpoint --output ./checkpoint
```

The output directory contains:

```text
train-rosbag-act/
└── checkpoint_005000/
    └── pretrained_model/
        ├── config.json
        ├── model.safetensors
        ├── policy_preprocessor.json
        ├── policy_preprocessor_step_3_normalizer_processor.safetensors
        ├── policy_postprocessor.json
        ├── policy_postprocessor_step_0_unnormalizer_processor.safetensors
        └── train_config.json
```

## Configuration

Training hyperparameters are in [osmo-config.yaml](osmo-config.yaml). Key settings:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `training.steps` | 5000 | Total training steps |
| `training.batch_size` | 4 | Batch size |
| `training.lr` | 1e-5 | Learning rate |
| `model.chunk_size` | 100 | Action chunk size |
| `data.fps` | 30 | Target sync FPS |

## Container Paths

| Host Path | Container Path | Description |
|-----------|----------------|-------------|
| `rosbag-to-lerobot/local_bags/` | `/data/rosbags` | Input rosbag recordings |
| — | `/output/train-rosbag-act` | Training output checkpoint |
| `train.py` | `/workspace/train.py` | Training script |
| `act_model.py` | `/workspace/act_model.py` | ACT model definition |
| `osmo-config.yaml` | `/workspace/config.yaml` | Training configuration |

## Troubleshooting

**Image not found by OSMO:**
Verify the image is pushed to a registry the OSMO cluster can reach. Check with `docker pull` from a cluster node.

**Out of GPU memory:**
Reduce `training.batch_size` in `osmo-config.yaml` or request a node with more VRAM.

**No rosbag data found:**
Confirm `../rosbag-to-lerobot/local_bags/` contains recording directories with `metadata.yaml` + `.db3` files before submitting.

---

## Multi-GPU DDP Training

Scale training across multiple GPUs using PyTorch DistributedDataParallel with OSMO groups.

### DDP Prerequisites

| Component | Requirement |
|-----------|-------------|
| OSMO Pool | Multiple GPU nodes (or multi-GPU nodes) |
| Container | Same `ur10e-act-train:latest` image |

### Submit DDP Workflow

```bash
osmo workflow submit osmo/osmo-workflow-ddp.yaml --pool gpu-pool
```

The DDP workflow launches 4 workers by default. Each worker runs `torchrun` for NCCL-based gradient synchronisation. Edit `osmo-workflow-ddp.yaml` to change `count` under `groups.workers`.

### DDP Configuration

DDP uses `osmo-config-ddp.yaml` with `num_workers: 4` for faster data loading. The `batch_size` is per-GPU — effective batch size = `batch_size * world_size`.

### Single-GPU Fallback

`train.py` auto-detects DDP mode via the `RANK` environment variable. When not set, it runs in standard single-GPU mode — no code changes needed.

---

## Azure Blob Storage Data Source

Download rosbag data directly from Azure Blob Storage instead of uploading via `localpath`.

### Blob Prerequisites

Create OSMO secrets for Azure Storage access:

```bash
osmo secret create azure-storage-account --value "stosmorbt3dev001"
osmo secret create azure-storage-sas --value "<your-sas-token>"
```

The SAS token needs `Read` and `List` permissions on the target container.

### Submit Blob Workflow

```bash
osmo workflow submit osmo/osmo-workflow-blob.yaml --pool gpu-pool
```

This workflow:

1. Downloads rosbag data from `https://stosmorbt3dev001.blob.core.windows.net/datasets/houston_recordings/` to `/data/rosbags`
2. Runs training with the downloaded data
3. Uploads the checkpoint as the `ur10e-act-checkpoint` dataset

### Blob Configuration

Override blob location via environment variables in `osmo-workflow-blob.yaml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `AZURE_BLOB_CONTAINER` | `datasets` | Blob container name |
| `AZURE_BLOB_PREFIX` | `houston_recordings/` | Prefix within container |
| `BLOB_DEST_DIR` | `/data/rosbags` | Local download destination |

---

## Train → Eval Workflow Chain

Automatically run offline evaluation after training completes.

### Eval Prerequisites

1. Build both container images:

```bash
# Training image
docker build -t ur10e-act-train:latest -f osmo/Dockerfile .

# Evaluation image (needs deploy/ context)
docker build -t ur10e-act-eval:latest -f osmo/Dockerfile.eval \
    --build-context deploy=../deploy .
```

2. Push both images to the OSMO registry.

3. Upload a LeRobot v3 evaluation dataset:

```bash
osmo dataset upload ur10e-eval-dataset ./path/to/lerobot-dataset
```

### Submit Train→Eval Workflow

```bash
osmo workflow submit osmo/osmo-workflow-train-eval.yaml --pool gpu-pool
```

This workflow runs two tasks sequentially:

1. **train-act** — Trains the ACT policy and produces the `ur10e-act-checkpoint` dataset
2. **eval-act** — Loads the trained checkpoint, runs offline inference on the evaluation dataset, and produces parquet files with per-joint MAE and latency metrics

### Eval Configuration

Override evaluation parameters via environment variables in `osmo-workflow-train-eval.yaml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `EVAL_EPISODES` | `0 1 2 3` | Space-separated episode indices |
| `EVAL_DEVICE` | `cuda` | Torch device for inference |

### Eval Output

The `ur10e-eval-results` dataset contains:

```text
episode_000.parquet
episode_001.parquet
...
all_episodes.parquet    # Combined if multiple episodes
```

Each parquet file includes per-step columns:

- `joint_position_*` — Ground-truth joint positions
- `predicted_action_*` — Model-predicted action deltas
- `gt_action_*` — Ground-truth action deltas
- `abs_error_*` — Per-joint absolute error
- `inference_time_s` — Per-step inference latency

---

## Wandb Experiment Tracking

Log training metrics to [Weights & Biases](https://wandb.ai) for visualization and comparison.

### Wandb Setup

1. Create an OSMO secret with your API key:

```bash
osmo secret create wandb-api-key --value "<your-wandb-api-key>"
```

2. Enable wandb in the config file (`osmo-config.yaml`):

```yaml
wandb:
  enabled: true
  project: "ur10e-act-train"
  run_name: null        # auto-generated if null
  tags: ["osmo"]
```

3. Submit the wandb-enabled workflow:

```bash
osmo workflow submit osmo/osmo-workflow-wandb.yaml --pool gpu-pool
```

Or enable wandb on any workflow using CLI overrides:

```bash
osmo workflow submit osmo/osmo-workflow.yaml --pool gpu-pool \
    --set-env PYTHONUNBUFFERED=1
# With --override in the command args:
# python train.py --config /workspace/config.yaml --override wandb.enabled=true
```

### Wandb Behavior

- **DDP mode**: Only rank 0 logs to wandb — no duplicate runs.
- **Logged metrics**: `loss`, `l1_loss`, `kl_loss`, `lr`, and step number.
- **Config snapshot**: The full training config is uploaded as the wandb run config.
- **Conditional import**: `wandb` is only imported when `wandb.enabled: true`. Training works without the package installed when disabled.

---

## Learning Rate Scheduler

Cosine annealing with optional linear warmup.

### Scheduler Configuration

Add or modify these fields in the `training:` section of your config:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `training.scheduler` | `"none"` | `"cosine"` to enable, `"none"` to disable |
| `training.warmup_steps` | `500` | Linear warmup steps before cosine decay |
| `training.min_lr` | `1e-7` | Minimum learning rate at end of schedule |

Example in `osmo-config.yaml`:

```yaml
training:
  lr: 1.0e-5
  scheduler: "cosine"
  warmup_steps: 500
  min_lr: 1.0e-7
```

When `scheduler: "none"` (the default in `config.yaml`), a constant learning rate is used.

---

## Config CLI Overrides

Override any config value at the command line without editing YAML files.

### Usage

```bash
python train.py --config config.yaml \
    --override training.lr=5e-5 \
    --override training.batch_size=8 \
    --override wandb.enabled=true
```

### Override Format

- Dot-notation keys: `training.lr`, `model.chunk_size`, `wandb.enabled`
- Auto type conversion: `true`/`false` → bool, integers → int, decimals/scientific → float, everything else → string
- Multiple `--override` flags can be passed

---

## Hyperparameter Sweep

Run multiple training jobs in parallel with different hyperparameter combinations.

### Default Sweep Grid

The sweep workflow (`osmo-workflow-sweep.yaml`) runs 6 parallel arms across a 3×2 grid:

| Arm | Learning Rate | KL Weight | Output Dataset |
|-----|--------------|-----------|----------------|
| 1 | 1e-5 | 10.0 | `ur10e-act-sweep-lr1e5-kl10` |
| 2 | 5e-5 | 10.0 | `ur10e-act-sweep-lr5e5-kl10` |
| 3 | 1e-4 | 10.0 | `ur10e-act-sweep-lr1e4-kl10` |
| 4 | 1e-5 | 1.0 | `ur10e-act-sweep-lr1e5-kl1` |
| 5 | 5e-5 | 1.0 | `ur10e-act-sweep-lr5e5-kl1` |
| 6 | 1e-4 | 1.0 | `ur10e-act-sweep-lr1e4-kl1` |

### Submit Sweep

```bash
osmo workflow submit osmo/osmo-workflow-sweep.yaml --pool gpu-pool
```

Each arm runs as an independent OSMO task scheduled in parallel. Results are saved to separate output datasets.

### Customizing the Sweep

Edit the `--override` args in each task of `osmo-workflow-sweep.yaml`. You can sweep any config parameter:

```yaml
args:
- |
  python train.py --config /workspace/config.yaml \
    --override training.lr=5e-5 \
    --override training.batch_size=8 \
    --override model.chunk_size=50 \
    --override wandb.enabled=true \
    --override wandb.run_name=sweep-custom-1 \
    && cp -r /output/train-rosbag-act/* {{output}}/
```

### Comparing Results

When wandb is enabled in the sweep, all arms log to the same project (`ur10e-act-train`) with the `sweep` tag. Use the wandb dashboard to compare loss curves and select the best configuration.

Without wandb, download each arm's checkpoint and compare using offline evaluation:

```bash
osmo dataset download ur10e-act-sweep-lr5e5-kl10 --output ./sweep-results/lr5e5-kl10
osmo dataset download ur10e-act-sweep-lr1e4-kl1  --output ./sweep-results/lr1e4-kl1
```
