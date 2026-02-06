---
title: OpenSSF Dynamic Analysis Scope
description: N/A justifications for OpenSSF Silver dynamic analysis requirements with IaC validation equivalents.
author: Edge AI Team
ms.date: 2026-02-05
ms.topic: reference
---

This scope documents OpenSSF Silver dynamic analysis requirements that are not applicable to this repository and lists IaC equivalents used for validation. It records evidence that the codebase does not contain compiled or low-level sources and provides Terraform validation as the assertion equivalent.

## OpenSSF Dynamic Analysis Requirements

### dynamic_analysis

| Field                   | Value                                                                                                                                                                     |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status                  | N/A                                                                                                                                                                       |
| Justification           | The repository contains infrastructure-as-code, shell scripts, Python utilities, and workflow YAML, with no runnable binaries to exercise in a dynamic analysis pipeline. |
| IaC equivalent evidence | Terraform plan reviews, Terraform validate, and policy-as-code evaluations provide the required behavioral validation for infrastructure changes.                         |

### dynamic_analysis_unsafe

| Field                   | Value                                                                                                                  |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Status                  | N/A                                                                                                                    |
| Justification           | The codebase does not include compiled or low-level components that could introduce memory-unsafe runtime behavior.    |
| IaC equivalent evidence | Terraform plan output and policy-as-code checks validate unsafe configuration changes before deployment.               |

### dynamic_analysis_enable_assertions

| Field                   | Value                                                                                                                      |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Status                  | N/A                                                                                                                        |
| Justification           | There are no compiled binaries with runtime assertions or build flags to enable.                                           |
| IaC equivalent evidence | Terraform validation blocks and policy-as-code checks provide the assertion equivalent for infrastructure configuration.   |

### dynamic_analysis_fixed

| Field                   | Value                                                                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Status                  | N/A                                                                                                                              |
| Justification           | The repository does not ship compiled artifacts or services where dynamic analysis findings would require runtime fixes.         |
| IaC equivalent evidence | Terraform plan review and validate checks gate configuration changes before apply.                                               |

## Memory Safety Scope

| Field         | Value                                                                                                                                                                                    |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status        | N/A                                                                                                                                                                                      |
| Justification | The repository contains no compiled or low-level code such as C, C++, Rust, Go, or Assembly. Memory safety concerns are out of scope for declarative IaC and scripts in this repository. |

## Infrastructure-as-Code Validation Evidence

| IaC validation     | Purpose                                                             |
| ------------------ | ------------------------------------------------------------------- |
| Terraform plan     | Review proposed infrastructure changes before apply.                |
| Terraform validate | Verify configuration syntax and internal consistency.               |
| Policy-as-code     | Enforce security and compliance controls through policy evaluation. |

## Repository Language Evidence

| Evidence item              | Details                                                                       |
| -------------------------- | ----------------------------------------------------------------------------- |
| IaC definitions            | Terraform modules and configuration under deploy/ and workflows/ directories. |
| Automation scripts         | Shell scripts and PowerShell tooling for deployment and cleanup.              |
| Application utilities      | Python and YAML for training, workflow, and automation orchestration.         |
| Compiled or low-level code | None present in the repository.                                               |

## Assertion Equivalent Example (Terraform validation)

```hcl
variable "region" {
  type        = string
  description = "Azure region for deployment"

  validation {
    condition     = contains(["eastus", "westus2", "westeurope"], var.region)
    error_message = "Region must be one of: eastus, westus2, westeurope."
  }
}
```
