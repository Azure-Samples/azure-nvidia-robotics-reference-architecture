# OSMO Control Plane Deployment

This directory contains the automation used to roll out the NVIDIA OSMO control plane onto the Azure Kubernetes Service (AKS) environment provisioned by the Terraform templates under `deploy/001-iac`.

## Prerequisites

- Terraform apply has completed successfully and `terraform.tfstate` is present in `deploy/001-iac` (or the path supplied by `--terraform-dir`).
- You are authenticated with Azure CLI (`az login`) and have the required permissions on the resource group that hosts the AKS cluster, Redis Enterprise, PostgreSQL, and Key Vault resources.
- Required tooling is available in your shell: `terraform`, `az`, `kubectl`, `helm`, `jq`, and `base64`.
- An active NVIDIA NGC API token with access to `nvcr.io/nvidia/osmo` images.

## Run the deployment script

Run the script from this directory and provide the NGC token:

```bash
./deploy-osmo-control-plane.sh --ngc-token <YOUR_NGC_TOKEN>
```

Optional flags:

- `--terraform-dir <path>`: Override the Terraform state directory (defaults to `../../001-iac`).
- `--values-dir <path>`: Point to alternative Helm values files (defaults to `./values`).
- `--namespace <name>`: Deploy into a non-default namespace (defaults to `osmo-control-plane`).
- `--config-preview`: Print the derived configuration and exit without applying changes.

### What the script deploys

- Retrieves AKS credentials and ensures the target namespace exists.
- Adds the NVIDIA OSMO Helm repository using the provided NGC token.
- Creates Kubernetes secrets:
  - `nvcr-secret` for pulling container images from `nvcr.io`.
  - `db-secret` containing the PostgreSQL administrator password fetched from Azure Key Vault.
  - `redis-secret` containing the Redis Enterprise database key.
- Applies `internal-lb-ingress.yaml` to provision the private load balancer ingress (if the manifest is present).
- Installs/updates the Helm releases `service`, `router`, and `ui` (chart version `1.0.0`, image tag `6.0.0`) using the values files under `values/`.
- Prints post-deployment verification commands and a summary of the deployed resources.

## Install the OSMO CLI

1. Navigate to the latest release on GitHub: <https://github.com/NVIDIA/osmo/releases>.
2. Download the installer artifact that matches your platform.
3. Install the package:
   - **macOS (Apple Silicon):**

     ```bash
     sudo installer -pkg osmo-client-installer-${release_version}-macos-arm64.pkg -target /
     ```

   - **Linux (x86_64 or arm64):**

     ```bash
     chmod +x osmo-client-installer-${release_version}-linux-${arch}.sh
     ./osmo-client-installer-${release_version}-linux-${arch}.sh
     ```

4. Validate the installation with `osmo --version`.

## Configure the OSMO CLI (work in progress)

After the control plane is online, authenticate the CLI against the ingress endpoint. For private deployments that skip external authentication but run behind an Azure virtual network, use the internal load balancer IP exposed by the ingress manifest:

```bash
osmo login http://10.0.5.7/ --method dev --username guest
```

Replace `10.0.5.7` with the Azure load balancer IP allocated to your deployment. Additional configuration guidance (projects, datasets, workflows, etc.) is being documented and will be added here as the integration matures.
