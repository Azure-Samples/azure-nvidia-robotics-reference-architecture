---
title: Contributing Guides
description: Detailed contribution guides for the Azure NVIDIA Robotics Reference Architecture
author: Microsoft Robotics-AI Team
ms.date: 2026-02-03
ms.topic: overview
---

This directory contains detailed guidance for specific contribution workflows. Start with the main [CONTRIBUTING.md](../../.github/CONTRIBUTING.md) for an overview, then reference these guides for in-depth information.

## Available Guides

| Guide                                             | Description                                                      |
|---------------------------------------------------|------------------------------------------------------------------|
| [Deployment Validation](deployment-validation.md) | 4-level validation model, testing templates, cost optimization   |
| [Cost Considerations](cost-considerations.md)     | Testing budgets, cost tracking, regional pricing                 |
| [Security Review](security-review.md)             | Security checklist, credential handling, dependency updates      |
| [Infrastructure Style](infrastructure-style.md)   | Terraform conventions, shell script standards, copyright headers |

## Quick Reference

**Contribution Type → Recommended Guide:**

| Changing...             | Read...                                                                                                 |
|-------------------------|---------------------------------------------------------------------------------------------------------|
| Terraform modules       | [Infrastructure Style](infrastructure-style.md), then [Deployment Validation](deployment-validation.md) |
| Shell scripts           | [Infrastructure Style](infrastructure-style.md)                                                         |
| Training workflows      | [Deployment Validation](deployment-validation.md) (Level 4)                                             |
| Security-sensitive code | [Security Review](security-review.md)                                                                   |
| Any PR                  | [Cost Considerations](cost-considerations.md) for testing budget                                        |

## Related Documentation

- [Main CONTRIBUTING.md](../../.github/CONTRIBUTING.md) - Prerequisites, workflow, commit messages
- [Code of Conduct](../../CODE_OF_CONDUCT.md)
- [Security Policy](../../SECURITY.md)
