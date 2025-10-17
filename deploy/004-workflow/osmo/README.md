# OSMO Inline Training Workflow

This directory hosts assets for submitting Isaac Lab training to NVIDIA OSMO using inline payloads.

- `templates/` contains reusable workflow YAML, including `isaaclab-inline.yaml` for embedded archives.
- `.tmp/` stores generated ZIP and base64 payloads created during submissions and remains untracked.
- `submit-training.sh` packages `src/training/`, encodes it, and submits the inline workflow through the OSMO CLI.
- `example-submit.sh` demonstrates common argument patterns for workflow submission.

## Prerequisites

- `osmo` CLI authenticated against the target environment
- GNU `zip`, `base64`, and `unzip` utilities available locally and within the task image
- Isaac Lab training sources present under `src/training/`

## Quick Start

1. Copy and customize `example-submit.sh` with your Azure credentials:
   - Replace `azure_client_id`, `azure_tenant_id`, `azure_subscription_id` with service principal values
   - Update `azure_resource_group` and `azure_workspace_name` to match your Azure ML workspace
2. Adjust training parameters such as `--task`, `--max-iterations`, or `--image` as needed.
3. Execute the script to submit the workflow: `./example-submit.sh`

## submit-training.sh Arguments

### Core Training Options

- `-t, --task NAME` — Isaac Lab task name (default: `Isaac-Velocity-Rough-Anymal-C-v0`)
- `-n, --num-envs COUNT` — Number of parallel environments (default: `2048`)
- `-m, --max-iterations N` — Maximum training iterations; omit to use task default
- `-i, --image IMAGE` — Container image for training (default: `nvcr.io/nvidia/isaac-lab:2.2.0`)

### Checkpoint Management

- `-c, --checkpoint-uri URI` — MLflow artifact URI to resume or warm-start training from
- `-M, --checkpoint-mode MODE` — Checkpoint behavior: `from-scratch`, `warm-start`, `resume`, or `fresh`
- `-r, --register-checkpoint NAME` — Azure ML model name to register the final checkpoint under

### Azure Integration

- `-s, --run-smoke-test` — Enable Azure connectivity validation before training starts
- Additional Azure parameters (client ID, tenant ID, subscription ID, resource group, workspace name) are passed after `--` as `key=value` pairs

### Advanced Options

- `-w, --workflow PATH` — Path to workflow template YAML (default: `templates/isaaclab-inline.yaml`)
- `-p, --payload-root DIR` — Runtime extraction root (default: `/workspace/isaac_payload`)
- `--sleep-after-unpack VALUE` — Pause duration in seconds after payload extraction for debugging (e.g., `7200` for 2 hours)
- `-h, --help` — Display usage information

### OSMO CLI Forwarding

Arguments after `--` are forwarded to `osmo workflow submit`. Common examples:

- Azure configuration as `key=value` pairs for workflow parameter substitution
- `--dry-run` — Output resolved workflow YAML without submitting to OSMO (must follow all `key=value` pairs)

**Note:** `--dry-run` must appear after all `key=value` arguments in the command line.

## Example Workflows

### Basic Training Submission

```bash
./submit-training.sh \
  --task Isaac-Velocity-Rough-Anymal-C-v0 \
  --max-iterations 600 \
  -- \
  azure_client_id=<YOUR_CLIENT_ID> \
  azure_tenant_id=<YOUR_TENANT_ID> \
  azure_subscription_id=<YOUR_SUBSCRIPTION_ID> \
  azure_resource_group=rg-example \
  azure_workspace_name=mlw-example
```

### Resume Training from Checkpoint

```bash
./submit-training.sh \
  --checkpoint-uri "runs:/<run-id>/checkpoints/final" \
  --checkpoint-mode resume \
  --max-iterations 1200 \
  -- \
  azure_client_id=<YOUR_CLIENT_ID> \
  azure_tenant_id=<YOUR_TENANT_ID> \
  azure_subscription_id=<YOUR_SUBSCRIPTION_ID> \
  azure_resource_group=rg-example \
  azure_workspace_name=mlw-example
```

### Debugging Workflow Configuration

```bash
./submit-training.sh \
  --run-smoke-test \
  -- \
  azure_client_id=<YOUR_CLIENT_ID> \
  azure_tenant_id=<YOUR_TENANT_ID> \
  azure_subscription_id=<YOUR_SUBSCRIPTION_ID> \
  azure_resource_group=rg-example \
  azure_workspace_name=mlw-example
```

### Pausing Workflow for Container Inspection

```bash
./submit-training.sh \
  --sleep-after-unpack 7200 \
  -- \
  azure_client_id=<YOUR_CLIENT_ID> \
  azure_tenant_id=<YOUR_TENANT_ID> \
  azure_subscription_id=<YOUR_SUBSCRIPTION_ID> \
  azure_resource_group=rg-example \
  azure_workspace_name=mlw-example
```

### Validating Workflow Without Submission

```bash
./submit-training.sh \
  --task Isaac-Velocity-Rough-Anymal-C-v0 \
  -- \
  azure_client_id=<YOUR_CLIENT_ID> \
  azure_tenant_id=<YOUR_TENANT_ID> \
  azure_subscription_id=<YOUR_SUBSCRIPTION_ID> \
  azure_resource_group=rg-example \
  azure_workspace_name=mlw-example \
  --dry-run
```

## Troubleshooting

- Inspect `.tmp/osmo-training.zip` and `.tmp/osmo-training.b64` to verify payload packaging.
- Use `--dry-run` after `--` to validate workflow parameters without submission.
- Enable `--run-smoke-test` to confirm Azure ML connectivity before training starts.
- Add `--sleep-after-unpack` with a duration in seconds to pause execution after payload extraction for container inspection.
