<!-- markdownlint-disable-file -->

# Research: Training Pipeline Enhancements (Logging, Scheduler, Sweep)

## Scope

1. **Wandb Experiment Tracking** — Loss curves, metrics, hyperparams logged to W&B
2. **Learning Rate Scheduler** — Cosine annealing with linear warmup
3. **OSMO Hyperparameter Sweep** — Parallel training runs with varied configs

## 1. Wandb Experiment Tracking

### Current State

- `train.py` logs to Python `logging` only — no experiment tracking
- NGC `nvcr.io/nvidia/pytorch:24.07-py3` has `wandb` pre-installed
- No `wandb` in `pyproject.toml` dependencies

### Selected Approach: Wandb

- Lightweight integration: `wandb.init()` at start, `wandb.log()` in loop, `wandb.finish()` at end
- Optional: only activates when `training.wandb.enabled: true` in config
- DDP-aware: only rank 0 logs to wandb
- OSMO credential: `WANDB_API_KEY` secret
- Config logged as wandb.config for run comparison

### Alternative Considered

- MLflow: Heavier server requirement, more complex setup for OSMO. Rejected.
- TensorBoard: Good but lacks remote dashboard without extra infra. Rejected.

## 2. Learning Rate Scheduler

### Current State

- Constant LR throughout training: `lr: 1.0e-5`, `lr_backbone: 1.0e-5`
- No `torch.optim.lr_scheduler` usage anywhere
- ACT paper (Zhao et al.) uses constant LR, but longer runs benefit from cosine decay

### Selected Approach: Cosine Annealing with Linear Warmup

- Linear warmup from 0 to `lr` over `warmup_steps`
- Cosine decay from `lr` to `min_lr` over remaining steps
- Implemented via `torch.optim.lr_scheduler.LambdaLR` with custom lambda
- Config fields: `scheduler: "cosine"`, `warmup_steps: 500`, `min_lr: 1.0e-7`
- Backward compatible: `scheduler: "none"` preserves current constant LR behavior

### Alternative Considered

- StepLR: Too aggressive for small datasets. Rejected.
- OneCycleLR: Requires careful max_lr tuning, less forgiving. Rejected.

## 3. OSMO Hyperparameter Sweep

### Current State

- Single OSMO workflow runs one training configuration
- No sweep or grid search capability

### Selected Approach: Multi-Task Sweep Workflow

Create `osmo-workflow-sweep.yaml` with multiple tasks, each with different environment variable overrides that train.py reads. Train.py already reads config from YAML — add CLI overrides for sweep params.

Add `--override` CLI arg to train.py that accepts `key=value` pairs to override config values. The sweep workflow spawns N parallel tasks with different overrides.

### Sweep Parameters

Default sweep grid:
- `training.lr`: [1e-5, 5e-5, 1e-4]
- `training.kl_weight`: [1.0, 10.0]
- `training.batch_size`: [4, 8]

## Success Criteria

- [ ] Wandb logging activates when config enables it, silent when disabled
- [ ] LR scheduler produces correct warmup + cosine curve
- [ ] Sweep workflow spawns parallel tasks with different configs
- [ ] All existing functionality preserved (backward compatible)
