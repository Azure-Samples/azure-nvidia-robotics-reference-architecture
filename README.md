# 🤖 Azure Robotics Reference Architecture with NVIDIA OSMO

This reference architecture provides a production-ready framework for orchestrating robotics and AI workloads on Azure using NVIDIA technologies such as Isaac Lab, Isaac Sim, and Osmo. It demonstrates end-to-end reinforcement learning workflows, scalable training pipelines, and deployment processes with Azure-native authentication, storage, and ML services.

## 🗼 Architecture Overview

This reference architecture integrates:
- **NVIDIA Osmo** - Workflow orchestration and job scheduling
- **Azure Machine Learning** - Experiment tracking and model management
- **Azure Container Instances/AKS** - Scalable compute for Isaac Lab training
- **Azure Storage** - Persistent data and checkpoint storage
- **Azure Key Vault** - Secure credential management
- **Azure Monitor** - Comprehensive logging and metrics

**INSERT ARCHITECTURE DIAGRAM HERE**

## Repository Structure

```text
.
├── deploy/
│   ├── 000-prerequisites/              # Prerequisites validation and setup
│   ├── 001-iac/                        # Infrastructure as Code deployment
│   ├── 002-setup/                      # Post-infrastructure setup
│   ├── 003-data/                       # Data preparation and upload
│   └── 004-workflow/                   # Training workflow execution
│       ├── job-templates/              # Job configuration templates
│       └── osmo/                       # OSMO inline workflow submission (see osmo/README.md)
├── src/
│   ├── terraform/                      # Infrastructure as Code
│   │   └── modules/                    # Reusable Terraform modules
│   └── training/                       # Training code and tasks
│       ├── common/                     # Shared utilities
│       ├── scripts/                    # Framework-specific training scripts configured for Azure services
│       │   ├── rsl_rl/                 # RSL_RL training scripts
│       │   ├── skrl/                   # SKRL training scripts
│       └── tasks/                      # Placeholder for Isaac Lab training tasks
```

## 🚀 Key Features

- **Infrastructure as Code** - Terraform modules referencing [microsoft/edge-ai](https://github.com/microsoft/edge-ai) components for reproducible deployments
- **Containerized Workflows** - Docker-based Isaac Lab training with NVIDIA GPU support
- **CI/CD Integration** - Automated deployment pipelines with GitHub Actions
- **MLflow Integration** - Automatic experiment tracking and model versioning
    - Automatic metric logging from SKRL agents to Azure ML
    - Comprehensive tracking of episode statistics, losses, optimization metrics, and timing data
    - Configurable logging intervals and metric filtering
    - See [MLflow Integration Guide](docs/mlflow-integration.md) for details
- **Scalable Compute** - Auto-scaling GPU nodes based on workload demands
- **Cost Optimization** - Pay-per-use compute with automatic scaling
- **Enterprise Security** - Azure AD integration and compliance certifications
- **Global Deployment** - Multi-region support for worldwide teams
- **Vendor Agnostic** - Open-source solution avoiding vendor lock-in
- **ROI Tracking** - Comprehensive metrics and cost analysis dashboards

## 🧑🏽‍💻 Local Development Setup

### Required Tools

- [pyenv](https://github.com/pyenv/pyenv)
- Python 3.11 (required by Isaac Sim 5.X)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (v2.50+)
- [Terraform](https://www.terraform.io/downloads) (v1.5+)
- [NVIDIA Osmo CLI](https://developer.nvidia.com/osmo) (latest)
- [Docker](https://docs.docker.com/get-docker/) with NVIDIA Container Toolkit

### Azure Requirements
- Azure subscription with contributor access
- Sufficient quota for GPU VMs (Standard_NC6s_v3 or higher)
- Azure Machine Learning workspace (or permissions to create one)

### NVIDIA Requirements
- NVIDIA Developer account with Osmo access
- NGC API key for container registry access

### Quick Start

```bash
./setup-dev.sh
```

The setup script installs Python 3.11 via pyenv, creates a virtual environment at `.venv/`, and installs training dependencies.

### VS Code Configuration

The workspace is configured with `python.analysis.extraPaths` pointing to `src/`, enabling imports like:

```python
from training.utils import AzureMLContext, bootstrap_azure_ml
```

Select the `.venv/bin/python` interpreter in VS Code for IntelliSense support

## 🪪 License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for details.

## 🤝 Support

For issues and questions:

* Review [microsoft/edge-ai](https://github.com/microsoft/edge-ai) documentation

## 🙏 Acknowledgments

This reference architecture builds upon:

* [microsoft/edge-ai](https://github.com/microsoft/edge-ai) - Edge AI infrastructure components
* [NVIDIA Isaac Lab](https://github.com/isaac-sim/IsaacLab) - RL task framework
* [NVIDIA Isaac Sim](https://developer.nvidia.com/isaac-sim) - Physics simulation
* [NVIDIA OSMO](https://developer.nvidia.com/osmo) - Workflow orchestration
