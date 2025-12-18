# 🤖 Azure NVIDIA Robotics Reference Architecture

Production-ready framework for orchestrating robotics and AI workloads on [Azure](https://azure.microsoft.com/) using [NVIDIA Isaac Lab](https://developer.nvidia.com/isaac/lab), [Isaac Sim](https://developer.nvidia.com/isaac/sim), and [OSMO](https://developer.nvidia.com/osmo).

## 🚀 Features

| Capability | Description |
|------------|-------------|
| Infrastructure as Code | [Terraform modules](deploy/001-iac/) for reproducible Azure deployments |
| Dual Orchestration | Submit jobs via [AzureML](workflows/azureml/) or [OSMO](workflows/osmo/) |
| Workload Identity | Key-less auth via Azure AD ([setup guide](deploy/002-setup/README.md#scenario-2-workload-identity)) |
| Private Networking | Services on private VNet with optional [VPN gateway](deploy/001-iac/vpn/) |
| MLflow Integration | Experiment tracking with Azure ML ([details](docs/mlflow-integration.md)) |
| GPU Scheduling | [KAI Scheduler](deploy/002-setup/values/kai-scheduler.yaml) for efficient utilization |
| Auto-scaling | Pay-per-use GPU compute on AKS Spot nodes |

## 🏗️ Architecture

The infrastructure deploys an AKS cluster with GPU node pools running the NVIDIA GPU Operator and KAI Scheduler. Training workloads can be submitted via OSMO workflows (control plane and backend operator) and AzureML jobs (ML extension). Both platforms share common infrastructure: Azure Storage for checkpoints and data, Key Vault for secrets, and Azure Container Registry for container images. OSMO additionally uses PostgreSQL for workflow state and Redis for caching.

**Azure Infrastructure** (deployed by [Terraform](deploy/001-iac/)):

| Component | Purpose |
|-----------|--------|
| Virtual Network | Private networking with NAT Gateway and DNS Resolver |
| Private Endpoints | Secure access to Azure services (7 endpoints, 11+ DNS zones) |
| AKS Cluster | Kubernetes with GPU Spot node pools and Workload Identity |
| Key Vault | Secrets management with RBAC authorization |
| Azure ML Workspace | Experiment tracking, model registry |
| Storage Account | Training data, checkpoints, and workflow artifacts |
| Container Registry | Training and OSMO container images |
| Azure Monitor | Log Analytics, Prometheus metrics, Managed Grafana |
| PostgreSQL | OSMO workflow state persistence |
| Redis | OSMO job queue and caching |
| VPN Gateway ⚙️ | Point-to-Site and Site-to-Site connectivity |

**Kubernetes Components** (deployed by [setup scripts](deploy/002-setup/)):

| Component | Purpose |
|-----------|--------|
| NVIDIA GPU Operator | GPU drivers, device plugin, DCGM metrics exporter |
| KAI Scheduler | GPU-aware scheduling with bin-packing |
| AzureML Extension | ML training and inference job submission |
| OSMO Control Plane | Workflow API, router, and web interface |
| OSMO Backend Operator | Workflow execution on cluster |

⚙️ = Optional component

> [!NOTE]
> Running both AzureML and OSMO on the same cluster? Create **separate GPU node pools** for each platform. AzureML uses [Volcano](https://volcano.sh/) while OSMO uses [KAI Scheduler](https://github.com/NVIDIA/KAI-Scheduler)—these schedulers don't share resource visibility. Without dedicated pools, jobs from one platform may fail when the other is using GPU resources. Configure node selectors and taints to isolate workloads.

## 🌍 Real World Examples

OSMO orchestration on Azure enables production-scale robotics training across industries:

| Use Case | Training Scenario |
|----------|-------------------|
| Warehouse AMRs | Navigation policies with 1000+ parallel environments, checkpointing to Azure Storage |
| Manufacturing Arms | Manipulation strategies with physics-accurate simulation on pay-per-use GPU |
| Legged Robots | Locomotion optimization with MLflow tracking for sim-to-real transfer |
| Collaborative Robots | Safe interaction policies with Azure Monitor logging for compliance |

## 📋 Prerequisites

### Required Tools

| Tool | Version | Installation |
|------|---------|--------------|
| [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | 2.50+ | `brew install azure-cli` |
| [Terraform](https://www.terraform.io/downloads) | 1.9.8+ | `brew install terraform` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.28+ | `brew install kubectl` |
| [Helm](https://helm.sh/docs/intro/install/) | 3.x | `brew install helm` |
| [jq](https://stedolan.github.io/jq/) | latest | `brew install jq` |
| [OSMO CLI](https://developer.nvidia.com/osmo) | latest | See NVIDIA docs |

### Azure Requirements

- Azure subscription with **Contributor** + **Role Based Access Control Administrator**
  - Scope: Subscription (if creating new resource group) or Resource Group (if using existing)
  - Terraform creates role assignments for managed identities
  - Alternative: **Owner** (grants more permissions than required)
- GPU VM quota for your target region (e.g., `Standard_NV36ads_A10_v5`)

## 🏃 Quick Start

### 1. Deploy Infrastructure

```bash
cd deploy/001-iac
source ../000-prerequisites/az-sub-init.sh
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply -var-file=terraform.tfvars
```

For VPN, automation, and additional configuration, see [deploy/001-iac/README.md](deploy/001-iac/README.md).

### 2. Configure Cluster

```bash
cd ../002-setup

# Get cluster credentials (resource group and cluster name from terraform output)
az aks get-credentials --resource-group <rg> --name <aks>

# Deploy GPU infrastructure
./01-deploy-robotics-charts.sh

# Deploy AzureML extension
./02-deploy-azureml-extension.sh

# Deploy OSMO
./03-deploy-osmo-control-plane.sh
./04-deploy-osmo-backend.sh
```

### 3. Submit Workloads

**OSMO Training** – Submits to NVIDIA OSMO orchestrator:

```bash
# Quick training run (100 iterations for testing)
./scripts/submit-osmo-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0 --max-iterations 100

# Full training with custom environments
./scripts/submit-osmo-training.sh --task Isaac-Velocity-Rough-Anymal-D-v0 --num-envs 4096

# Resume from checkpoint
./scripts/submit-osmo-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0 \
  --checkpoint-uri "runs:/<run-id>/checkpoints" --checkpoint-mode resume
```

**AzureML Training** – Submits to Azure Machine Learning:

```bash
# Quick training run
./scripts/submit-azureml-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0 --max-iterations 100

# Full training with log streaming
./scripts/submit-azureml-training.sh --task Isaac-Velocity-Rough-Anymal-D-v0 --num-envs 4096 --stream

# Resume training from registered model
./scripts/submit-azureml-training.sh --task Isaac-Velocity-Rough-Anymal-C-v0 \
  --checkpoint-uri "azureml://models/isaac-velocity-rough-anymal-c-v0/versions/1" \
  --checkpoint-mode resume
```

**AzureML Validation** – Validates a trained model:

```bash
# Validate latest model version (model name derived from task)
./scripts/submit-azureml-validation.sh --task Isaac-Velocity-Rough-Anymal-C-v0

# Validate specific model version with custom episodes
./scripts/submit-azureml-validation.sh --model-name isaac-velocity-rough-anymal-c-v0 \
  --model-version 2 --eval-episodes 200

# Validate with streaming logs
./scripts/submit-azureml-validation.sh --model-name my-policy --stream
```

> **Tip**: Run any script with `--help` for all available options.

## 🔐 Deployment Scenarios

| Scenario | Storage Auth | Registry | Use Case |
|----------|--------------|----------|----------|
| Access Keys | Keys | nvcr.io | Development |
| Workload Identity | Federated | nvcr.io | Production |
| Workload Identity + ACR | Federated | Private ACR | Air-gapped |

See [002-setup/README.md](deploy/002-setup/README.md) for detailed instructions.

## 📁 Repository Structure

```text
.
├── deploy/
│   ├── 000-prerequisites/              # Azure CLI and provider setup
│   ├── 001-iac/                        # Terraform infrastructure
│   └── 002-setup/                      # Cluster configuration scripts
├── scripts/
│   ├── submit-azureml-*.sh             # AzureML job submission
│   └── submit-osmo-*.sh                # OSMO workflow submission
├── workflows/
│   ├── azureml/                        # AzureML job templates
│   └── osmo/                           # OSMO workflow templates
├── src/training/                       # Training code
└── docs/                               # Additional documentation
```

## 📖 Documentation

| Guide | Description |
|-------|-------------|
| [Deploy Overview](deploy/README.md) | Deployment order and quick path |
| [Infrastructure](deploy/001-iac/README.md) | Terraform configuration and modules |
| [Cluster Setup](deploy/002-setup/README.md) | Scripts and deployment scenarios |
| [Scripts](scripts/README.md) | Training and validation submission |
| [Workflows](workflows/README.md) | Job and workflow templates |
| [MLflow Integration](docs/mlflow-integration.md) | Experiment tracking setup |

## 💰 Cost Estimation

Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) to estimate costs. Add these services based on the architecture:

| Service | Configuration | Notes |
|---------|---------------|-------|
| Azure Kubernetes Service (AKS) | System pool: Standard_D4s_v3 (3 nodes) | Always-on control plane |
| Virtual Machines (Spot) | Standard_NV36ads_A10_v5 or NC-series | GPU nodes scale to zero when idle |
| Azure Database for PostgreSQL | Flexible Server, Burstable B1ms | OSMO workflow state |
| Azure Cache for Redis | Basic C0 or Standard C1 | OSMO job queue |
| Azure Machine Learning | Basic workspace | No additional compute costs (uses AKS) |
| Storage Account | Standard LRS, ~100GB | Checkpoints and datasets |
| Container Registry | Basic or Standard | Image storage |
| Log Analytics | ~5GB/day ingestion | Monitoring data |
| Azure Managed Grafana | Essential tier | Dashboards (optional) |
| VPN Gateway | VpnGw1 | Point-to-site access (optional) |

GPU Spot VMs provide significant savings (60-90%) compared to on-demand pricing. Actual costs depend on training frequency, job duration, and data volumes.

## 🪪 License

MIT License. See [LICENSE.md](LICENSE.md).

## 🙏 Acknowledgments

- [microsoft/edge-ai](https://github.com/microsoft/edge-ai) – Infrastructure components
- [NVIDIA Isaac Lab](https://github.com/isaac-sim/IsaacLab) – RL framework
- [NVIDIA OSMO](https://github.com/NVIDIA/OSMO) – Workflow orchestration
