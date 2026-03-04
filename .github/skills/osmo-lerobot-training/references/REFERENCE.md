# OSMO LeRobot Training Reference

Detailed CLI commands, Python SDK patterns, and troubleshooting for LeRobot training on OSMO.

## OSMO CLI Reference

### Workflow Submission

```bash
# Submit with the helper script (packages payload automatically)
scripts/submit-osmo-lerobot-training.sh \
  -d user/dataset \
  -p act \
  --training-steps 50000 \
  -r my-model-name

# Direct OSMO submission (already-built payload)
osmo workflow submit workflows/osmo/lerobot-train.yaml \
  --set-string "dataset_repo_id=user/dataset" \
  "policy_type=act" \
  "training_steps=50000"
```

### Workflow Monitoring

```bash
# Query workflow status (returns task table with statuses)
osmo workflow query <workflow-id>

# Stream live logs
osmo workflow logs <workflow-id>

# Stream logs for a specific task
osmo workflow logs <workflow-id> --task lerobot-train

# Show last N lines of logs
osmo workflow logs <workflow-id> -n 100

# Show only error output
osmo workflow logs <workflow-id> --error

# List recent workflows with filtering
osmo workflow list --status running
osmo workflow list --status completed --json
osmo workflow list --name lerobot-training

# Cancel a running workflow
osmo workflow cancel <workflow-id>
osmo workflow cancel <workflow-id> --force --message "reason"

# Interactive shell into running container
osmo workflow exec <workflow-id> --task lerobot-train
```

### Workflow Status Values

| Status | Meaning |
|--------|---------|
| `pending` | Queued, awaiting resources |
| `running` | Actively executing |
| `completed` | Finished successfully |
| `failed` | Exited with error |
| `cancelled` | Manually cancelled |

## Azure ML Metric Retrieval

### Python SDK Pattern

```python
from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient
import mlflow

# Connect to workspace
credential = DefaultAzureCredential()
ml_client = MLClient(credential, subscription_id, resource_group, workspace_name)
workspace = ml_client.workspaces.get(workspace_name)

# Configure MLflow tracking
mlflow.set_tracking_uri(workspace.mlflow_tracking_uri)

# Search for training runs
runs = mlflow.search_runs(
    experiment_names=["lerobot-training"],
    order_by=["start_time DESC"],
    max_results=10,
)

# Get metric history for a specific run
client = mlflow.MlflowClient()
history = client.get_metric_history(run_id, "train/loss")
```

### Key Metrics Logged

| Metric | Description |
|--------|-------------|
| `train/loss` | Training loss per step |
| `grad_norm` | Gradient norm |
| `learning_rate` | Current learning rate |
| `val/loss` | Validation loss (when val split enabled) |
| `gpu_percent` | GPU utilization (when system metrics enabled) |
| `gpu_memory_percent` | GPU memory usage |
| `cpu_percent` | CPU utilization |
| `ram_percent` | RAM usage |

### CLI Quick Check

```bash
# List experiments
az ml job list \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --workspace-name "$AZUREML_WORKSPACE_NAME" \
  --query "[?display_name=='lerobot-act-training']" \
  -o table
```

## Training Progress Interpretation

### Loss Curve Analysis

- ACT policy: Expect rapid initial descent in `train/loss` over first 5-10k steps, then gradual convergence. Typical final loss: 0.01-0.1 depending on dataset complexity.
- Diffusion policy: Slower convergence, loss may plateau and resume descent. Typical training requires 50-100k steps minimum.

### Checkpoint Strategy

Checkpoints saved at `--save-freq` intervals to `output_dir`. When `--register-checkpoint` is set, the final checkpoint uploads to the Azure ML model registry.

## Common Issues

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `CUDA_ERROR_NO_DEVICE` | MIG strategy misconfigured | Verify `mig.strategy: single` for vGPU nodes |
| MLflow connection timeout | Token refresh failure | Check `MLFLOW_TRACKING_TOKEN_REFRESH_RETRIES` |
| Dataset download failure | Blob auth issue | Verify managed identity has Storage Blob Reader role |
| OOM during training | Batch size too large | Reduce `--batch-size` |

## Troubleshooting

### OSMO Workflow Debugging

```bash
# Check error logs
osmo workflow logs <workflow-id> --error

# Interactive shell for inspection
osmo workflow exec <workflow-id> --task lerobot-train

# Validate workflow YAML before submission
osmo workflow validate workflows/osmo/lerobot-train.yaml
```

### Azure ML Connectivity

```bash
# Verify workspace access
az ml workspace show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZUREML_WORKSPACE_NAME"

# Check tracking URI
python3 -c "
from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient
c = MLClient(DefaultAzureCredential(), '$AZURE_SUBSCRIPTION_ID', '$AZURE_RESOURCE_GROUP', '$AZUREML_WORKSPACE_NAME')
print(c.workspaces.get('$AZUREML_WORKSPACE_NAME').mlflow_tracking_uri)
"
```
