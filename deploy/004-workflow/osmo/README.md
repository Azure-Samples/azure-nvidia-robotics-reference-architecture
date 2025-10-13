# OSMO Inline Training Workflow

This directory hosts assets for submitting Isaac Lab training to NVIDIA OSMO using inline payloads.

- `templates/` contains reusable workflow YAML, including `isaaclab-inline.yaml` for embedded archives.
- `.tmp/` stores generated ZIP and base64 payloads created during submissions and remains untracked.
- `submit-training.sh` packages `src/training/`, encodes it, and submits the inline workflow through the OSMO CLI.

## Prerequisites

- `osmo` CLI authenticated against the target environment
- GNU `zip`, `base64`, and `unzip` utilities available locally and within the task image
- Isaac Lab training sources present under `src/training/`

## Usage

1. Update workflow defaults or overrides in `templates/isaaclab-inline.yaml` as needed.
2. Run `deploy/004-workflow/osmo/submit-training.sh` to package the training payload and submit the workflow.
3. Inspect `.tmp/` artifacts if troubleshooting encoded archives; delete them when finished.
