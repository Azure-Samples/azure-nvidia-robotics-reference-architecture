---
title: OSMO Workflows
description: NVIDIA OSMO workflow templates for distributed robotics training
author: Edge AI Team
ms.date: 2025-12-04
ms.topic: reference
---

# OSMO Workflows

NVIDIA OSMO workflow templates for distributed Isaac Lab training on Azure Kubernetes Service.

## 📜 Available Templates

| Template | Purpose | Submission Script |
|----------|---------|-------------------|
| [train.yaml](train.yaml) | Distributed training (base64 inline) | `scripts/submit-osmo-training.sh` |
| [train-dataset.yaml](train-dataset.yaml) | Distributed training (dataset upload) | `scripts/submit-osmo-dataset-training.sh` |
| [lerobot-train.yaml](lerobot-train.yaml) | LeRobot imitation learning fine-tuning | See [LeRobot Workflow](#-lerobot-fine-tuning-workflow) |

## ⚖️ Workflow Comparison

| Aspect | train.yaml | train-dataset.yaml |
|--------|------------|--------------------|
| Payload | Base64-encoded archive | Dataset folder upload |
| Size limit | ~1MB | Unlimited |
| Versioning | None | Automatic |
| Reusability | Per-run | Across runs |
| Setup | None | Bucket configured |

## 🏋️ Training Workflow (`train.yaml`)

Submits Isaac Lab distributed training through OSMO's workflow orchestration engine.

### Features

* Multi-GPU distributed training coordination
* KAI Scheduler / Volcano integration
* Automatic checkpointing and recovery
* OSMO UI monitoring dashboard

### Workflow Parameters

Parameters are passed as key=value pairs through the submission script:

| Parameter | Description |
|-----------|-------------|
| `azure_subscription_id` | Azure subscription ID |
| `azure_resource_group` | Resource group name |
| `azure_workspace_name` | ML workspace name |
| `task` | Isaac Lab task name |
| `num_envs` | Parallel environments |
| `max_iterations` | Training iterations |

### Usage

```bash
# Default configuration from Terraform outputs
./scripts/submit-osmo-training.sh

# Override parameters
./scripts/submit-osmo-training.sh \
  --azure-subscription-id "your-subscription-id" \
  --azure-resource-group "rg-custom"
```

## 💾 Dataset Training Workflow (`train-dataset.yaml`)

Submits Isaac Lab training using OSMO dataset folder injection instead of base64-encoded archives.

### Features

* Dataset versioning and reusability
* No payload size limits
* Training folder mounted at `/data/<dataset_name>/training`
* All features from `train.yaml`

### Dataset Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `dataset_bucket` | `training` | OSMO bucket for training code |
| `dataset_name` | `training-code` | Dataset name in bucket |
| `training_localpath` | (required) | Local path to src/training relative to workflow |

### Usage

```bash
# Default configuration
./scripts/submit-osmo-dataset-training.sh

# Custom dataset bucket
./scripts/submit-osmo-dataset-training.sh \
  --dataset-bucket custom-bucket \
  --dataset-name my-training-code
```

## ⚙️ Environment Variables

| Variable | Description |
|----------|-------------|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_RESOURCE_GROUP` | Resource group name |
| `WORKFLOW_TEMPLATE` | Path to workflow template |
| `OSMO_CONFIG_DIR` | OSMO configuration directory |
| `OSMO_DATASET_BUCKET` | Dataset bucket name (default: training) |
| `OSMO_DATASET_NAME` | Dataset name (default: training-code) |

## 📋 Prerequisites

1. OSMO control plane deployed (`03-deploy-osmo-control-plane.sh`)
2. OSMO backend operator installed (`04-deploy-osmo-backend.sh`)
3. Storage configured for checkpoints
4. OSMO CLI installed and authenticated (see [Accessing OSMO](#-accessing-osmo))

## 🔌 Accessing OSMO

OSMO services are deployed to the `osmo-control-plane` namespace. Access method depends on your network configuration.

### Via VPN (Default Private Cluster)

When connected to VPN, OSMO is accessible via the internal load balancer:

| Service | URL |
|---------|-----|
| UI Dashboard | http://10.0.5.7 |
| API Service | http://10.0.5.7/api |

```bash
osmo login http://10.0.5.7 --method=dev --username=testuser
osmo info
```

> [!NOTE]
> Verify the internal load balancer IP with: `kubectl get svc -n azureml azureml-nginx-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`

### Via Port-Forward (Public Cluster without VPN)

If `should_enable_private_aks_cluster = false` and not using VPN:

| Service | Port-Forward Command | Local URL |
|---------|---------------------|----------|
| UI Dashboard | `kubectl port-forward svc/osmo-ui 3000:80 -n osmo-control-plane` | http://localhost:3000 |
| API Service | `kubectl port-forward svc/osmo-service 9000:80 -n osmo-control-plane` | http://localhost:9000 |
| Router | `kubectl port-forward svc/osmo-router 8080:80 -n osmo-control-plane` | http://localhost:8080 |

```bash
# Start port-forward in background (or separate terminal)
kubectl port-forward svc/osmo-service 9000:80 -n osmo-control-plane &

# Login to OSMO (dev mode for local access)
osmo login http://localhost:9000 --method=dev --username=testuser

# Verify connection
osmo info
osmo backend list
```

> [!NOTE]
> When accessing OSMO through port-forwarding, `osmo workflow exec` and `osmo workflow port-forward` commands are not supported. These require the router service to be accessible via ingress.

## 📺 Monitoring

Access the OSMO UI dashboard:

- **VPN**: Open http://10.0.5.7 in your browser
- **Port-forward**: Run `kubectl port-forward svc/osmo-ui 3000:80 -n osmo-control-plane` then open http://localhost:3000

## 🤖 LeRobot Fine-tuning Workflow

Fine-tune ACT and other imitation learning policies using [LeRobot](https://huggingface.co/docs/lerobot).

### Credential Setup

Before submitting the workflow, configure your credentials:

```bash
# Set WANDB API key for experiment tracking
osmo credential set wandb --type GENERIC --payload wandb_api_key=<YOUR_WANDB_API_KEY>

# Set HuggingFace token for dataset access and model publishing
osmo credential set huggingface --type GENERIC --payload hf_token=<YOUR_HF_TOKEN>
```

### Running the Workflow

**Basic Usage:**

```bash
osmo workflow submit lerobot-train.yaml \
  --set dataset_repo_id=alizaidi/so101-multi-pick-merged \
  --set job_name=act_so101_pick_test \
  --set policy_repo_id=alizaidi/act_so101_multi_pick
```

**Full Example with All Options:**

```bash
osmo workflow submit lerobot-train.yaml \
  --set dataset_repo_id=alizaidi/so101-multi-pick-merged \
  --set policy_type=act \
  --set output_dir=/workspace/outputs/train/act_so101_pick_test \
  --set job_name=act_so101_pick_test \
  --set policy_repo_id=alizaidi/act_so101_multi_pick \
  --set wandb_enable=true \
  --set wandb_project=lerobot-so101 \
  --set training_steps=100000 \
  --set batch_size=64
```

### LeRobot Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image` | `pytorch/pytorch:2.4.1-cuda12.4-cudnn9-runtime` | Base Docker image |
| `dataset_repo_id` | (required) | HuggingFace Hub dataset ID |
| `policy_type` | `act` | Policy architecture: `act`, `diffusion`, `vqbet`, `tdmpc` |
| `output_dir` | `/workspace/outputs/train` | Output directory for checkpoints |
| `job_name` | `lerobot-act-training` | Training job identifier |
| `policy_repo_id` | (optional) | HuggingFace Hub repo for model upload |
| `wandb_enable` | `true` | Enable WANDB experiment tracking |
| `wandb_project` | `lerobot-training` | WANDB project name |
| `training_steps` | (auto) | Total training steps |
| `batch_size` | (auto) | Training batch size |
| `eval_freq` | (auto) | Evaluation frequency (steps) |
| `save_freq` | (auto) | Checkpoint save frequency (steps) |
| `lerobot_version` | (latest) | Specific LeRobot version to install |

### Monitoring LeRobot Training

Once the workflow is running:

1. **WANDB Dashboard**: View real-time training metrics at [wandb.ai](https://wandb.ai)
2. **OSMO Logs**: `osmo workflow logs <workflow-id>`
3. **OSMO Status**: `osmo workflow status <workflow-id>`

If `policy_repo_id` is set, the trained model will be automatically pushed to HuggingFace Hub upon completion.
