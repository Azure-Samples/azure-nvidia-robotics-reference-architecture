---
title: Contributing to Azure NVIDIA Robotics Reference Architecture
description: Contribution guidelines covering development setup, conventions, testing requirements, and code of conduct
ms.date: 2026-02-07
ms.topic: how-to
---

Thank you for your interest in contributing to this project. This guide outlines how to contribute effectively.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Review the [README](README.md) for project setup
4. Create a feature branch for your changes

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

## Testing Requirements

All contributions require appropriate tests. This policy supports code quality and the project's [OpenSSF Best Practices](https://www.bestpractices.dev/) goals.

### Policy

* New features require accompanying unit tests.
* Bug fixes require regression tests that reproduce the fixed behavior.
* Refactoring changes must not reduce test coverage.

### Running Tests

Run the full test suite:

```bash
pytest tests/
```

Run tests within the devcontainer:

```bash
uv run pytest tests/
```

Run tests with coverage reporting:

```bash
pytest tests/ --cov=src --cov-report=term-missing
```

### Test Organization

Tests mirror the source directory structure under `tests/`:

| Source Path                     | Test Path                     |
|---------------------------------|-------------------------------|
| `src/training/utils/env.py`     | `tests/unit/test_env.py`      |
| `src/training/utils/metrics.py` | `tests/unit/test_metrics.py`  |
| `src/common/cli_args.py`        | `tests/unit/test_cli_args.py` |

### Test Categories

| Marker        | Description                        | CI Behavior                   |
|---------------|------------------------------------|-------------------------------|
| *(default)*   | Unit tests, fast, no external deps | Always runs                   |
| `slow`        | Tests exceeding 5 seconds          | Runs on main, optional on PRs |
| `integration` | Requires external services         | Runs on main only             |
| `gpu`         | Requires CUDA runtime              | Excluded from standard CI     |

Skip categories selectively:

```bash
pytest tests/ -m "not slow and not gpu"
```

### Coverage Targets

Coverage thresholds increase with each milestone:

| Milestone | Minimum Coverage |
|-----------|------------------|
| v0.4.0    | 40%              |
| v0.5.0    | 60%              |
| v0.6.0    | 80%              |

CI enforces the current milestone's minimum. PRs that reduce coverage below the threshold fail validation.

### Configuration

Pytest configuration is in `pyproject.toml` under `[tool.pytest.ini_options]`. Coverage configuration is in `pyproject.toml` under `[tool.coverage.run]` and `[tool.coverage.report]`.

### Shell and Infrastructure Tests

Shell scripts use [BATS-core](https://github.com/bats-core/bats-core) for testing and PowerShell modules use [Pester v5](https://pester.dev/). Terraform modules use the native `terraform test` framework. Each area's README contains framework-specific details.

## Code of Conduct

This project follows the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
