# UR10e Offline Inference Evaluation

Evaluate a trained ACT policy checkpoint against LeRobot episode data before deploying to the physical UR10e. The script loads initial joint positions from the training dataset, runs step-by-step inference with ground-truth observations, and writes predicted actions alongside ground truth into parquet files.

## 📋 Prerequisites

| Component | Version | Install                         |
| --------- | ------- | ------------------------------- |
| Python    | 3.11+   | `uv venv .venv --python 3.11`   |
| lerobot   | 0.3.2   | `uv pip install lerobot==0.3.2` |
| pyarrow   | 14+     | `uv pip install pyarrow`        |
| av        | 12+     | `uv pip install av`             |
| torch     | 2.0+    | Installed with lerobot          |

Install all dependencies from the repository root:

```bash
uv venv .venv --python 3.11
source .venv/bin/activate
uv pip install lerobot==0.3.2 pyarrow av matplotlib numpy safetensors
```

## 🚀 Quick Start

Run from the `src/inference/Ur10e/deploy` directory:

```bash
cd src/inference/Ur10e/deploy

python -m ur10e_deploy.offline_eval \
  --checkpoint ../../../../outputs/train-houston-ur10e/checkpoints/050000/pretrained_model \
  --dataset ../../../../tmp/houston_lerobot_fixed \
  --episode 0 \
  --device mps
```

Results are written to `tmp/inference_results/episode_000.parquet`.

## 🏗️ How It Works

```text
┌─────────────────────┐    ┌───────────────────┐    ┌─────────────────┐
│  LeRobot Dataset    │    │  ACT Policy       │    │  Parquet Output │
│  (parquet + mp4)    │───▶│  from_pretrained  │───▶│  (per-step log) │
│                     │    │  select_action()  │    │                 │
│  observation.state  │    │                   │    │  joint_position │
│  action (gt)        │    │  Norm stats in    │    │  predicted_action│
│  video frames       │    │  model.safetensors│    │  gt_action      │
└─────────────────────┘    └───────────────────┘    │  abs_error      │
                                                    │  inference_time │
                                                    └─────────────────┘
```

At each step:

1. Read ground-truth joint state and video frame from the dataset
2. Feed them to the ACT policy (teacher-forcing)
3. Compare predicted action delta against ground-truth action delta
4. Record joint positions, predicted actions, ground-truth actions, absolute error, and inference latency

The initial joint positions come directly from the episode's first frame in the dataset. Normalization statistics (mean/std) are embedded in `model.safetensors` — no separate preprocessor files needed.

## ⚙️ CLI Parameters

| Parameter       | Default                 | Description                                     |
| --------------- | ----------------------- | ----------------------------------------------- |
| `--checkpoint`  | (required)              | Path to `pretrained_model` directory            |
| `--dataset`     | (required)              | Path to LeRobot v3 dataset root                 |
| `--episode`     | `0`                     | Episode index(es) to evaluate (space-separated) |
| `--start-frame` | `0`                     | Starting frame within each episode              |
| `--num-steps`   | all frames              | Max inference steps per episode                 |
| `--device`      | `mps`                   | Torch device: `cuda`, `cpu`, or `mps`           |
| `--output`      | `tmp/inference_results` | Output directory for parquet files              |

## 📦 Output Schema

Each parquet file contains one row per inference step with 29 columns:

| Column Group         | Columns                                                                     | Type      |
| -------------------- | --------------------------------------------------------------------------- | --------- |
| Metadata             | `step`, `frame_index`, `timestamp`, `episode_index`                         | int/float |
| Timing               | `inference_time_s`                                                          | float     |
| Joint positions      | `joint_position_{shoulder_pan,shoulder_lift,elbow,wrist_1,wrist_2,wrist_3}` | float     |
| Predicted actions    | `predicted_action_{shoulder_pan,...,wrist_3}`                               | float     |
| Ground-truth actions | `gt_action_{shoulder_pan,...,wrist_3}`                                      | float     |
| Absolute error       | `abs_error_{shoulder_pan,...,wrist_3}`                                      | float     |

## 🔍 Examples

### Evaluate a single episode

```bash
python -m ur10e_deploy.offline_eval \
  --checkpoint ../../../../outputs/train-houston-ur10e/checkpoints/050000/pretrained_model \
  --dataset ../../../../tmp/houston_lerobot_fixed \
  --episode 0 \
  --device mps \
  --output ../../../../tmp/inference_results
```

### Evaluate multiple episodes

```bash
python -m ur10e_deploy.offline_eval \
  --checkpoint ../../../../outputs/train-houston-ur10e/checkpoints/050000/pretrained_model \
  --dataset ../../../../tmp/houston_lerobot_fixed \
  --episode 0 1 2 3 4 \
  --device mps \
  --output ../../../../tmp/inference_results
```

This writes per-episode files (`episode_000.parquet`, `episode_001.parquet`, ...) plus a combined `all_episodes.parquet`.

### Evaluate a subset of frames

```bash
python -m ur10e_deploy.offline_eval \
  --checkpoint ../../../../outputs/train-houston-ur10e/checkpoints/050000/pretrained_model \
  --dataset ../../../../tmp/houston_lerobot_fixed \
  --episode 0 \
  --start-frame 100 \
  --num-steps 200 \
  --device mps
```

### Read results in Python

```python
import pyarrow.parquet as pq

table = pq.read_table("tmp/inference_results/episode_000.parquet")
print(f"Rows: {table.num_rows}, Columns: {table.num_columns}")

# Per-joint MAE
import numpy as np
for joint in ["shoulder_pan", "shoulder_lift", "elbow", "wrist_1", "wrist_2", "wrist_3"]:
    errors = table.column(f"abs_error_{joint}").to_numpy()
    print(f"  {joint}: MAE={np.mean(errors):.6f} rad")
```

## 📤 Expected Output

```text
12:00:01 INFO  Loading ACT policy from .../050000/pretrained_model ...
12:00:02 INFO  No separate preprocessor files found — using normalization stats embedded in model weights
12:00:02 INFO  Policy loaded — 51.6M parameters on mps
12:00:02 INFO  Episode 0: 426 frames, state shape (426, 6)
12:00:02 INFO  Initial joint state (episode 0, frame 0): [-0.160  1.525 -2.226 -2.248 -1.593 -2.774]
12:00:02 INFO  Running inference: frames 0–425 (425 steps)
12:00:03 INFO    Step 1/425 — inference 847.3 ms
12:00:03 INFO    Step 100/425 — inference 1.5 ms
12:00:03 INFO    Step 400/425 — inference 1.6 ms
12:00:03 INFO  --- Episode 0 Summary ---
12:00:03 INFO    Steps evaluated: 425
12:00:03 INFO    Overall MAE: 0.000292 rad
12:00:03 INFO    Mean inference latency: 4.4 ms
12:00:03 INFO    Realtime capable (<33 ms): yes
12:00:03 INFO  Results written to tmp/inference_results/episode_000.parquet (425 rows)
```

> [!NOTE]
> The first inference step is slow (~800 ms) due to MPS/CUDA kernel compilation. Subsequent steps run at ~1.5 ms on Apple Silicon.

## 🔧 Checkpoint Formats

The offline evaluator supports two checkpoint formats:

| Format               | Files Present                                           | Norm Stats Source          |
| -------------------- | ------------------------------------------------------- | -------------------------- |
| Training checkpoint  | `config.json`, `model.safetensors`, `train_config.json` | Embedded in model weights  |
| Converted checkpoint | Above + `policy_preprocessor_*.safetensors`             | Separate safetensors files |

The `050000/pretrained_model` checkpoint uses the training format — normalization mean/std values are stored inside `model.safetensors` as ParameterDict buffers in `normalize_inputs`, `normalize_targets`, and `unnormalize_outputs`.
