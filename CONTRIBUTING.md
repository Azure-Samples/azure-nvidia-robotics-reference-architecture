---
title: Contributing
description: How to contribute to the Azure NVIDIA Robotics Reference Architecture
author: Microsoft Robotics-AI Team
ms.date: 2026-02-08
ms.topic: guide
keywords:
  - contributing
  - development workflow
  - pull requests
  - code review
---

Thank you for your interest in contributing to this project. ❤️

All types of contributions are encouraged and valued — infrastructure code, deployment automation, documentation, training scripts, and ML workflows. Read the relevant sections below before making your contribution.

> If you like the project but don't have time to contribute, consider starring the repository or sharing it with colleagues working in robotics and AI.

## Getting Started

1. Read the [Contributing Guide](docs/contributing/README.md) for prerequisites, workflow, and conventions
2. Review the [Prerequisites](docs/contributing/prerequisites.md) for required tools and Azure access
3. Fork the repository and clone your fork locally
4. Review the [README](README.md) for project overview and architecture
5. Create a feature branch following [conventional commit](docs/contributing/README.md#-commit-messages) naming
6. Run [validation](#build-and-validation) before submitting

## Contributing Guides

Detailed documentation lives in [`docs/contributing/`](docs/contributing/):

| Guide                                                                   | Description                                                    |
|-------------------------------------------------------------------------|----------------------------------------------------------------|
| [Contributing Guide](docs/contributing/README.md)                       | Main hub — prerequisites, workflow, commit messages, style     |
| [Prerequisites](docs/contributing/prerequisites.md)                     | Required tools, Azure access, NGC credentials, build commands  |
| [Contribution Workflow](docs/contributing/contribution-workflow.md)     | Bug reports, feature requests, first contributions             |
| [Pull Request Process](docs/contributing/pull-request-process.md)       | PR workflow, reviewers, approval criteria                      |
| [Infrastructure Style](docs/contributing/infrastructure-style.md)       | Terraform conventions, shell scripts, copyright headers        |
| [Deployment Validation](docs/contributing/deployment-validation.md)     | Validation levels, testing templates, cost optimization        |
| [Cost Considerations](docs/contributing/cost-considerations.md)         | Component costs, budgeting, regional pricing                   |
| [Security Review](docs/contributing/security-review.md)                 | Security checklist, credential handling, dependency updates    |

## I Have a Question

Search existing resources before asking:

- Search [GitHub Issues](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues) for similar questions or problems
- Check [GitHub Discussions](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/discussions) for community Q&A
- Review the [docs/](docs/) directory for troubleshooting guides

If you cannot find an answer, open a [new discussion](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/discussions/new) in the Q&A category. Provide context about what you are trying to accomplish, what you have tried, and any error messages. For bugs or feature requests, use [GitHub Issues](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/new) instead.

## Development Environment

Run the setup script to configure your local development environment:

```bash
./setup-dev.sh
```

This installs npm dependencies for linting, spell checking, and link validation. See the [Prerequisites](docs/contributing/prerequisites.md) guide for required tools and version requirements.

## Build and Validation

Run these commands to validate changes before submitting a PR:

```bash
npm run lint:md        # Markdownlint
npm run lint:links     # Markdown link validation
npm run spell-check    # cspell
```

For Terraform and shell script validation, see the [Prerequisites](docs/contributing/prerequisites.md#build-and-validation-requirements) guide.

## Issue Title Conventions

Use structured titles to maintain consistency and enable automation.

### Convention Tiers

| Format         | Use Case       | Example                            |
|----------------|----------------|------------------------------------|
| `type(scope):` | Code changes   | `feat(ci): Add pytest workflow`    |
| `[Task]:`      | Work items     | `[Task]: Achieve OpenSSF badge`    |
| `[Policy]:`    | Governance     | `[Policy]: Define code of conduct` |
| `[Docs]:`      | Doc planning   | `[Docs]: Publish security policy`  |
| `[Infra]:`     | Infrastructure | `[Infra]: Sign release tags`       |

### Conventional Commits Types

| Type       | Description                             |
|------------|-----------------------------------------|
| `feat`     | New feature or capability               |
| `fix`      | Bug fix                                 |
| `docs`     | Documentation only                      |
| `refactor` | Code change that neither fixes nor adds |
| `test`     | Adding or correcting tests              |
| `ci`       | CI configuration changes                |
| `chore`    | Maintenance tasks                       |

### Repository Scopes

| Scope       | Area                     |
|-------------|--------------------------|
| `terraform` | Infrastructure as Code   |
| `scripts`   | Shell and Python scripts |
| `training`  | ML training code         |
| `workflows` | AzureML/Osmo workflows   |
| `ci`        | GitHub Actions           |
| `deploy`    | Deployment artifacts     |
| `docs`      | Documentation            |
| `security`  | Security-related changes |

### Title Examples

```text
feat(ci): Add CodeQL security scanning workflow
fix(terraform): Correct AKS node pool configuration
docs(deploy): Add VPN deployment documentation
refactor(scripts): Consolidate common functions
test(training): Add pytest fixtures
[Task]: Achieve code coverage target
[Policy]: Define input validation requirements
```

## Release Process

This project uses [release-please](https://github.com/googleapis/release-please) for automated version management. All commits to `main` must follow [Conventional Commits](https://www.conventionalcommits.org/) format:

- `feat:` commits trigger a **minor** version bump
- `fix:` commits trigger a **patch** version bump
- `docs:`, `chore:`, `refactor:` commits appear in the changelog without a version bump
- Commits with `BREAKING CHANGE:` footer trigger a **major** version bump

After merging to `main`, release-please automatically creates a release PR with updated `CHANGELOG.md` and version bumps. Merging that PR creates a GitHub Release and git tag.

For commit message format details, see [commit-message.instructions.md](.github/instructions/commit-message.instructions.md).

## Code of Conduct

This project adopts the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). See [CODE_OF_CONDUCT.md](.github/CODE_OF_CONDUCT.md) for details, or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with questions.

## Reporting Security Issues

**Do not** report security vulnerabilities through public GitHub issues. See [SECURITY.md](SECURITY.md) for reporting instructions.

## Support

For questions and community discussion, see [SUPPORT.md](SUPPORT.md).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

## Attribution

This contributing guide is adapted for reference architecture contributions and Azure + NVIDIA robotics infrastructure.

Copyright (c) Microsoft Corporation. Licensed under the MIT License.
