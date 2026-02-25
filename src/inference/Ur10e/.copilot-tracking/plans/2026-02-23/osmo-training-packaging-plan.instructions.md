<!-- markdownlint-disable-file -->

# Implementation Plan: OSMO Training Packaging

**Date:** 2026-02-23
**Research:** `.copilot-tracking/research/2026-02-23/osmo-training-packaging-research.md`

## Overview

Package the rosbag ACT training pipeline for submission to an NVIDIA OSMO instance at 192.168.1.100.

### User Requirements

- Run existing `train/` ACT training on OSMO instance 192.168.1.100
- Training reads rosbag data, trains ACT model, outputs checkpoints

### Derived Objectives

- Create container image with all training dependencies
- Create OSMO workflow YAML for job submission
- Create container-appropriate training configuration
- Provide clear instructions for build, push, and submit

## Implementation Checklist

### Phase 1: Container Image <!-- parallelizable: false -->

- [ ] Create `train/osmo/Dockerfile` — NVIDIA PyTorch base, install training deps, copy source

### Phase 2: OSMO Configuration <!-- parallelizable: true -->

- [ ] Create `train/osmo/osmo-config.yaml` — Training config with container paths
- [ ] Create `train/osmo/osmo-workflow.yaml` — OSMO workflow definition

### Phase 3: Documentation <!-- parallelizable: true -->

- [ ] Create `train/osmo/README.md` — Build, push, submit instructions

## Dependencies

- Existing training scripts: `train/train.py`, `train/act_model.py`
- Existing training config: `train/config.yaml`
- NVIDIA NGC PyTorch container images
- Access to OSMO instance at 192.168.1.100

## Success Criteria

- Dockerfile builds successfully with all training dependencies
- OSMO workflow YAML follows OSMO specification
- Container paths in config align with OSMO file injection
- README provides complete workflow from build to job monitoring
