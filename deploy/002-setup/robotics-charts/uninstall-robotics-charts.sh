#!/usr/bin/env bash
set -euo pipefail

#######################################
# Robotics Charts Uninstall Script
#
# Removes NVIDIA GPU Operator and KAI Scheduler from AKS cluster.
#
# Usage:
#   ./uninstall-robotics-charts.sh
#######################################

echo "Uninstalling Robotics Charts..."

# ============================================================
# KAI Scheduler
# ============================================================

if helm status kai-scheduler -n kai-scheduler &>/dev/null; then
  echo "Uninstalling KAI Scheduler..."
  helm uninstall kai-scheduler -n kai-scheduler
  kubectl delete namespace kai-scheduler --ignore-not-found
else
  echo "KAI Scheduler not found, skipping..."
fi

# ============================================================
# GPU Operator
# ============================================================

if helm status gpu-operator -n gpu-operator &>/dev/null; then
  echo "Uninstalling GPU Operator..."
  helm uninstall gpu-operator -n gpu-operator
  kubectl delete namespace gpu-operator --ignore-not-found
else
  echo "GPU Operator not found, skipping..."
fi

# ============================================================
# PodMonitor
# ============================================================

echo "Removing GPU PodMonitor..."
kubectl delete podmonitor nvidia-dcgm-exporter -n kube-system --ignore-not-found

echo ""
echo "============================"
echo "Robotics Charts Uninstalled"
echo "============================"
echo ""
echo "Note: The osmo namespace was NOT deleted to preserve workloads."
echo "To delete the osmo namespace: kubectl delete namespace osmo"
