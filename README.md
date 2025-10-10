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
│       └── job-templates/              # Job configuration templates
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

- Modular Terraform configurations referencing [microsoft/edge-ai](https://github.com/microsoft/edge-ai) components

## Prerequisites

- To be added...

## Quick Start

```bash
# To be added...
```

## License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for details.

## Support

For issues and questions:

- Review [microsoft/edge-ai](https://github.com/microsoft/edge-ai) documentation

## Acknowledgments

This reference architecture builds upon:

- [microsoft/edge-ai](https://github.com/microsoft/edge-ai) - Edge AI infrastructure components
- [NVIDIA Isaac Lab](https://github.com/isaac-sim/IsaacLab) - RL task framework
- [NVIDIA Isaac Sim](https://developer.nvidia.com/isaac-sim) - Physics simulation
- [NVIDIA OSMO](https://developer.nvidia.com/osmo) - Workflow orchestration
