# Omniverse Kit App Streaming Deployment

Deploy NVIDIA Omniverse Kit Application Streaming on Azure Kubernetes Service (AKS) with GPU-optimized ApplicationProfiles.

## Prerequisites

* AKS cluster with GPU node pools configured
* kubectl >= 1.29 with cluster context configured
* helm >= 3.8
* az CLI with ACR access
* NGC API token from NVIDIA
* bash >= 5.x

## Deployment Workflow

### Step 1: Bootstrap Namespace and Secrets

Create the target namespace and configure registry pull secrets:

```bash
cd deploy/002-setup/scripts

./aks-bootstrap.sh \
  --acr-name <your-acr-name> \
  --ngc-token $NGC_API_TOKEN \
  --namespace omni-streaming
```

Verify secrets created:

```bash
kubectl -n omni-streaming get secret regcred ngc-omni-user
```

### Step 2: Mirror Omniverse Charts to ACR

Mirror NVIDIA Omniverse Helm charts and container images to your Azure Container Registry:

```bash
./mirror-omniverse.sh \
  --acr-name <your-acr-name> \
  --app-version 1.11.0 \
  --ngc-token $NGC_API_TOKEN
```

This pulls charts for:

* kit-appstreaming-rmcp (Resource Management Control Plane)
* kit-appstreaming-manager (Session Manager)
* kit-appstreaming-session (GPU Streaming Pods)
* kit-appstreaming-applications (Application Catalog)

### Step 3: Deploy Core Omniverse Services

Deploy FluxCD, Memcached, and Omniverse core services:

```bash
./deploy-omniverse.sh \
  --acr-name <your-acr-name> \
  --app-version 1.11.0 \
  --namespace omni-streaming \
  --flux-namespace flux-operators
```

Verify deployments:

```bash
kubectl -n omni-streaming get pods
```

Expected pods:

* omni-memcached-* (shader cache)
* omni-rmcp-* (resource management)
* streaming-* (session manager)
* applications-* (application catalog)

### Step 4: Deploy USD Viewer Application

Deploy Application, ApplicationVersion, and ApplicationProfile CRDs:

```bash
./deploy-usd-viewer-app.sh \
  --acr-name <your-acr-name> \
  --app-version 1.11.0 \
  --profile-type partialgpu
```

For full GPU nodes instead:

```bash
./deploy-usd-viewer-app.sh \
  --acr-name <your-acr-name> \
  --app-version 1.11.0 \
  --profile-type fullgpu
```

Verify CRDs created:

```bash
kubectl -n omni-streaming get application,applicationversion,applicationprofile
```

### Step 5: Test Streaming Session

Port-forward streaming service to local workstation:

```bash
./test-streaming-session.sh \
  --namespace omni-streaming \
  --service-name <streaming-service-name>
```

Follow the printed instructions to:

1. Clone NVIDIA web-viewer-sample repository
2. Configure `stream.config.json`
3. Run Web Viewer locally
4. Connect via browser to `http://localhost:5173/`

## ApplicationProfile Variants

### partialgpu Profile

**Target**: AKS node pools with `partialgpu=true` taint (MIG or vGPU)

**Tolerations**:

* `nvidia.com/gpu:NoSchedule` (Exists)
* `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`
* `partialgpu=true:NoSchedule`

**NodeSelector**: `agentpool=partialgpu`

**Resources**:

* GPU: 1 (may represent MIG slice)
* CPU: 4000m request, 8000m limit
* Memory: 8Gi request, 16Gi limit

### fullgpu Profile

**Target**: Standard GPU nodes without partitioning

**Tolerations**:

* `nvidia.com/gpu:NoSchedule` (Exists)
* `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`

**NodeSelector**: `accelerator=nvidia-tesla-a100` (optional, customize for your GPU SKU)

**Resources**:

* GPU: 1 (full GPU)
* CPU: 8000m request, 16000m limit
* Memory: 16Gi request, 32Gi limit

## Script Options

### deploy-usd-viewer-app.sh

```
Required:
  --acr-name NAME          ACR name (no .azurecr.io suffix)
  --app-version VERSION    Omniverse chart version (e.g., 1.11.0)

Optional:
  --namespace NS           Target namespace (default: omni-streaming)
  --profile-type TYPE      partialgpu or fullgpu (default: partialgpu)
  --dry-run                Print manifests without applying
  --verbose                Verbose logging
  --skip-verify            Skip CRD verification after apply
```

### test-streaming-session.sh

```
Optional:
  --namespace NS               Namespace (default: omni-streaming)
  --service-name NAME          Service to port-forward (auto-detected)
  --local-signaling-port PORT  Local TCP port (default: 30100)
  --local-media-port PORT      Local UDP port (default: 30101)
  --session-id ID              Session ID for cleanup on exit
  --dry-run                    Print commands without executing
  --verbose                    Verbose logging
```

## Troubleshooting

### Pods Not Scheduling to GPU Nodes

**Symptom**: Session pods stuck in Pending state with event "0/N nodes available: untolerated taint"

**Solutions**:

1. Verify GPU node pool has correct taints:

   ```bash
   kubectl describe nodes -l agentpool=partialgpu | grep Taints
   ```

2. Confirm ApplicationProfile includes all required tolerations
3. Check nodeSelector matches node labels

### Port-Forward Connection Fails

**Symptom**: Web Viewer cannot connect to local ports

**Solutions**:

1. Verify port-forward process is running:

   ```bash
   ps aux | grep "kubectl port-forward"
   ```

2. Check firewall allows UDP traffic on media port (31001)
3. Ensure service exists and is ClusterIP type:

   ```bash
   kubectl -n omni-streaming get svc
   ```

### Shader Cache Warm-Up Delay

**Symptom**: Black screen in Web Viewer for 5-10 minutes on first launch

**Expected Behavior**: First session compiles shaders. Subsequent sessions use memcached cache.

**Mitigation**:

* Confirm memcached pod is running
* Check shader cache env var in ApplicationProfile:

  ```yaml
  env:
    - name: AUTO_ENABLE_DRIVER_SHADER_CACHE_WRAPPER
      value: "true"
  ```

### Session Manager API Errors

**Symptom**: Cannot create sessions via streaming manager API

**Solutions**:

1. Verify all Omniverse services are Running:

   ```bash
   kubectl -n omni-streaming get pods
   ```

2. Check streaming manager logs:

   ```bash
   kubectl -n omni-streaming logs -l app.kubernetes.io/name=streaming
   ```

3. Ensure RMCP can create FluxCD HelmReleases:

   ```bash
   kubectl -n omni-streaming get helmreleases
   ```

## Architecture

```
Control Plane (CPU Nodes)
├── FluxCD Operators (flux-operators namespace)
├── Memcached (shader cache)
├── RMCP (resource management)
├── Streaming Manager (session API)
└── Applications (catalog service)

Data Plane (GPU Nodes)
└── Streaming Session Pods (created dynamically)
    ├── USD Viewer container
    ├── WebRTC streaming
    └── Envoy sidecar (optional TLS)
```

## References

* [NVIDIA Omniverse Kit App Streaming Documentation](https://docs.omniverse.nvidia.com/ovas/latest/index.html)
* [Kit App Template - USD Viewer](https://github.com/NVIDIA-Omniverse/kit-app-template/tree/main/templates/apps/usd_viewer)
* [Web Viewer Sample](https://github.com/NVIDIA-Omniverse/web-viewer-sample)
* Research: `.copilot-tracking/research/20251022-omniverse-kit-streaming-research.md`
* Research: `.copilot-tracking/research/20251023-omniverse-aks-gpu-scheduling-research.md`
