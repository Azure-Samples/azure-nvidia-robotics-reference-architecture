# Contributing to Azure NVIDIA Robotics Reference Architecture

Thank you for your interest in contributing to this project. This guide outlines how to contribute effectively.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Review the [README](README.md) for project setup
4. Create a feature branch for your changes

## Issue Title Conventions

Use structured titles to maintain consistency and enable automation.

### Convention Tiers

| Format | Use Case | Example |
|--------|----------|---------|
| `type(scope):` | Code changes | `feat(ci): Add pytest workflow` |
| `[Task]:` | Work items | `[Task]: Achieve OpenSSF badge` |
| `[Policy]:` | Governance | `[Policy]: Define code of conduct` |
| `[Docs]:` | Doc planning | `[Docs]: Publish security policy` |
| `[Infra]:` | Infrastructure | `[Infra]: Sign release tags` |

### Conventional Commits Types

| Type | Description |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes nor adds |
| `test` | Adding or correcting tests |
| `ci` | CI configuration changes |
| `chore` | Maintenance tasks |

### Repository Scopes

| Scope | Area |
|-------|------|
| `terraform` | Infrastructure as Code |
| `scripts` | Shell and Python scripts |
| `training` | ML training code |
| `workflows` | AzureML/Osmo workflows |
| `ci` | GitHub Actions |
| `deploy` | Deployment artifacts |
| `docs` | Documentation |
| `security` | Security-related changes |

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

## Code of Conduct

This project follows the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
