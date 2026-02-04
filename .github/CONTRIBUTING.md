---
title: Contributing to Azure NVIDIA Robotics Reference Architecture
description: Guide for contributing to the Azure NVIDIA Robotics Reference Architecture, including prerequisites, deployment validation, and style conventions
author: Microsoft Robotics-AI Team
ms.date: 2026-02-03
ms.topic: how-to
keywords:
  - azure
  - nvidia
  - robotics
  - kubernetes
  - terraform
  - contributing
  - reference architecture
---

## 🤝 Contributing to Azure NVIDIA Robotics Reference Architecture

Contributions improve this reference architecture for the robotics and AI community. This project accepts contributions for infrastructure code (Terraform/shell), deployment automation, documentation, training scripts, and ML workflows.

Reference architectures emphasize deployment validation over automated testing. Contributors validate changes through actual Azure deployments, which incurs cost. This guide provides cost-transparent guidance for different contribution scopes.

Contributions can include:

* Infrastructure improvements (Terraform modules, networking, security)
* Deployment automation enhancements (shell scripts, Kubernetes manifests)
* Documentation updates (guides, troubleshooting, architecture diagrams)
* Training script optimizations (Python, MLflow integration)
* Workflow templates (AzureML, OSMO)
* Bug fixes and issue resolution

## 📚 Table of Contents

* [Prerequisites](#-prerequisites)
* [Build and Validation Requirements](#-build-and-validation-requirements)
* [Code of Conduct](#-code-of-conduct)
* [I Have a Question](#-i-have-a-question)
* [I Want To Contribute](#-i-want-to-contribute)
  * [Legal Notice](#legal-notice)
  * [Reporting Bugs](#reporting-bugs)
  * [Suggesting Enhancements](#suggesting-enhancements)
  * [Your First Code Contribution](#your-first-code-contribution)
  * [Improving The Documentation](#improving-the-documentation)
* [Commit Messages](#-commit-messages)
* [Markdown Style](#-markdown-style)
* [Infrastructure as Code Style](#️-infrastructure-as-code-style)
* [Deployment Validation](#-deployment-validation)
* [Pull Request Process](#-pull-request-process)
* [Cost Considerations](#-cost-considerations)
* [Security Review Process](#-security-review-process)
* [Attribution](#-attribution)

### Extended Guides

Detailed documentation for specialized topics:

* [Infrastructure Style Guide](../docs/contributing/infrastructure-style.md) - Terraform conventions, shell scripts, copyright headers
* [Deployment Validation Guide](../docs/contributing/deployment-validation.md) - Validation levels, testing templates, cost optimization
* [Cost Considerations Guide](../docs/contributing/cost-considerations.md) - Component costs, budgeting, regional pricing
* [Security Review Guide](../docs/contributing/security-review.md) - Security checklist, credential handling, dependency updates

## 📋 Prerequisites

### Required Tools

Install these tools before contributing:

| Tool         | Minimum Version | Installation                                                              |
| ------------ | --------------- | ------------------------------------------------------------------------- |
| Terraform    | 1.9.8           | <https://developer.hashicorp.com/terraform/install>                       |
| Azure CLI    | 2.65.0          | <https://learn.microsoft.com/cli/azure/install-azure-cli>                 |
| kubectl      | 1.31            | <https://kubernetes.io/docs/tasks/tools/>                                 |
| Helm         | 3.16            | <https://helm.sh/docs/intro/install/>                                     |
| Node.js/npm  | 20+ LTS         | <https://nodejs.org/>                                                     |
| Python       | 3.11+           | <https://www.python.org/downloads/>                                       |
| shellcheck   | 0.10+           | <https://www.shellcheck.net/>                                             |

### Azure Access Requirements

Deploying this architecture requires Azure subscription access with specific permissions and quotas:

**Subscription Roles:**

* `Contributor` role for resource group creation and management
* `User Access Administrator` role for managed identity assignment

**GPU Quota:**

* Request GPU VM quota in your target region before deployment
* Architecture uses `Standard_NC24ads_A100_v4` (24 vCPU, 220 GB RAM, 1x A100 80GB GPU)
* Check quota: `az vm list-usage --location <region> --query "[?name.value=='standardNCadsA100v4Family']"`
* Request increase through Azure Portal → Quotas → Compute

**Regional Availability:**

* Verify GPU VM availability in target region: <https://azure.microsoft.com/global-infrastructure/services/?products=virtual-machines>
* Architecture validated in `eastus`, `westus2`, `westeurope`

### NVIDIA NGC Account

Training workflows use NVIDIA GPU Operator and Isaac Lab, which require NGC credentials:

* Create account: <https://ngc.nvidia.com/signup>
* Generate API key: NGC Console → Account Settings → Generate API Key
* Store API key in Azure Key Vault or Kubernetes secret (deployment scripts provide guidance)

### Cost Awareness

Full deployment validation incurs Azure costs. Understand cost structure before deploying:

**GPU Virtual Machines:**

* `Standard_NC24ads_A100_v4`: ~$3.06/hour per VM (pay-as-you-go)
* 8-hour validation session: ~$25
* 40-hour work week: ~$125

**Managed Services:**

* AKS control plane: ~$0.10/hour (~$73/month)
* Log Analytics workspace: ~$2.76/GB ingested
* Storage accounts: ~$0.02/GB (block blob, hot tier)
* Azure Container Registry: Basic tier ~$5/month

**Cost Optimization:**

* Use `terraform destroy` immediately after validation
* Automate cleanup with `-auto-approve` flag
* Monitor costs: Azure Portal → Cost Management + Billing
* Set budget alerts to prevent overruns

**Estimated Costs:**

* Quick validation (deploy + verify + destroy): ~$25-50
* Extended development session (8 hours): ~$50-100
* Monthly development (40 hours): ~$200-300

## 🔨 Build and Validation Requirements

### Prerequisites

Verify tool versions before validating:

```bash
# Terraform
terraform version  # >= 1.9.8

# Azure CLI
az version  # >= 2.65.0

# kubectl
kubectl version --client  # >= 1.31

# Helm
helm version  # >= 3.16

# Node.js (for documentation linting)
node --version  # >= 20

# Python (for training scripts)
python --version  # >= 3.11

# shellcheck (for shell script validation)
shellcheck --version  # >= 0.10
```

### Validation Commands

Run these commands before committing:

**Terraform:**

```bash
# Format check (required)
terraform fmt -check -recursive deploy/

# Initialize and validate (required for infrastructure changes)
cd deploy/001-iac/
terraform init
terraform validate
```

**Shell Scripts:**

```bash
# Lint all shell scripts (required)
shellcheck deploy/**/*.sh scripts/**/*.sh
```

**Documentation:**

```bash
# Install dependencies (first time only)
npm install

# Lint markdown (required for documentation changes)
npm run lint:md
```

## 📜 Code of Conduct

This project adopts the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

For more information, see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with questions or comments.

## ❓ I Have a Question

Search existing resources before asking questions:

* **Issues:** Search [GitHub Issues](https://github.com/microsoft/azure-nvidia-robotics-reference-architecture/issues) for similar questions or problems
* **Discussions:** Check [GitHub Discussions](https://github.com/microsoft/azure-nvidia-robotics-reference-architecture/discussions) for community Q&A
* **Documentation:** Review [docs/](../docs/) for troubleshooting guides
* **Troubleshooting:** See [azureml-validation-job-debugging.md](../docs/azureml-validation-job-debugging.md) for common deployment and workflow issues

If you cannot find an answer:

1. Open a [new discussion](https://github.com/microsoft/azure-nvidia-robotics-reference-architecture/discussions/new) in the Q&A category
2. Provide context: What you are trying to accomplish, what you have tried, error messages or unexpected behavior
3. Include relevant details: Azure region, Terraform version, deployment step, error logs

Maintainers and community members respond to discussions. For bugs or feature requests, use GitHub Issues instead.

## 🤝 I Want To Contribute

### Legal Notice

When contributing to this project, you must agree that you have authored 100% of the content, that you have the necessary rights to the content, and that the content you contribute may be provided under the project license.

This project uses the Microsoft Contributor License Agreement (CLA) to define the terms under which intellectual property has been received. All contributions require acceptance of the CLA.

Visit <https://cla.opensource.microsoft.com> to sign the CLA electronically. When you submit a pull request, a bot will automatically determine whether you need to sign the CLA. Simply follow the instructions provided.

### Reporting Bugs

#### Before Submitting a Bug Report

Before creating a bug report:

* Search [existing issues](https://github.com/microsoft/azure-nvidia-robotics-reference-architecture/issues) for similar deployment errors or problems
* Verify you are using tested versions: Terraform >= 1.9.8, Azure CLI >= 2.65.0
* Check Azure resource quotas and limits: `az vm list-usage --location <region>`
* Confirm network mode (private/hybrid/public) matches documented requirements
* Test with minimal configuration first (public network mode before private, single GPU node before multi-node)

#### How to Submit a Bug Report

Create a [new issue](https://github.com/microsoft/azure-nvidia-robotics-reference-architecture/issues/new) with:

* **Title format:** `[Component][Subcomponent] Brief description`
  * Examples: `[Terraform][Platform Module] Private endpoint creation fails`, `[AzureML Extension] GPU pod scheduling timeout`
* **Environment details:**
  * Azure region
  * Network mode (private/hybrid/public)
  * Terraform version
  * Azure CLI version
  * Relevant VM SKUs (GPU node pool)
* **Expected vs. actual behavior:**
  * What should happen
  * What actually happened
* **Deployment logs:**
  * `terraform apply` output (sanitize sensitive values)
  * Azure CLI error messages
  * Kubernetes pod logs if applicable: `kubectl logs <pod-name> -n <namespace>`
* **Azure resource state:**
  * `az resource show --ids <resource-id>` output for affected resources
  * Resource provisioning state: `az resource list --resource-group <rg> --query "[].{name:name, provisioningState:provisioningState}"`
* **Reproduction steps:**
  * Numbered list of commands from initial setup
  * Configuration files used (sanitize sensitive values)
* **Cost impact (if relevant):**
  * Resources deployed and hourly cost: `az consumption usage list`
  * Example: "Deployed 3x Standard_NC24ads_A100_v4 VMs running at ~$9/hour"

#### Bug Report Example

````markdown
**Title:** [Terraform][SIL Module] AKS cluster creation fails with subnet authorization error

**Environment:**

* Region: eastus2
* Network mode: private
* Terraform: 1.9.8
* Azure CLI: 2.65.0
* VM SKU: Standard_NC24ads_A100_v4

**Expected Behavior:**

`terraform apply` creates AKS cluster with GPU node pool using private network configuration.

**Actual Behavior:**

Deployment fails during AKS cluster creation with authorization error:

```text
Error: creating Managed Kubernetes Cluster: Code="LinkedAuthorizationFailed"
Message="The client has permission to perform action 'Microsoft.ContainerService/managedClusters/write'
on scope '/subscriptions/.../resourceGroups/.../providers/Microsoft.ContainerService/managedClusters/aks-cluster';
however, it does not have permission to perform action 'Microsoft.Network/virtualNetworks/subnets/join/action'
on the linked scope(s) '/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks-subnet'"
```

**Resource State:**

```bash
az resource show --ids /subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks-subnet
```

Output shows subnet exists but lacks role assignment for AKS managed identity.

**Reproduction Steps:**

1. Set up `terraform.tfvars` with private network mode
2. Run `terraform init && terraform plan`
3. Run `terraform apply`
4. Observe failure at AKS cluster creation step

**Configuration:**

```hcl
network_mode = "private"
enable_private_cluster = true
aks_subnet_cidr = "10.0.2.0/24"
```

**Cost Impact:**

Reproduced the issue with prerequisite resources (VNet, Key Vault, Storage Account) deployed before AKS creation step failed. Incurred ~$0.10/hour while debugging. Destroyed all resources after confirming the issue.

**Additional Context:**

Deployment script creates VNet and subnet but appears to skip role assignment for AKS managed identity on subnet. Manually assigning `Network Contributor` role on subnet allows deployment to succeed.
````

### Suggesting Enhancements

#### Before Submitting an Enhancement

Before suggesting an enhancement:

* Determine if the enhancement is broadly applicable (blueprint improvement) or organization-specific (belongs in a fork)
* Search [existing issues](https://github.com/microsoft/azure-nvidia-robotics-reference-architecture/issues) and [pull requests](https://github.com/microsoft/azure-nvidia-robotics-reference-architecture/pulls) for similar proposals
* Consider cost implications if adding new Azure services or increasing resource scale
* Verify compatibility with all three network modes (private/hybrid/public) or document known limitations
* Check if enhancement aligns with reference architecture goals (generalized deployment patterns vs. specific use cases)

#### How to Submit an Enhancement

Create a [new issue](https://github.com/microsoft/azure-nvidia-robotics-reference-architecture/issues/new) with:

* **Clear title** describing the enhancement
* **Problem statement:** What limitation or gap does this enhancement address?
* **Proposed solution:** Describe the technical approach
* **Azure services:** List new services required, with cost implications
* **Breaking changes:** Indicate if existing deployments require migration
* **Contributor personas:** Which personas benefit most (ML engineers, infrastructure engineers, DevOps/SRE, robotics developers)?
* **Network mode compatibility:** Specify if enhancement works in all modes or has limitations
* **Alternatives considered:** Other approaches evaluated and why this solution is preferred
* **Reference architecture precedent:** Similar patterns in other Azure reference architectures or Microsoft guidance

### Your First Code Contribution

This reference architecture validates through deployment rather than automated tests. The validation level depends on your contribution type.

#### PR Workflow

1. **Fork** the repository to your GitHub account
2. **Create a branch** from `main` with descriptive name: `feature/private-endpoint-support` or `fix/gpu-scheduling-timeout`
3. **Make changes** following style guides and conventions
4. **Open a draft PR** early for maintainer feedback
5. **Perform validation** appropriate to your contribution type (see table below)
6. **Mark PR ready for review** after completing validation
7. **Address review feedback** promptly
8. **Merge** occurs after approval and passing maintainer integration tests

#### Validation Expectations

| Contribution Type           | Expected Validation                                                                 |
| --------------------------- | ----------------------------------------------------------------------------------- |
| Documentation               | Read-through, link check (`npm run lint:md`)                                        |
| Shell scripts               | ShellCheck validation, test in local/minimal environment                            |
| Terraform modules           | `terraform fmt`, `terraform validate`, `terraform plan` output attached to PR       |
| Full infrastructure changes | Deployment testing in dev subscription with cost estimate and teardown confirmation |
| Training scripts            | AzureML job submission in test workspace with logs                                  |
| Workflow templates          | Workflow execution validation with job outputs                                      |
| Configuration manifests     | Syntax validation, test deployment in non-production cluster                        |

#### Testing Documentation

In your PR description, document:

* **Validation performed:** Commands run, deployments tested
* **Environment used:** Dev subscription, network mode, Azure region
* **Cost incurred:** Estimate for resources deployed during testing
* **Known limitations:** Untested scenarios or edge cases

Maintainers perform integration testing across multiple scenarios before merge. Contributors are not expected to test all permutations (different regions, network modes, SKU variations).

### Improving The Documentation

Documentation contributions improve the architecture for the entire robotics and AI community.

#### High-Value Documentation Contributions

* **Deployment troubleshooting guides:** Expand [azureml-validation-job-debugging.md](../docs/azureml-validation-job-debugging.md) with new scenarios
* **Region/SKU compatibility matrices:** Document tested combinations and known limitations
* **Cost optimization strategies:** Real-world cost profiles and reduction techniques
* **Network architecture decisions:** Guidance on when to use private vs. hybrid vs. public modes
* **Migration guides:** Instructions for handling breaking changes or infrastructure updates
* **Architecture decision records (ADRs):** Document major design choices and trade-offs

#### Documentation Validation

Before submitting documentation changes:

* Run `npm run lint:md` to check formatting and style
* Verify internal links with `npm run lint:links` (if available)
* Test code samples in deployment environment
* Review against [docs-style-and-conventions.instructions.md](instructions/docs-style-and-conventions.instructions.md)

## 💬 Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for commit messages. Follow the standard format:

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**

* `feat` - New feature
* `fix` - Bug fix
* `docs` - Documentation changes
* `refactor` - Code refactoring (no functional changes)
* `perf` - Performance improvement
* `test` - Test additions or corrections
* `chore` - Maintenance tasks
* `ci` - CI/CD pipeline changes

**Scopes:**

* `terraform` - Infrastructure as Code changes
* `k8s` - Kubernetes manifests or Helm charts
* `azureml` - Azure Machine Learning integration
* `osmo` - OSMO workflow orchestration
* `scripts` - Shell scripts and automation
* `docs` - Documentation
* `deploy` - Deployment procedures

**Guidelines:**

* Use present tense: "add feature" not "added feature"
* Keep subject line under 100 characters
* Capitalize subject line
* Do not end subject line with period
* Provide detailed body for non-trivial changes

**Examples:**

```bash
# Feature addition
feat(terraform): add private endpoint support for PostgreSQL

Enable private endpoint creation for PostgreSQL Flexible Server in
platform module. Includes DNS zone configuration and subnet delegation.

# Bug fix
fix(k8s): correct GPU node pool selector in OSMO backend

Update node selector from 'gpu: true' to 'accelerator: nvidia-a100'
to match AKS GPU node pool labels.

# Documentation update
docs(deployment): add troubleshooting guide for quota errors

Document common Azure quota errors and resolution steps for GPU VM
families in different regions.

# Breaking change
feat(terraform)!: migrate to Terraform 1.10 provider syntax

BREAKING CHANGE: Requires Terraform >= 1.10.0. Variable names changed
from snake_case to kebab-case. See migration guide in CHANGELOG.md.
```

For complete commit message guidance, see [commit-message.instructions.md](instructions/commit-message.instructions.md).

## 📝 Markdown Style

All Markdown documents must follow consistent formatting and structure standards.

**YAML Frontmatter:**

Every Markdown file requires YAML frontmatter with these fields:

```yaml
---
title: Document Title
description: Brief description for search indexing (150 chars max)
author: Microsoft Robotics-AI Team
ms.date: YYYY-MM-DD
ms.topic: concept | how-to | reference | tutorial
keywords:
  - keyword1
  - keyword2
  - keyword3
---
```

**Formatting Rules:**

* Use ATX-style headers (`##` not underlines)
* Prefer tables over lists for structured data
* Use GitHub alert syntax for callouts:
  * `> [!NOTE]` for informational content
  * `> [!WARNING]` for cautions
  * `> [!IMPORTANT]` for critical information
* Code blocks must specify language: ` ```bash ` not ` ``` `
* Use relative links for internal documentation
* Wrap file paths in backticks: `deploy/001-iac/main.tf`
* Use meaningful link text (not "click here")

**Validation:**

```bash
# Lint markdown formatting
npm run lint:md

# Check internal links
npm run lint:links
```

For complete Markdown guidance, see [docs-style-and-conventions.instructions.md](instructions/docs-style-and-conventions.instructions.md).

## 🏗️ Infrastructure as Code Style

Infrastructure code follows strict conventions for consistency, security, and maintainability.

**Key Terraform Conventions:**

* Format with `terraform fmt -recursive deploy/` before committing
* Use descriptive snake_case variables with prefixes (`enable_`, `is_`, `aks_`)
* Include standard tags on all Azure resources
* Prefer managed identities over service principals
* Store secrets in Key Vault, never in code

**Key Shell Script Conventions:**

* Begin scripts with `#!/usr/bin/env bash` and `set -euo pipefail`
* Include header documentation with prerequisites, environment variables, and usage
* Validate with `shellcheck` before committing

**Copyright Headers:**

All source files require the Microsoft copyright header:

```text
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
```

For complete conventions with examples, see [Infrastructure Style Guide](../docs/contributing/infrastructure-style.md).

## 🧪 Deployment Validation

This reference architecture validates through deployment rather than automated testing. Choose validation level based on contribution scope and cost constraints.

### Validation Levels

| Level                   | What                                                                        | When to Use                    | Cost    |
| ----------------------- | --------------------------------------------------------------------------- | ------------------------------ | ------- |
| **Level 1: Static**     | `terraform fmt`, `terraform validate`, `shellcheck`, `npm run lint:md`      | Every contribution             | $0      |
| **Level 2: Plan**       | `terraform plan` with documented output                                     | Terraform changes              | $0      |
| **Level 3: Deployment** | Full deployment in dev subscription                                         | Major infrastructure changes   | $25-50  |
| **Level 4: Workflow**   | Training job execution                                                      | Script/workflow changes        | $5-30   |

**Static validation is required for all PRs:**

```bash
terraform fmt -check -recursive deploy/
terraform validate deploy/001-iac/
shellcheck deploy/**/*.sh scripts/**/*.sh
npm run lint:md
```

For complete validation procedures, testing templates, and cost optimization strategies, see [Deployment Validation Guide](../docs/contributing/deployment-validation.md).

## 🔄 Pull Request Process

This reference architecture uses a deployment-based validation model rather than automated testing. The PR workflow adapts to different contribution types and validation levels.

### PR Workflow Steps

1. **Fork and Branch**: Create a feature branch from your fork's main branch
2. **Make Changes**: Implement improvements following style guides
3. **Validate Locally**: Run appropriate validation level (static/plan/deployment)
4. **Create Draft PR**: Open draft PR with validation documentation
5. **Request Review**: Mark PR ready when validation complete

### Review Process

**Reviewer Assignment:**

Maintainers assign reviewers based on contribution type:

| Contribution Type    | Primary Reviewer              |
| -------------------- | ----------------------------- |
| Terraform modules    | Cloud Infrastructure Engineer |
| Kubernetes manifests | DevOps/SRE Engineer           |
| Training scripts     | ML Engineer                   |
| OSMO workflows       | Robotics Developer            |
| Documentation        | Any maintainer                |
| Security changes     | Security Contributor          |

**Review Cycles:**

* First review: Focus on architecture, security, cost implications
* Subsequent reviews: Address specific feedback
* Final review: Verify all validation documentation complete

**Approval Criteria:**

* [ ] Follows style guides (commit messages, markdown, infrastructure)
* [ ] Appropriate validation level completed
* [ ] Testing documentation provided in PR description
* [ ] No security vulnerabilities introduced
* [ ] Cost implications documented (if applicable)
* [ ] Breaking changes clearly communicated

### Update Process

This reference architecture uses a rolling update model rather than semantic versioning. Users fork and adapt the blueprint for their own use.

#### Update Types

**Documentation Updates:**

* Continuous improvements to READMEs, guides, and troubleshooting docs
* No announcement needed for minor clarifications
* Significant new guides announced via repository discussions

**Enhancement Updates:**

* New capabilities (e.g., new network mode, new Azure service integration)
* Announced via GitHub Releases with usage examples
* Backward compatible when possible

**Breaking Changes:**

* Infrastructure modifications that require resource recreation
* Terraform variable/output changes
* Deployment script interface changes

**Breaking Change Communication:**

* GitHub Release with `[BREAKING]` prefix
* Migration guide in release notes
* Updated deployment documentation
* Announcement in repository discussions

#### Component Updates

**Dependency Management:**

Update dependencies regularly for security patches and feature improvements:

```bash
# Update Terraform provider versions
terraform init -upgrade

# Update Helm chart versions
helm repo update
helm search repo nvidia-gpu-operator --versions

# Update Python dependencies
pip install -r requirements.txt --upgrade
```

**Migration Approach:**

When pulling upstream updates:

```bash
# Create branch for upstream updates
git checkout -b upstream-updates

# Pull latest changes
git fetch upstream
git merge upstream/main

# Resolve conflicts (prioritize your customizations)
# Test deployment in dev environment
# Merge to your main branch after validation
```

#### Staying Updated

**Recommended Approach:**

* Watch repository for releases
* Review release notes before pulling updates
* Test updates in dev environment before production
* Maintain customizations in separate branch/overlay

## 💰 Cost Considerations

Full deployment testing incurs Azure costs. Plan accordingly and destroy resources promptly.

**Testing Budget Summary:**

| Contribution Type   | Typical Cost | Testing Approach          |
| ------------------- | ------------ | ------------------------- |
| Documentation       | $0           | Linting only              |
| Terraform modules   | $10-25       | Plan + short deployment   |
| Training scripts    | $15-30       | Single training job       |
| Full infrastructure | $25-50       | Complete deployment cycle |

**Key Cost Drivers:**

* GPU VMs: ~$3.06/hour per Standard_NC24ads_A100_v4 node
* Managed services: ~$50-100/month combined (Storage, Key Vault, PostgreSQL, Redis)

**Minimize costs with:**

```bash
# Single GPU node, public network mode
terraform apply -var="gpu_node_count=1" -var="network_mode=public"

# Always destroy after testing
terraform destroy -auto-approve -var-file=terraform.tfvars
```

For component cost breakdowns, budgeting commands, and regional pricing, see [Cost Considerations Guide](../docs/contributing/cost-considerations.md).

## 🔒 Security Review Process

Security-sensitive contributions require additional review to ensure Azure best practices.

**Security Review Required For:**

* RBAC and permissions changes
* Private endpoints and networking configuration
* Credential handling and secrets management
* Network policies and firewall rules
* Workload identity configuration

**Key Requirements:**

* Managed identities over service principals
* Secrets in Key Vault, never in code
* Least privilege RBAC assignments
* Security scanning before PR submission

**Reporting Security Issues:**

**DO NOT** report vulnerabilities through public GitHub issues. Report to Microsoft Security Response Center (MSRC). See [SECURITY.md](../SECURITY.md).

For the complete security checklist, dependency update process, and scanning requirements, see [Security Review Guide](../docs/contributing/security-review.md).

## 📚 Attribution

This contributing guide is based on [microsoft/robotics-ai's CONTRIBUTING.md](https://github.com/microsoft/robotics-ai/blob/main/CONTRIBUTING.md), adapted for reference architecture contributions and Azure + NVIDIA robotics infrastructure.

Copyright (c) Microsoft Corporation. Licensed under the MIT License.
