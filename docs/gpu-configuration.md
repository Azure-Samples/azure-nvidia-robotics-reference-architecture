---
title: GPU Configuration Guide
description: GPU driver architecture, MIG strategy, and runtime behavior for mixed GPU node pools in Azure AKS
author: Microsoft Robotics-AI Team
ms.date: 2026-02-23
ms.topic: concept
---

GPU driver management, MIG configuration, and runtime behavior for the mixed GPU node pools used in this reference architecture.

## GPU Node Pool Architecture

This cluster uses two GPU node pool types with different driver and runtime profiles.

| Property | H100 (`h100gpu`) | RTX PRO 6000 (`rtxprogpu`) |
| --- | --- | --- |
| Azure VM SKU | `Standard_NC40ads_H100_v5` | `Standard_NC128ds_xl_RTXPRO6000BSE_v6` |
| GPU passthrough | PCIe passthrough | SR-IOV vGPU (PCI ID `10de:2bb5`) |
| Driver source | GPU Operator datacenter driver | Custom GRID DaemonSet (`gpu-grid-driver-installer`) |
| Driver branch | Standard datacenter | Microsoft GRID `580.105.08-grid-azure` |
| MIG at hardware level | Disabled | Enabled by vGPU host |
| Vulkan device creation | Supported | Fails (`ERROR_INITIALIZATION_FAILED`) |
| Kernel module type | Open (default) | Proprietary (required for vGPU) |

## GPU Driver Management

### H100 Nodes

The GPU Operator manages the full driver lifecycle for H100 nodes using its built-in driver container (`driver.enabled: true`). No additional configuration is required.

### RTX PRO 6000 Nodes

RTX PRO 6000 BSE nodes use Azure SR-IOV vGPU passthrough, which requires the Microsoft GRID driver instead of the NVIDIA datacenter driver. AKS does not support `gpu_driver = "Install"` for this VM SKU.

The `gpu-grid-driver-installer` DaemonSet ([manifests/gpu-grid-driver-installer.yaml](../deploy/002-setup/manifests/gpu-grid-driver-installer.yaml)) installs the GRID driver on each RTX node. Terraform labels these nodes with `nvidia.com/gpu.deploy.driver=false`, causing the GPU Operator to skip its driver DaemonSet on those nodes while still managing toolkit, device-plugin, and validator components.

The GRID driver is installed via an init container that uses `nsenter` into the host namespace to download and compile the driver. New nodes added by the autoscaler receive the driver automatically through the DaemonSet.

> [!NOTE]
> The GPU Operator supports [custom vGPU driver containers](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/install-gpu-operator-vgpu.html),
> but this requires building a private container image, a private registry, and NVIDIA vGPU licensing infrastructure.
> The DaemonSet approach is functionally equivalent without that overhead.

## MIG Strategy

The GPU Operator `mig.strategy` setting controls how GPUs are exposed to workload containers.

### Why `single` Is Required

The Azure vGPU host enables MIG mode on RTX PRO 6000 GPUs. When MIG is enabled at the hardware level, CUDA can only access the GPU through MIG device UUIDs, not bare GPU UUIDs.

| Strategy | Device-plugin sets `NVIDIA_VISIBLE_DEVICES` to | CUDA result |
| --- | --- | --- |
| `single` | `MIG-<uuid>` (MIG device UUID) | Works |
| `none` | `GPU-<uuid>` (bare GPU UUID) | Fails: `cuInit` returns `CUDA_ERROR_NO_DEVICE` |

With `strategy: none`, `nvidia-smi` works (it uses NVML, which is MIG-agnostic) but PyTorch/CUDA applications cannot initialize the GPU.

### Guest VM MIG Limitations

The guest VM cannot create, destroy, or reconfigure MIG instances:

```text
nvidia-smi -i 0 -mig 0 → Unable to disable MIG Mode: Insufficient Permissions
nvidia-smi mig -lgi    → Insufficient Permissions
```

The vGPU host manages MIG instances, so `migManager.enabled` is set to `false` in the GPU Operator values.

### H100 Compatibility

H100 nodes do not have MIG enabled at hardware level. Setting `mig.strategy: single` on a non-MIG GPU is a no-op — the device-plugin falls back to standard GPU UUID allocation. H100 workloads are unaffected.

## Vulkan Limitation on RTX PRO 6000

Vulkan device creation fails on the RTX PRO 6000 vGPU MIG profile:

```text
VkResult: ERROR_INITIALIZATION_FAILED
vkCreateDevice failed
gpu.foundation.plugin: No device could be created
```

This occurs despite `vulkaninfo` succeeding and ray-tracing extensions being present. The failure is in Isaac Sim's GPU foundation plugin, which requires full Vulkan device creation capabilities not available on this vGPU profile.

**Impact on training**: Headless CUDA compute training works. PhysX simulation runs on CUDA. Vulkan is only needed for rendering, which is disabled in headless mode. The errors are logged but non-blocking.

**Impact on shutdown**: Isaac Sim's `SimulationApp.close()` may log Vulkan errors during shutdown. With the MIG strategy fix in place, the close completes cleanly. The training script suppresses expected shutdown exceptions.

## Related Resources

* [NVIDIA GPU Operator with Azure AKS](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/microsoft-aks.html)
* [NVIDIA GPU Operator vGPU support](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/install-gpu-operator-vgpu.html)
* [GPU Operator Helm values](../deploy/002-setup/values/nvidia-gpu-operator.yaml)
* [GRID driver installer DaemonSet](../deploy/002-setup/manifests/gpu-grid-driver-installer.yaml)
