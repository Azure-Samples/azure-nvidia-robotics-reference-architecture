# 🤖 Azure NVIDIA Robotics Reference Architecture

Production-ready framework for orchestrating robotics and AI workloads on [Azure](https://azure.microsoft.com/) using [NVIDIA Isaac Lab](https://developer.nvidia.com/isaac/lab), [Isaac Sim](https://developer.nvidia.com/isaac/sim), and [OSMO](https://developer.nvidia.com/osmo).

## 🚀 Features

- **Infrastructure as Code** – [Terraform modules](deploy/001-iac/) for reproducible deployments
- **Dual Orchestration** – [AzureML jobs](workflows/azureml/) and [NVIDIA OSMO workflows](workflows/osmo/) both available
- **Workload Identity** – Key-less authentication via Azure AD federation ([setup](deploy/002-setup/README.md#scenario-2-workload-identity--ngc-production))
- **Private Networking** – Azure services secured on a private VNet with [private endpoints](deploy/001-iac/variables.tf) and private links; optional [VPN gateway](deploy/001-iac/vpn/) for secure remote access; public access configurable when needed
- **MLflow Integration** – Experiment tracking with Azure ML ([details](docs/mlflow-integration.md))
- **GPU Scheduling** – [KAI Scheduler](deploy/002-setup/values/kai-scheduler.yaml) for efficient GPU utilization
- **Auto-scaling** – Pay-per-use GPU compute on AKS Spot nodes

## 🏗️ Architecture

The infrastructure deploys an AKS cluster with GPU node pools running the NVIDIA GPU Operator and KAI Scheduler. Training workloads can be submitted via OSMO workflows (control plane and backend operator) and AzureML jobs (ML extension). Both platforms share common infrastructure: Azure Storage for checkpoints and data, Key Vault for secrets, and Azure Container Registry for container images. OSMO additionally uses PostgreSQL for workflow state and Redis for caching.

**Core Components**:

- **AKS Cluster** – Hosts GPU workloads with Spot node pools for cost optimization
- **NVIDIA GPU Operator** – Manages GPU drivers and device plugins
- **KAI Scheduler** – GPU-aware scheduling for training jobs
- **AzureML Extension** – Enables Azure ML job submission to Kubernetes
- **OSMO Control Plane** – Workflow orchestration (service, router, web-ui)
- **OSMO Backend Operator** – Executes workflows on the cluster

## 🌍 Real World Examples

OSMO orchestration on Azure enables production-scale robotics training across industries:

- **Warehouse AMRs** – Train navigation policies with 1000+ parallel environments on auto-scaling GPU nodes, checkpoint to Azure Storage, track experiments in Azure ML
- **Manufacturing Arms** – Develop manipulation strategies with physics-accurate simulation, leveraging pay-per-use GPU compute and global Azure regions
- **Legged Robots** – Optimize locomotion policies with MLflow experiment tracking for sim-to-real transfer
- **Collaborative Robots** – Create safe interaction policies with Azure Monitor logging for compliance auditing

## 📋 Prerequisites

### Required Tools

| Tool | Version | Installation |
|------|---------|--------------|
| [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | 2.50+ | `brew install azure-cli` |
| [Terraform](https://www.terraform.io/downloads) | 1.5+ | `brew install terraform` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.28+ | `brew install kubectl` |
| [Helm](https://helm.sh/docs/intro/install/) | 3.x | `brew install helm` |
| [jq](https://stedolan.github.io/jq/) | latest | `brew install jq` |
| [OSMO CLI](https://developer.nvidia.com/osmo) | latest | See NVIDIA docs |

### Azure Requirements

- Azure subscription with **Contributor** access
- GPU VM quota for your target region (e.g., `Standard_NV36ads_A10_v5`)
- Permissions to create: Resource Groups, AKS, Storage, Key Vault, AzureML Workspace

### NVIDIA Requirements

- [NVIDIA Developer](https://developer.nvidia.com/) account with OSMO access
- [NGC API Key](https://ngc.nvidia.com/setup/api-key) for container registry access

## 🏃 Quick Start

### 1. Deploy Infrastructure

```bash
# Login to Azure CLI (required for Terraform and cluster configuration)
source deploy/000-prerequisites/az-sub-init.sh # --tenant <tenant-id>  (Optionally) Specify tenant

cd deploy/001-iac
cp terraform.tfvars.example terraform.tfvars  # Edit with your values
terraform init && terraform apply

# Optional: Deploy VPN for secure access to private resources
cd vpn
terraform init && terraform apply
# Download VPN client config from Azure Portal > Virtual Network Gateway > Point-to-site configuration
```

### 2. Configure Cluster

```bash
cd ../002-setup

# Get cluster credentials (resource group and cluster name from terraform output)
az aks get-credentials --resource-group <rg> --name <aks>

# Deploy GPU infrastructure
./01-deploy-robotics-charts.sh

# Deploy AzureML extension
./02-deploy-azureml-extension.sh

# Deploy OSMO (requires NGC token)
export NGC_API_KEY="your-token"
./03-deploy-osmo-control-plane.sh --ngc-token "$NGC_API_KEY"
./04-deploy-osmo-backend.sh --ngc-token "$NGC_API_KEY"
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

> **Tip**: Run `./scripts/submit-*-training.sh --help` for all available options.

## 🔐 Deployment Scenarios

| Scenario | Storage Auth | Registry | Use Case |
|----------|--------------|----------|----------|
| Access Keys + NGC | Keys | nvcr.io | Development |
| Workload Identity + NGC | Federated | nvcr.io | Production |
| Workload Identity + ACR | Federated | Private ACR | Air-gapped |

See [002-setup/README.md](deploy/002-setup/README.md) for detailed instructions.

## 📁 Repository Structure

```text
.
├── deploy/
│   ├── 000-prerequisites/    # Validation scripts
│   ├── 001-iac/              # Terraform infrastructure
│   └── 002-setup/            # Cluster configuration scripts
├── scripts/
│   ├── submit-azureml-*.sh   # AzureML job submission
│   └── submit-osmo-*.sh      # OSMO workflow submission
├── workflows/
│   ├── azureml/              # AzureML job templates
│   └── osmo/                 # OSMO workflow templates
├── src/training/             # Training code
└── docs/                     # Additional documentation
```

## 📖 Documentation

- [002-setup README](deploy/002-setup/README.md) – Cluster setup and deployment scenarios
- [Workflows README](workflows/README.md) – Job and workflow templates
- [MLflow Integration](docs/mlflow-integration.md) – Experiment tracking setup

## 🪪 License

MIT License. See [LICENSE.md](LICENSE.md).

## 🙏 Acknowledgments

- [microsoft/edge-ai](https://github.com/microsoft/edge-ai) – Infrastructure components
- [NVIDIA Isaac Lab](https://github.com/isaac-sim/IsaacLab) – RL framework
- [NVIDIA OSMO](https://github.com/NVIDIA/OSMO) – Workflow orchestration
