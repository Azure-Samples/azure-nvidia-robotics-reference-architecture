# Azure Robotics Reference Architecture with NVIDIA OSMO

This reference architecture demonstrates end-to-end reinforcement learning workflows for robotics using Azure infrastructure and NVIDIA technologies including Isaac Lab, Isaac Sim, and OSMO. The architecture provides production-ready infrastructure, training pipelines, and deployment workflows with Azure-native authentication and storage integration.

## Architecture Overview

The architecture integrates Azure services and NVIDIA robotics frameworks (Isaac Lab, Isaac Sim, OSMO) to provide scalable, secure RL training infrastructure.

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

## Key Features

### Infrastructure as Code

* Modular Terraform configurations referencing [microsoft/edge-ai](https://github.com/microsoft/edge-ai) components

### MLflow Integration

* Automatic metric logging from SKRL agents to Azure ML
* Comprehensive tracking of episode statistics, losses, optimization metrics, and timing data
* Configurable logging intervals and metric filtering
* See [MLflow Integration Guide](docs/mlflow-integration.md) for details

## Local Development Setup

### Prerequisites

* [pyenv](https://github.com/pyenv/pyenv)
* Python 3.11 (required by Isaac Sim 5.X)

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

## License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for details.

## Support

For issues and questions:

* Review [microsoft/edge-ai](https://github.com/microsoft/edge-ai) documentation

## Acknowledgments

This reference architecture builds upon:

* [microsoft/edge-ai](https://github.com/microsoft/edge-ai) - Edge AI infrastructure components
* [NVIDIA Isaac Lab](https://github.com/isaac-sim/IsaacLab) - RL task framework
* [NVIDIA Isaac Sim](https://developer.nvidia.com/isaac-sim) - Physics simulation
* [NVIDIA OSMO](https://developer.nvidia.com/osmo) - Workflow orchestration
