#!/usr/bin/env bash
set -euo pipefail

#######################################
# GPU Metrics Validation Script
#
# Validates GPU Operator and DCGM metrics are available.
#
# Usage:
#   ./validate-gpu-metrics.sh
#######################################

echo "Validating GPU Metrics..."
echo ""

# ============================================================
# GPU Operator Status
# ============================================================

echo "=== GPU Operator Status ==="
if kubectl get namespace gpu-operator &>/dev/null; then
  kubectl get pods -n gpu-operator -o wide
else
  echo "(gpu-operator namespace not found)"
fi
echo ""

# ============================================================
# DCGM Exporter
# ============================================================

echo "=== DCGM Exporter Pods ==="
if kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter &>/dev/null 2>&1; then
  kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter
else
  echo "(No DCGM Exporter pods found)"
fi
echo ""

# ============================================================
# GPU Metrics Check
# ============================================================

echo "=== Checking GPU Metrics ==="
dcgm_pod=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -n "${dcgm_pod}" ]]; then
  echo "Found DCGM exporter pod: ${dcgm_pod}"
  echo ""
  echo "Sample metrics:"
  if kubectl exec -n gpu-operator "${dcgm_pod}" -- curl -s localhost:9400/metrics 2>/dev/null | head -20; then
    echo ""
    echo "(Metrics available)"
  else
    echo "(Could not retrieve metrics - GPU nodes may not be ready)"
  fi
else
  echo "No DCGM exporter pod found."
  echo "This may indicate:"
  echo "  - GPU nodes are not running"
  echo "  - GPU Operator is still initializing"
  echo "  - GPU Operator is not installed"
fi
echo ""

# ============================================================
# KAI Scheduler Status
# ============================================================

echo "=== KAI Scheduler Status ==="
if kubectl get namespace kai-scheduler &>/dev/null; then
  kubectl get pods -n kai-scheduler -o wide
else
  echo "(kai-scheduler namespace not found - KAI Scheduler may not be installed)"
fi
echo ""

# ============================================================
# GPU Nodes
# ============================================================

echo "=== GPU Nodes ==="
kubectl get nodes -l accelerator=nvidia -o wide 2>/dev/null || \
  kubectl get nodes -l nvidia.com/gpu.present=true -o wide 2>/dev/null || \
  echo "(No GPU-labeled nodes found)"
echo ""

# ============================================================
# Summary
# ============================================================

echo "=== Validation Summary ==="

gpu_operator_ready=false
kai_scheduler_ready=false
dcgm_ready=false

if kubectl get pods -n gpu-operator -l app.kubernetes.io/name=gpu-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
  gpu_operator_ready=true
fi

if kubectl get pods -n kai-scheduler -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
  kai_scheduler_ready=true
fi

if [[ -n "${dcgm_pod}" ]]; then
  dcgm_ready=true
fi

echo "GPU Operator:   $(${gpu_operator_ready} && echo '✓ Running' || echo '✗ Not Ready')"
echo "KAI Scheduler:  $(${kai_scheduler_ready} && echo '✓ Running' || echo '✗ Not Ready')"
echo "DCGM Exporter:  $(${dcgm_ready} && echo '✓ Found' || echo '✗ Not Found')"
echo ""
echo "Validation complete."
