---
title: Pull Request Process
description: PR workflow, reviewer assignment, review cycles, approval criteria, and update process
author: Microsoft Robotics-AI Team
ms.date: 2026-02-08
ms.topic: how-to
keywords:
  - pull request
  - code review
  - approval
  - contributing
---

> [!NOTE]
> This guide expands on the [Pull Request Process](README.md#-pull-request-process) section of the main contributing guide.

This reference architecture uses a deployment-based validation model rather than automated testing. The PR workflow adapts to different contribution types and validation levels.

## PR Workflow Steps

1. Fork and Branch: Create a feature branch from your fork's main branch
2. Make Changes: Implement improvements following style guides
3. Validate Locally: Run appropriate validation level (static/plan/deployment)
4. Create Draft PR: Open draft PR with validation documentation
5. Request Review: Mark PR ready when validation complete

## Review Process

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

## Update Process

This reference architecture uses a rolling update model rather than semantic versioning. Users fork and adapt the blueprint for their own use.

### Update Types

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

### Component Updates

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

### Staying Updated

* Watch repository for releases
* Review release notes before pulling updates
* Test updates in dev environment before production
* Maintain customizations in separate branch/overlay

## Related Documentation

* [Contributing Guide](README.md) - Main contributing guide with all sections
* [Contribution Workflow](contribution-workflow.md) - Legal, bug reports, enhancements, first contributions
* [Deployment Validation](deployment-validation.md) - Validation levels and testing templates
