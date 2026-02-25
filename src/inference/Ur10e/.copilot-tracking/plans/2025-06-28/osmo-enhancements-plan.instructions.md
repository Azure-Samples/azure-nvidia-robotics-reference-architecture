<!-- markdownlint-disable-file -->

# Implementation Plan: OSMO Training Enhancements

## Overview and Objectives

### User Requirements

1. Multi-GPU distributed training (DDP) for the OSMO ACT training pipeline
2. Azure Blob Storage integration for direct dataset access without local upload
3. Train→Eval workflow chain for automated post-training evaluation

### Derived Objectives

- Keep train.py backward-compatible with single-GPU mode
- Minimize Dockerfile changes — extend, don't replace
- All new OSMO workflows follow conventions from the existing osmo-workflow.yaml

## Context Summary

- Research: `.copilot-tracking/research/2025-06-28/osmo-enhancements-research.md`
- Existing OSMO files: `train/osmo/Dockerfile`, `osmo-config.yaml`, `osmo-workflow.yaml`, `README.md`
- Training script: `train/train.py` (750 lines, single-GPU)
- Eval script: `deploy/ur10e_deploy/offline_eval.py` (~390 lines)

## Implementation Checklist

### Phase A: Multi-GPU DDP Support <!-- parallelizable: false -->

- [ ] A1. Add DDP support to `train/train.py`
  - Add `torch.distributed` imports and init/cleanup helpers
  - Auto-detect DDP via `RANK` env var
  - Replace shuffle with `DistributedSampler` when DDP active
  - Wrap model with `DistributedDataParallel`
  - Gate checkpoint saving and logging on rank 0
  - Add `sampler.set_epoch()` call
  - Unwrap `model.module` for checkpoint saving under DDP
- [ ] A2. Create `train/osmo/osmo-workflow-ddp.yaml`
  - Use OSMO groups with configurable worker count
  - Use `torchrun` as launcher
  - Same file injection and dataset I/O as base workflow
- [ ] A3. Create `train/osmo/osmo-config-ddp.yaml`
  - Copy of osmo-config.yaml with batch_size scaled for multi-GPU
  - Add num_workers tuned for multi-GPU

### Phase B: Azure Blob Integration <!-- parallelizable: true -->

- [ ] B1. Update `train/osmo/Dockerfile` to install azcopy
- [ ] B2. Create `train/osmo/osmo-workflow-blob.yaml`
  - Workflow variant with Azure credentials block
  - Pre-training azcopy download command
  - No localpath input — data comes from blob
- [ ] B3. Create `train/osmo/download-blob.sh`
  - Shell script for azcopy download with env var configuration
  - Handles container/prefix paths

### Phase C: Train→Eval Workflow Chain <!-- parallelizable: true -->

- [ ] C1. Create `train/osmo/Dockerfile.eval`
  - NGC base with lerobot==0.3.2, pyarrow, av
  - Copy eval modules from deploy/
- [ ] C2. Create `train/osmo/osmo-workflow-train-eval.yaml`
  - Two-task workflow: train then eval
  - Task 2 consumes Task 1's output checkpoint
  - Eval dataset as separate input
- [ ] C3. Create `train/osmo/eval-entrypoint.sh`
  - Entrypoint script for eval container
  - Locates checkpoint, runs offline_eval, copies results

### Phase D: Documentation <!-- parallelizable: false -->

- [ ] D1. Update `train/osmo/README.md`
  - Add DDP workflow section
  - Add Azure Blob workflow section
  - Add Train→Eval workflow section
  - Update configuration table

## Dependencies

- PyTorch DDP (included in NGC image)
- azcopy (installed in Dockerfile)
- lerobot==0.3.2 (eval Dockerfile only)

## Success Criteria

- train.py runs in both single-GPU and DDP modes without error
- All OSMO workflow YAML files parse correctly
- Dockerfiles build without errors
- README documents all workflow variants
