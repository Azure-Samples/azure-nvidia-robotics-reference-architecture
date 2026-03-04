---
name: osmo-lerobot-training
description: 'Submit, monitor, analyze, and evaluate LeRobot imitation learning training jobs on OSMO with Azure ML MLflow integration and inference evaluation - Brought to you by microsoft/azure-nvidia-robotics-reference-architecture'
---

# OSMO LeRobot Training

Submit, monitor, analyze, and evaluate LeRobot behavioral cloning training workflows on the OSMO platform. Covers the full lifecycle: job submission, log streaming, Azure ML metric retrieval, training summary generation, and post-training inference evaluation.

Read the skill file `.github/skills/osmo-lerobot-training/SKILL.md` for parameter defaults, GPU configuration, and training duration estimates. Read [references/DEFAULTS.md](references/DEFAULTS.md) for known datasets, GPU profiles, and Azure environment auto-resolution.

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| `osmo` CLI | Workflow submission and monitoring |
| `az` CLI | Azure authentication and model registry |
| `terraform` | Infrastructure output resolution |
| `zip`, `base64` | Training payload packaging |
| Python 3.11+ with `azure-ai-ml`, `mlflow` | Metric retrieval from Azure ML |

Authentication must be configured before any OSMO or Azure ML operations:

```bash
az login
osmo login <service-url> --method dev --username guest
```

## Quick Start

### Train from Azure Blob Storage (typical production flow)

```bash
scripts/submit-osmo-lerobot-training.sh \
  -d my-robot-dataset \
  --from-blob \
  --storage-account mystorageaccount \
  --blob-prefix my-robot-dataset \
  --no-val-split \
  --steps 100000 \
  --batch-size 32 \
  --learning-rate 1e-4 \
  --save-freq 10000 \
  -j my-robot-act-train \
  --experiment-name my-robot-training \
  -r my-robot-act-model
```

### Train from HuggingFace Hub

```bash
scripts/submit-osmo-lerobot-training.sh -d lerobot/aloha_sim_insertion_human
```

### Run Inference After Training

```bash
# OSMO inference (GPU, evaluates against the same dataset)
scripts/submit-osmo-lerobot-inference.sh \
  --from-aml-model \
  --model-name my-robot-act-model \
  --model-version 3 \
  --from-blob-dataset \
  --storage-account mystorageaccount \
  --blob-prefix my-robot-dataset \
  --mlflow-enable \
  --eval-episodes 10 \
  -j my-robot-eval \
  --experiment-name my-robot-inference

# Local inference (CPU/MPS, for quick validation)
python scripts/run-local-lerobot-inference.py \
  --model-name my-robot-act-model \
  --model-version 3 \
  --dataset-dir /path/to/local/dataset \
  --episodes 5 \
  --output-dir outputs/local-eval \
  --device cpu
```

## Post-Submission Browser Monitoring

After every successful training or inference submission, open the OSMO workflow page in VS Code's SimpleBrowser so the user can track progress and access logs directly.

**Steps:**

1. Capture the workflow ID from the submission output (the line `Workflow ID - <id>`).
2. Construct the URL: `http://10.0.5.7/workflows/<workflow-id>`.
3. Open it with the `open_browser_page` tool (VS Code SimpleBrowser).
4. Tell the user that the **Logs** tab on that page streams live output per task (e.g., `lerobot-train`, `lerobot-infer`).

**Example — after training submission output:**

```
Workflow ID - lerobot-training-31
Workflow Overview - http://10.0.5.7/workflows/lerobot-training-31
```

Open: `http://10.0.5.7/workflows/lerobot-training-31`

**Example — after inference submission output:**

```
Workflow ID - lerobot-inference-20
Workflow Overview - http://10.0.5.7/workflows/lerobot-inference-20
```

Open: `http://10.0.5.7/workflows/lerobot-inference-20`

> The page has a **Logs** tab with per-task log streams. For training, select the `lerobot-train` task. For inference, select the `lerobot-infer` task. Use the OSMO CLI (`osmo workflow logs <id> -t <task> -n 100`) as a fallback when the browser is not reachable.

## Parameters Reference

### Training Submission Parameters

| Parameter | Flag | Default | Description |
|-----------|------|---------|-------------|
| Dataset repo ID | `-d`, `--dataset` | (required) | HuggingFace dataset or blob dataset name |
| Policy type | `-p`, `--policy` | `act` | `act` or `diffusion` |
| Job name | `-j`, `--job-name` | `lerobot-act-training` | Unique job identifier |
| Training steps | `--steps` | `100000` | Total training iterations |
| Batch size | `--batch-size` | `32` | Training batch size (64 for 48GB GPUs) |
| Learning rate | `--learning-rate` | `1e-4` | Maps to `--policy.optimizer_lr` internally |
| Save frequency | `--save-freq` | `5000` | Checkpoint interval (model registered at each) |
| Validation split | `--val-split` | `0.1` | Ratio for train/val split |
| No val split | `--no-val-split` | — | Disable validation splitting |
| Register checkpoint | `-r` | (none) | Model name for Azure ML registration |
| From blob | `--from-blob` | `false` | Use Azure Blob Storage as data source |
| Storage account | `--storage-account` | (terraform) | Azure Storage account name |
| Blob prefix | `--blob-prefix` | (none) | Blob path prefix for dataset |

### Inference Submission Parameters

| Parameter | Flag | Default | Description |
|-----------|------|---------|-------------|
| Policy repo ID | `--policy-repo-id` | (required) | HuggingFace repo, or use `--from-aml-model` |
| From AML model | `--from-aml-model` | `false` | Load from AzureML model registry |
| Model name | `--model-name` | (none) | AzureML model registry name |
| Model version | `--model-version` | (none) | AzureML model version |
| Dataset repo ID | `-d`, `--dataset-repo-id` | (none) | HuggingFace dataset |
| From blob dataset | `--from-blob-dataset` | `false` | Download dataset from Azure Blob |
| Eval episodes | `--eval-episodes` | `10` | Number of episodes to evaluate |
| MLflow enable | `--mlflow-enable` | `false` | Log trajectory plots to AzureML |

### GPU Configuration Guidelines

| GPU | VRAM | Recommended Batch Size | Notes |
|-----|------|----------------------|-------|
| A10 | 24GB | 32 | Standard configuration |
| RTX PRO 6000 | 48GB | 64 | Requires `mig.strategy: single` |
| H100 | 80GB | 128 | Standard MIG disabled |

### Azure ML Context

Resolved from CLI flags > environment variables > Terraform outputs:

| Variable | Flag | Env Var |
|----------|------|---------|
| Subscription ID | `--azure-subscription-id` | `AZURE_SUBSCRIPTION_ID` |
| Resource group | `--azure-resource-group` | `AZURE_RESOURCE_GROUP` |
| Workspace name | `--azure-workspace-name` | `AZUREML_WORKSPACE_NAME` |

## Training Completion Estimation

Estimate training duration based on dataset and configuration:

| Dataset Size | Steps | GPU | Approximate Duration |
|-------------|-------|-----|---------------------|
| 20K frames / 64 episodes | 10,000 | A10 | ~30 minutes |
| 20K frames / 64 episodes | 100,000 | A10 | ~5 hours |
| 80K frames / 174 episodes | 100,000 | A10 | ~8 hours |
| 20K frames / 64 episodes | 100,000 | RTX PRO 6000 | ~3 hours |

Checkpoints are registered to AzureML at every `--save-freq` interval. Jobs may be evicted on spot GPU instances — checkpoints already registered remain available for inference even if the job is interrupted.

## OSMO CLI Reference

See [references/REFERENCE.md](references/REFERENCE.md) for full CLI and SDK documentation.

```bash
osmo workflow query <workflow-id>
osmo workflow logs <workflow-id> -n 100
osmo workflow logs <workflow-id> --error
osmo workflow list
osmo workflow cancel <workflow-id>
```

## Key Metrics Logged

| Metric | Description |
|--------|-------------|
| `train/loss` | Training loss per step |
| `train/grad_norm` | Gradient norm |
| `train/learning_rate` | Current learning rate (verify `1e-4` not `1e-5`) |
| `val/loss` | Validation loss (when val split enabled) |
| `gpu_percent` | GPU utilization (when system metrics enabled) |

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `lr: 1e-05` in logs | `LEARNING_RATE` not mapped | Verify `train.py` maps to `--policy.optimizer_lr` |
| `KeyError: chunk_index` | v3.0 dataset not converted | Verify `download_dataset.py` has `patch_info_paths()` |
| `codebase_version` warning | Dataset still marked v3.0 | Verify `patch_info_paths()` sets `codebase_version = "v2.1"` |
| `CUDA_ERROR_NO_DEVICE` | MIG strategy misconfigured | Set `mig.strategy: single` for vGPU nodes |
| VM eviction mid-training | Spot GPU preempted | Checkpoints already registered to AML survive eviction |
| `ImportError: patch_info_paths` | Payload missing training fixes | Ensure `src/training/` includes `download_dataset.py` with `patch_info_paths` |
| OOM during training | Batch size too large | Reduce `--batch-size` (32 for 24GB, 64 for 48GB) |

See [references/REFERENCE.md](references/REFERENCE.md) for detailed debugging commands.

> Brought to you by microsoft/azure-nvidia-robotics-reference-architecture
