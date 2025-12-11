# Prerequisites

Azure CLI initialization to set the subscription ID for Terraform deployments.

## Scripts

| Script | Purpose |
|--------|---------|
| `az-sub-init.sh` | Azure login and `ARM_SUBSCRIPTION_ID` export |

## Usage

Source the script to set `ARM_SUBSCRIPTION_ID` for Terraform:

```bash
source az-sub-init.sh
```

For a specific tenant:

```bash
source az-sub-init.sh --tenant your-tenant.onmicrosoft.com
```

## What It Does

1. Checks for existing Azure CLI session
2. Prompts for login if needed (optionally with tenant)
3. Exports `ARM_SUBSCRIPTION_ID` to current shell

The subscription ID is required by Terraform's Azure provider when not running in a managed identity context.

## Next Step

After initialization, proceed to [001-iac](../001-iac/) to deploy infrastructure.
