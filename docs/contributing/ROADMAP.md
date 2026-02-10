---
title: "Azure NVIDIA Robotics Reference Architecture Roadmap"
description: "12-month roadmap covering documentation, testing, CI/CD, governance, security, and OpenSSF compliance."
author: wberry
ms.date: 2026-02-10
ms.topic: reference
keywords:
  - roadmap
  - project planning
  - openssf
  - azure
  - nvidia
  - robotics
estimated_reading_time: 8
---

This 12-month roadmap covers planned work for the Azure NVIDIA Robotics Reference Architecture from Q1 2026 through Q1 2027.
Six priority areas align to milestones v0.2.0 through v0.7.0, progressing from documentation maturity through security hardening.
Each area lists concrete deliverables with linked issues and explicit items we will not pursue.

> [!NOTE]
> This roadmap represents current project intentions and is subject to change.
> It is not a commitment or guarantee of specific features or timelines.
> Community feedback and contributions influence priorities.
> See [How to Influence the Roadmap](#how-to-influence-the-roadmap) for ways to participate.

## Current State

The project reached v0.1.0 on 2026-02-07 with 30 commits on main and 24 merged pull requests.
Seven milestones are planned through v0.7.0, spanning foundation work through security hardening.
OpenSSF Best Practices Passing criteria are approximately 85% met (43 Met, 7 Partial, 12 Gap, 6 N/A).

## Priorities

### Documentation Maturity (v0.2.0, Q1 2026)

Complete the contributing guide suite and establish maintenance policies.
This milestone closes the remaining documentation gaps identified during the OpenSSF Passing assessment.

**Will Do:**

* Expand developer setup and prerequisites (#89)
* Define security expectations for contributors (#91)
* Publish a maintenance and upgrade policy (#92, #102)
* Commit to 48-hour achievement update cadence (#93)
* Add accessibility guidelines for documentation (#94)
* Standardize install and uninstall conventions (#95)

**Won't Do:**

* API reference documentation (this is a reference architecture, not a library)
* Automated documentation generation from source code

### Developer Tooling and Linting (v0.3.0, Q1-Q2 2026)

Standardize linting infrastructure across shell, Python, and markdown.
Shared modules reduce duplication and enforce consistent quality gates.

**Will Do:**

* Implement verified downloads with hash checking (#54)
* Create testing directory structure and runner (#55)
* Add YAML and GitHub Actions linting (#56)
* Implement frontmatter validation (#57)
* Enable dependency pinning and scanning (#58)
* Migrate shared linting modules from hve-core (#68, #69)
* Standardize `os.environ` usage patterns (#130)

**Won't Do:**

* Custom linting rule development beyond existing tools
* IDE-specific plugin creation

### Testing Infrastructure (v0.4.0, Q2 2026)

Stand up pytest and Pester test frameworks with coverage reporting and CI integration.
Baseline test suites validate training utilities and CI helper modules.

**Will Do:**

* Configure pytest with baseline test directory (#80)
* Add unit tests for training utilities (#82)
* Enable coverage reporting (#83)
* Create pytest CI workflow (#81)
* Configure Pester with shared test helpers (#63)
* Write Pester tests for CIHelpers, linting, security, and download modules (#64, #65, #66, #67)
* Establish regression test requirements for bug fixes (#107)

**Won't Do:**

* End-to-end deployment tests (cost-prohibitive in CI)
* GPU-dependent tests in CI pipelines

### CI/CD and Automation (v0.5.0, Q2 2026)

Expand CI pipelines with Python linting, security scanning, and workflow orchestration.
CodeQL and Bandit scanning catch vulnerabilities before merge.

**Will Do:**

* Configure Ruff linter with project rules (#85, #86)
* Resolve existing Ruff violations (#87)
* Add Bandit security scanning (#88)
* Enable CodeQL on pull request triggers (#84)
* Mirror PR validation across branches (#71)
* Orchestrate new CI jobs into existing workflows (#70)
* Port remaining workflows from hve-core (#20)

**Won't Do:**

* Deployment automation requiring Azure credentials in CI
* External registry or package releases

### Governance and Compliance (v0.6.0, Q2-Q3 2026)

Formalize project governance and complete OpenSSF Passing badge criteria.
N/A justifications document criteria that do not apply to this project.

**Will Do:**

* Publish a governance model (#98)
* Define contributor and maintainer roles (#99)
* Document access continuity procedures (#100)
* Address bus factor with succession planning (#101)
* Establish DCO or CLA requirements (#97)
* Add vulnerability credit policy (#103)
* Document reused software components (#104)
* Define deprecated interface conventions (#105)
* Enable strict compiler warnings equivalents (#106)
* File N/A justifications for build, install, crypto, site password, i18n, and dynamic analysis criteria (#113, #114, #115, #116, #117, #118)
* Register for OpenSSF Passing badge (#96)

**Won't Do:**

* External security audit engagements
* Paid compliance tooling subscriptions

### Security Hardening (v0.7.0, Q3 2026)

Implement release integrity, input validation, and threat modeling.
OpenSSF Scorecard integration provides continuous security measurement.

**Will Do:**

* Integrate OpenSSF Scorecard with automated reporting (#60)
* Establish weekly security maintenance cadence (#61)
* Detect and remediate SHA staleness (#59)
* Implement release signing and verification (#108, #109)
* Add input validation for scripts and CI parameters (#110)
* Publish hardening guidance for deployment (#111)
* Create an assurance case and threat model (#112)

**Won't Do:**

* Penetration testing engagements
* Hardware security module (HSM) integration

## Out of Scope

* Production SLA or uptime guarantees
* Multi-cloud support
* Custom robot hardware integration guides
* Paid support tiers or enterprise licensing
* Backward compatibility guarantees for infrastructure modules
* Automated deployment pipelines for end users

## Success Metrics

| Metric                       | Current | Q2 2026 Target | Q4 2026 Target |
|------------------------------|---------|----------------|----------------|
| OpenSSF Passing criteria met | ~85%    | 95%            | 100%           |
| OpenSSF Silver criteria met  | ~30%    | 50%            | 80%            |
| Test coverage (Python)       | 0%      | 60%            | 80%            |
| CI workflow count            | 4       | 8              | 10             |
| Contributing guide count     | 7       | 8              | 9              |
| Average PR review time       | N/A     | < 3 days       | < 2 days       |

## Timeline Overview

```text
Q1 2026 (Jan-Mar) — Foundation
├── Documentation: Complete v0.2.0 docs backlog (roadmap, security, maintenance policies)
├── Developer Tooling: Verified downloads, linting standardization, frontmatter validation
└── Release: v0.2.0, v0.3.0

Q2 2026 (Apr-Jun) — Quality
├── Testing: pytest + Pester infrastructure, coverage reporting, CI integration
├── CI/CD: Ruff, Bandit, CodeQL PR triggers, workflow orchestration
├── Governance: Governance model, roles, DCO/CLA, OpenSSF N/A documentation
└── Release: v0.4.0, v0.5.0, v0.6.0

Q3 2026 (Jul-Sep) — Security
├── Security: OpenSSF Scorecard, release signing, threat model, hardening guidance
├── Compliance: Register for OpenSSF Passing badge
└── Release: v0.7.0

Q4 2026 (Oct-Dec) — Maturity
├── OpenSSF: Complete Silver attestation
├── Platform: Azure and NVIDIA integration updates (OSMO workload identity)
└── Community: External contributor onboarding, maintainer documentation

Q1 2027 (Jan-Mar) — Growth
├── Architecture: Additional ML workflow patterns, multi-region considerations
├── Community: Conference presentations, partner integrations
└── Roadmap: Publish updated 2027-2028 roadmap
```

## How to Influence the Roadmap

* Open an issue describing the feature or improvement you need.
* Comment on existing issues to share use cases or signal priority.
* Join GitHub Discussions to propose broader changes.
* Submit a pull request referencing an open issue.
* Provide feedback on in-progress milestones through issue comments.

## Version History

| Date       | Version | Notes                    |
|------------|---------|--------------------------|
| 2026-02-10 | 1.0     | Initial 12-month roadmap |
