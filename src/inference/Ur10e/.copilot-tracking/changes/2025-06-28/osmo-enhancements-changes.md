<!-- markdownlint-disable-file -->

# Changes Log: OSMO Training Enhancements

## Related Plan

`.copilot-tracking/plans/2025-06-28/osmo-enhancements-plan.instructions.md`

## Implementation Date

2025-06-28

## Summary

Added three OSMO training enhancements:

1. Multi-GPU DDP training with automatic detection and OSMO groups
2. Azure Blob Storage integration with azcopy download and OSMO credentials
3. Train→Eval workflow chain with sequential task execution

## Changes by Category

### Modified

- [train/train.py](train/train.py) — Added DDP support (torch.distributed init, DistributedSampler, DDP model wrapping, rank-gated logging/checkpointing, cleanup)
- [train/osmo/Dockerfile](train/osmo/Dockerfile) — Added azcopy installation for Azure Blob download
- [train/osmo/README.md](train/osmo/README.md) — Added DDP, Azure Blob, and Train→Eval documentation sections

### Added

- [train/osmo/osmo-workflow-ddp.yaml](train/osmo/osmo-workflow-ddp.yaml) — OSMO DDP workflow with groups and torchrun
- [train/osmo/osmo-config-ddp.yaml](train/osmo/osmo-config-ddp.yaml) — DDP training config with scaled workers
- [train/osmo/osmo-workflow-blob.yaml](train/osmo/osmo-workflow-blob.yaml) — Azure Blob data source workflow with credentials
- [train/osmo/download-blob.sh](train/osmo/download-blob.sh) — azcopy download script for Azure Blob
- [train/osmo/osmo-workflow-train-eval.yaml](train/osmo/osmo-workflow-train-eval.yaml) — Two-task train→eval workflow
- [train/osmo/Dockerfile.eval](train/osmo/Dockerfile.eval) — Evaluation container with lerobot dependency
- [train/osmo/eval-entrypoint.sh](train/osmo/eval-entrypoint.sh) — Eval container entrypoint script

### Removed

None.
