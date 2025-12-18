# Automation

Azure Automation account for scheduled infrastructure operations.

## 🎯 Purpose

Runs scheduled PowerShell runbooks to manage infrastructure resources, such as starting PostgreSQL and AKS at the beginning of business hours to reduce costs.

## 📋 Prerequisites

- Platform infrastructure deployed (`cd .. && terraform apply`)
- Core variables matching parent deployment

## 🚀 Usage

```bash
cd deploy/001-iac/automation

# Configure schedule and resources
# Edit terraform.tfvars with your schedule

terraform init && terraform apply
```

## ⚙️ Configuration

Example `terraform.tfvars`:

```hcl
environment     = "dev"
location        = "westus3"
resource_prefix = "rob"
instance        = "001"

should_start_postgresql = true

schedule_config = {
  start_time = "13:00"
  week_days  = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
  timezone   = "UTC"
}
```

## 📦 Resources Created

- Azure Automation Account with system-assigned managed identity
- PowerShell 7.2 runbook for starting resources
- Weekly schedule with configurable days and start time
- Role assignments for AKS and PostgreSQL management

## 🔗 Related

- [Parent README](../README.md) - Main infrastructure documentation
