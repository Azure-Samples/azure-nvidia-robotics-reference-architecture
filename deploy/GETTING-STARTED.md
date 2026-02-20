# Getting Started: Deploy OSMO on Azure

This guide walks through a first deployment using the **Hybrid** network (no VPN) and **Workload Identity** for OSMO (Scenario 2). Total time is roughly **1–1.5 hours** (mostly Terraform apply and cluster setup).

---

## Before you start

**Tools (install if needed):**

| Tool | Version | Check |
|------|--------|--------|
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | v2.50+ | `az version` |
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.9+ | `terraform version` |
| kubectl | recent | `kubectl version --client` |
| Helm | 3.x | `helm version` |
| jq | any | `jq --version` |
| [NVIDIA OSMO CLI](https://developer.nvidia.com/osmo) | latest | `osmo --version` (required before deploying the backend) |

**Azure:**

- A subscription where you have **Contributor** and **Role Based Access Control Administrator** (or **Owner**).
- GPU quota in your chosen region for the default GPU size (`Standard_NV36ads_A10_v5`). Check in Azure Portal: **Subscriptions → Your subscription → Usage + quotas**, search for the VM family or “NVads”.

**Optional for later (training workflows):** Docker with NVIDIA Container Toolkit, Python/uv (see root [README](../README.md)).

---

## Step 1: Prerequisites (about 2 minutes)

From the repo root:

```bash
cd deploy
source 000-prerequisites/az-sub-init.sh
```

Log in if prompted. This sets `ARM_SUBSCRIPTION_ID` in your shell.

If this subscription has never had AKS, Azure ML, or similar resources, register providers once:

```bash
./000-prerequisites/register-azure-providers.sh
```

---

## Step 2: Configure and deploy infrastructure (about 30–40 minutes)

```bash
cd 001-iac
cp terraform.tfvars.example terraform.tfvars
```

Edit **`terraform.tfvars`** and set at least:

- **`resource_prefix`** – short name for your resources (e.g. `myosmo`).
- **`location`** – Azure region (e.g. `westus3`). Use a region where you have GPU quota.
- **`environment`** – e.g. `dev`.

The example file is already set for:

- **Hybrid network** – private Azure services, public AKS API (no VPN).
- **OSMO Scenario 2** – Workload Identity; no `--use-access-keys` or `--use-acr` later.

Optional: adjust GPU node pool (e.g. `node_pools.gpu.vm_size`, `min_count`/`max_count`) or leave defaults.

Deploy:

```bash
terraform init
terraform apply -var-file=terraform.tfvars
```

Type `yes` when prompted. Wait for the run to finish (~30–40 min). You can leave VPN **undeployed**; with Hybrid you don’t need it.

---

## Step 3: Connect to the cluster and run cluster setup (about 30 minutes)

From the repo root (or from `deploy/`):

```bash
cd deploy/002-setup
```

Get AKS credentials. Replace `<rg>` and `<aks>` with your resource group and cluster name (from Terraform output or Azure Portal), or use:

```bash
tf_dir="../001-iac"
rg=$(cd "$tf_dir" && terraform output -raw resource_group | jq -r '.name')
aks=$(cd "$tf_dir" && terraform output -raw aks_cluster | jq -r '.name')
az aks get-credentials --resource-group "$rg" --name "$aks" --overwrite-existing
kubectl cluster-info
```

If `kubectl cluster-info` works, run the first three setup scripts in order (no VPN, no `--use-access-keys`, no `--use-acr`):

```bash
./01-deploy-robotics-charts.sh
./02-deploy-azureml-extension.sh
./03-deploy-osmo-control-plane.sh
```

The control plane script auto-detects the service URL and sets the control plane’s `service_base_url` (used by workflow pods). If the internal LB or osmo-service is not ready yet, detection can be empty; you can pass an explicit URL: `./03-deploy-osmo-control-plane.sh --service-url "http://<LB_IP>"` or use the in-cluster URL. See [deployment-issues-and-fixes.md](../docs/deployment-issues-and-fixes.md#35-workflow-pod-loggerctrl-unsupported-protocol-scheme-or-url-80) if workflow pods show `//:80`.

**Before running the backend script:** The backend operator needs a **service token** from the OSMO control plane. The script creates that token using the OSMO CLI, so you must be **logged in to OSMO** first. In a **separate terminal**, start a port-forward to the OSMO service, then log in:

```bash
# Terminal A: keep this running
kubectl port-forward svc/osmo-service 9000:80 -n osmo-control-plane
```

```bash
# Terminal B: log in to OSMO (complete the browser/devicelogin if prompted)
osmo login http://localhost:9000 --method=dev --username=testuser
```

Then run the backend script. The script uses the OSMO CLI to create a service token, so run it from a shell where you have already run `osmo login` (or from the same terminal as Terminal B above; the CLI stores login state for your user).

```bash
./04-deploy-osmo-backend.sh
```

The script auto-detects the OSMO service URL (preferring the **LoadBalancer** so backend auth works). When configuring dataset buckets, it uses a storage account key when available (even with workload identity) so workflow uploads to datasets work from a fresh deploy; if the storage account has shared access keys disabled, run `./configure-dataset-credential.sh` later once keys are enabled, or see [deployment-issues-and-fixes.md](../docs/deployment-issues-and-fixes.md#310-workflow-upload-credential-not-set-for-azure). After changing the service URL or regenerating the token, restart OSMO backend pods so they renegotiate auth: `kubectl rollout restart deployment -n osmo-operator osmo-operator-osmo-backend-worker osmo-operator-osmo-backend-listener`. If workflows show `//:80` or "unsupported protocol scheme", see [deployment-issues-and-fixes.md](../docs/deployment-issues-and-fixes.md#35-workflow-pod-loggerctrl-unsupported-protocol-scheme-or-url-80).

If you need to regenerate the token later (e.g. after it expires or the backend pods report "Access Token is invalid"), run `osmo login http://localhost:9000 --method=dev --username=testuser` again, then `./04-deploy-osmo-backend.sh --regenerate-token`.

**Change SERVICE URL:** From `002-setup`, with port-forward and `osmo login` active, run `./update-service-url.sh` (LB) or `./update-service-url.sh http://<LB_IP>`. Then restart the backend. If workflow pods go **NotReady** and terminate with the LB URL, switch back to in-cluster so they complete: `./update-service-url.sh http://osmo-service.osmo-control-plane.svc.cluster.local` and restart the backend; use `kubectl logs <pod> -n osmo-workflows -c <task-container>` for task output. See [deployment-issues-and-fixes.md](../docs/deployment-issues-and-fixes.md#39-workflow-pod-logger-websocket-bad-handshake-403-with-in-cluster-url).

Scripts read Terraform outputs from `../001-iac` by default. If your Terraform is elsewhere, use `-t /path/to/001-iac`.

---

## Step 4: Verify and use OSMO

Check that OSMO pods are running:

```bash
kubectl get pods -n osmo-control-plane
kubectl get pods -n osmo-operator
```

With **Hybrid**, the AKS API is public but the Load Balancer for OSMO may still be internal. To use the OSMO UI or API from your machine you can use port-forward:

```bash
# Terminal 1 – API (for OSMO CLI)
kubectl port-forward svc/osmo-service 9000:80 -n osmo-control-plane

# Terminal 2 – UI
kubectl port-forward svc/osmo-ui 3000:80 -n osmo-control-plane
```

Then:

- **UI:** open `http://localhost:3000`
- **CLI:** `osmo login http://localhost:9000 --method=dev --username=testuser` (install [OSMO CLI](https://developer.nvidia.com/osmo) if needed), then `osmo info` and `osmo backend list`
- **Hello-world workflow:** from the repo root run `osmo workflow submit workflows/osmo/hello-world.yaml`, then use the returned workflow ID (e.g. `hello-world-1`) with `osmo workflow query <id>` and `osmo workflow logs <id>`. See [workflows/osmo/README.md](../workflows/osmo/README.md#-hello-world-smoke-test).

**Troubleshooting:** If workflows stay RUNNING, backend pods crash with "Access Token is invalid", or you see other deploy issues, see [deployment-issues-and-fixes.md](../docs/deployment-issues-and-fixes.md) (token, workflow config, service URL for workflow pods, etc.).

See [002-setup/README.md](002-setup/README.md) for more access options and cleanup.

---

## Summary

| Step | Where | What |
|------|--------|------|
| 1 | `000-prerequisites` | Azure login, set subscription, register providers |
| 2 | `001-iac` | Copy tfvars, edit prefix/location/env, `terraform init && apply` |
| 3 | `002-setup` | `az aks get-credentials`, run 01–03 scripts, then **osmo login** (with port-forward), then 04 script |
| 4 | - | Check pods, port-forward to OSMO UI/API if needed |

**No VPN** is required with the Hybrid settings in `terraform.tfvars.example`. For a fully private cluster (VPN required), set `should_enable_private_aks_cluster = true` and follow [001-iac/vpn/README.md](001-iac/vpn/README.md) after Step 2.
