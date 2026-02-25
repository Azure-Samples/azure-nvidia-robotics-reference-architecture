<!-- markdownlint-disable-file -->

# OSMO Enhancements Research

## Scope

Three enhancements to the OSMO training pipeline for UR10e ACT:

1. **Multi-GPU DDP Training** — PyTorch DistributedDataParallel support with OSMO groups
2. **Azure Blob Integration** — Direct blob storage dataset access via OSMO credentials
3. **Train→Eval Workflow Chain** — Two-task OSMO workflow connecting training to offline evaluation

## 1. Multi-GPU DDP Training

### Current State

- `train.py` (750 lines) is single-GPU only
- No `torch.distributed` imports or initialization
- Single `DataLoader` with `shuffle=True` (incompatible with DDP — must use `DistributedSampler`)
- Model created with `model.to(device)` — needs DDP wrapper
- Checkpoint saving uses raw `model.state_dict()` — with DDP, must unwrap via `model.module`
- OSMO workflow has single task `train-act` with 1 GPU resource

### Required Changes — train.py

1. Add distributed initialization: `torch.distributed.init_process_group(backend="nccl")`
2. Set `local_rank` from environment variable `LOCAL_RANK` (PyTorch convention)
3. Replace `shuffle=True` with `DistributedSampler`
4. Wrap model with `DistributedDataParallel`
5. Gate checkpoint saving on `rank == 0` only
6. Gate logging on `rank == 0` only
7. Add `sampler.set_epoch(epoch)` for proper shuffling across epochs
8. Detect DDP vs single-GPU automatically via env vars

### OSMO Groups

OSMO supports multi-worker tasks via the `groups` specification. A group defines replicated workers that share the same resource and command. Each worker gets environment variables for rank/world_size coordination.

OSMO group format:
```yaml
tasks:
- name: train-act-ddp
  image: ur10e-act-train:latest
  resource: gpu-node
  groups:
  - name: workers
    count: 4
  command: ["torchrun"]
  args:
  - "--nproc_per_node=1"
  - "--nnodes={{groups.workers.count}}"
  - "--node_rank={{groups.workers.rank}}"
  - "--master_addr={{groups.workers.0.host}}"
  - "--master_port=29500"
  - "train.py"
  - "--config"
  - "/workspace/config.yaml"
```

**Selected approach**: Use `torchrun` launcher with OSMO groups for multi-node DDP. Each OSMO group worker runs one GPU. `torchrun` handles `LOCAL_RANK`, `RANK`, `WORLD_SIZE` environment variables automatically.

### Alternative considered

- Horovod: Heavier dependency, not standard PyTorch. Rejected.
- torch.multiprocessing.spawn: Doesn't integrate with OSMO groups. Rejected.

## 2. Azure Blob Integration

### Current State

- Workflow uses `localpath` upload for rosbag data: `../rosbag-to-lerobot/local_bags`
- Azure Blob account: `stosmorbt3dev001.blob.core.windows.net`, container `datasets`, prefix `houston_recordings/`
- Dockerfile has no Azure SDK packages

### OSMO Credentials

OSMO workflows support a `credentials` block for injecting secrets as environment variables:

```yaml
credentials:
  AZURE_STORAGE_ACCOUNT_NAME:
    secret: azure-storage-account
  AZURE_STORAGE_ACCOUNT_KEY:
    secret: azure-storage-key
```

Secrets must be pre-created in the OSMO secret store via:
```bash
osmo secret create azure-storage-account --value "stosmorbt3dev001"
osmo secret create azure-storage-key --value "<key>"
```

### Selected Approach

1. Add a pre-training data download step in the workflow command that uses `azcopy` or `az storage blob download-batch`
2. Install `azcopy` in the Dockerfile (lightweight, no Python dependency)
3. Add OSMO credentials block for Azure storage secrets
4. Fall back to localpath if credentials not configured (backward compatible)

### Alternative considered

- azure-storage-blob Python SDK: More deps, slower for bulk download vs azcopy. Rejected for download step.
- OSMO native blob dataset driver: Not available in current OSMO release. Not viable.

## 3. Train→Eval Workflow Chain

### Current State

- `offline_eval.py` loads a pretrained checkpoint and runs inference on a LeRobot v3 dataset
- Uses `PolicyRunner` which internally uses `lerobot.policies.act.modeling_act.ACTPolicy`
- Requires: lerobot==0.3.2, pyarrow, av
- Outputs parquet files with per-joint MAE and latency metrics
- Evaluation needs both trained checkpoint and evaluation dataset

### Selected Approach

Create a two-task OSMO workflow:
1. **Task 1 (train)**: Existing training task — produces checkpoint dataset
2. **Task 2 (eval)**: New evaluation task — consumes checkpoint + eval dataset, produces metrics

OSMO tasks within a workflow execute sequentially by default. Task 2 references Task 1's output dataset as input.

Eval task needs a separate Dockerfile with lerobot dependency.

### Eval Dockerfile Requirements

- Same NGC base image for CUDA compatibility
- lerobot==0.3.2, pyarrow>=14, av
- Copy offline_eval.py and supporting modules (config.py, policy_runner.py)

## Success Criteria

- [ ] `train.py` supports both single-GPU and multi-GPU DDP modes transparently
- [ ] New `osmo-workflow-ddp.yaml` uses OSMO groups with torchrun
- [ ] Azure Blob credentials integrated in workflow with azcopy download
- [ ] Two-task train→eval workflow with sequential execution
- [ ] Eval Dockerfile builds with lerobot dependency
- [ ] README updated with all new workflow variants

## References

- PyTorch DDP: https://pytorch.org/docs/stable/notes/ddp.html
- torchrun: https://pytorch.org/docs/stable/elastic/run.html
- NVIDIA OSMO groups: nvidia.github.io/OSMO workflow spec
- Azure azcopy: https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-v10
