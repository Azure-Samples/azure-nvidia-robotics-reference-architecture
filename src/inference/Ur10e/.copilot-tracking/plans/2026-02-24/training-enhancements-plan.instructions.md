<!-- markdownlint-disable-file -->

# Implementation Plan: Training Pipeline Enhancements

## Overview and Objectives

### User Requirements

1. Wandb/MLflow experiment tracking with OSMO credential support
2. Learning rate scheduler for improved convergence
3. OSMO hyperparameter sweep workflow for automated grid search

### Derived Objectives

- All changes backward compatible — existing configs work unchanged
- DDP-aware: only rank 0 logs to wandb
- Scheduler disabled by default (`scheduler: "none"`)

## Context Summary

- Research: `.copilot-tracking/research/2026-02-24/training-enhancements-research.md`
- Training script: `train/train.py` (~790 lines, has DDP support)
- Config files: `train/config.yaml`, `train/osmo/osmo-config.yaml`, `train/osmo/osmo-config-ddp.yaml`
- OSMO workflows: `train/osmo/osmo-workflow*.yaml`
- Dockerfile: `train/osmo/Dockerfile`

## Implementation Checklist

### Phase A: Wandb Experiment Tracking <!-- parallelizable: false -->

- [ ] A1. Add wandb integration to `train/train.py`
  - Import wandb conditionally
  - Add `_init_wandb()` helper: reads config, inits run, logs config
  - Add `wandb.log()` calls in training loop (loss, l1, kl, lr, step)
  - Add `wandb.finish()` at end
  - Gate on `is_main` and `wandb.enabled` config flag
- [ ] A2. Add `wandb` section to config files
  - `config.yaml`: `wandb.enabled: false` (local default)
  - `osmo-config.yaml`: `wandb.enabled: false`
- [ ] A3. Add `wandb` to Dockerfile pip install
- [ ] A4. Add wandb credential to a new `osmo-workflow-wandb.yaml` variant
  - OSMO secret `wandb-api-key` → `WANDB_API_KEY` env var

### Phase B: Learning Rate Scheduler <!-- parallelizable: true -->

- [ ] B1. Add scheduler logic to `train/train.py`
  - Create `_build_scheduler()` helper
  - Cosine annealing with linear warmup via LambdaLR
  - Call `scheduler.step()` after each optimizer step
  - Log current LR in training loop
- [ ] B2. Add scheduler config fields to all config YAMLs
  - `training.scheduler: "none"` (default, backward compat)
  - `training.warmup_steps: 500`
  - `training.min_lr: 1.0e-7`

### Phase C: Hyperparameter Sweep <!-- parallelizable: true -->

- [ ] C1. Add `--override` CLI arg to `train/train.py`
  - Accepts `key=value` pairs (dot-notation: `training.lr=5e-5`)
  - Applies overrides to loaded config dict
- [ ] C2. Create `train/osmo/osmo-workflow-sweep.yaml`
  - Multiple parallel tasks with different env-var overrides
  - Each task uses the same image and dataset
  - Separate output datasets per sweep run

### Phase D: Documentation <!-- parallelizable: false -->

- [ ] D1. Update `train/osmo/README.md`
  - Add wandb section with secret setup
  - Add scheduler configuration section
  - Add sweep workflow section

## Dependencies

- wandb (NGC pre-installed, add to Dockerfile explicitly)

## Success Criteria

- train.py runs unchanged with old configs (no wandb, no scheduler)
- wandb logs appear when enabled with valid API key
- LR follows warmup + cosine curve
- Sweep workflow spawns parallel tasks
