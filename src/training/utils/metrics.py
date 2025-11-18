"""System and training metrics collection utilities.

Provides reusable metrics collectors for training integrations.
"""

from __future__ import annotations

import logging
from typing import Any

_LOGGER = logging.getLogger(__name__)


def _is_tensor_scalar(value: Any) -> bool:
    """Check if value is a single-element tensor."""
    return hasattr(value, "item") and hasattr(value, "numel") and value.numel() == 1


def _is_tensor_array(value: Any) -> bool:
    """Check if value is a multi-element tensor."""
    return hasattr(value, "item") and hasattr(value, "numel") and value.numel() > 1


def _is_numpy_array(value: Any) -> bool:
    """Check if value is a multi-element numpy array."""
    return hasattr(value, "mean") and hasattr(value, "__len__") and len(value) > 1


def _is_single_element_sequence(value: Any) -> bool:
    """Check if value is a sequence with exactly one element."""
    return hasattr(value, "__len__") and len(value) == 1


def _extract_tensor_scalar(name: str, value: Any, metrics: dict[str, float]) -> None:
    """Extract scalar value from single-element tensor."""
    metrics[name] = float(value.item())


def _extract_tensor_statistics(name: str, value: Any, metrics: dict[str, float]) -> None:
    """Extract mean, std, min, max statistics from tensor array."""
    if hasattr(value, "mean"):
        metrics[f"{name}/mean"] = float(value.mean().item())
    if hasattr(value, "std"):
        metrics[f"{name}/std"] = float(value.std().item())
    if hasattr(value, "min"):
        metrics[f"{name}/min"] = float(value.min().item())
    if hasattr(value, "max"):
        metrics[f"{name}/max"] = float(value.max().item())


def _extract_numpy_statistics(name: str, value: Any, metrics: dict[str, float]) -> None:
    """Extract mean, std, min, max statistics from numpy array."""
    import numpy as np

    arr = np.asarray(value)
    metrics[f"{name}/mean"] = float(np.mean(arr))
    metrics[f"{name}/std"] = float(np.std(arr))
    metrics[f"{name}/min"] = float(np.min(arr))
    metrics[f"{name}/max"] = float(np.max(arr))


def _extract_from_value(name: str, value: int | float | Any, metrics: dict[str, float]) -> None:
    """Extract numeric value and add to metrics dict.

    Handles tensors, numpy arrays, and scalar types. Multi-element arrays
    are converted to mean/std/min/max statistics.

    Args:
        name: Metric name.
        value: Value to extract (tensor, array, or scalar).
        metrics: Output dictionary to populate.
    """
    if value is None:
        return

    try:
        if _is_tensor_scalar(value):
            _extract_tensor_scalar(name, value, metrics)
        elif _is_tensor_array(value):
            _extract_tensor_statistics(name, value, metrics)
        elif hasattr(value, "item"):
            metrics[name] = float(value.item())
        elif _is_numpy_array(value):
            _extract_numpy_statistics(name, value, metrics)
        elif _is_single_element_sequence(value):
            metrics[name] = float(value[0])
        else:
            metrics[name] = float(value)
    except (ValueError, TypeError, AttributeError, IndexError) as exc:
        _LOGGER.debug("Could not convert %s to float: %s", name, exc)


def _extract_from_tracking_data(
    data: dict[str, Any],
    metrics: dict[str, float],
    prefix: str,
    max_depth: int = 2,
) -> None:
    """Recursively extract metrics from tracking_data dict.

    Args:
        data: Dictionary to extract from.
        metrics: Output dictionary to populate.
        prefix: Metric name prefix for nested structures.
        max_depth: Maximum recursion depth.
    """
    if max_depth <= 0:
        return

    for key, value in data.items():
        metric_name = f"{prefix}{key}" if prefix else key

        if isinstance(value, dict):
            _extract_from_tracking_data(value, metrics, f"{metric_name}/", max_depth - 1)
        else:
            _extract_from_value(metric_name, value, metrics)


_STANDARD_METRIC_ATTRS = [
    "episode_reward",
    "episode_reward_mean",
    "episode_length",
    "episode_length_mean",
    "cumulative_rewards",
    "mean_rewards",
    "episode_lengths",
    "success_rate",
    "policy_loss",
    "value_loss",
    "critic_loss",
    "entropy",
    "learning_rate",
    "lr",
    "grad_norm",
    "gradient_norm",
    "kl_divergence",
    "kl",
    "timesteps",
    "timesteps_total",
    "total_timesteps",
    "iterations",
    "iterations_total",
    "fps",
    "time_elapsed",
    "epoch_time",
    "rollout_time",
    "learning_time",
]


class SystemMetricsCollector:
    """Collects system metrics using psutil and pynvml."""

    def __init__(self, collect_gpu: bool = True, collect_disk: bool = True) -> None:
        """Initialize system metrics collector.

        Args:
            collect_gpu: Enable GPU metrics collection (requires pynvml).
            collect_disk: Enable disk metrics collection.
        """
        self._collect_disk = collect_disk
        self._gpu_available = False
        self._gpu_handles: list[Any] = []

        if collect_gpu:
            self._initialize_gpu()

    def _initialize_gpu(self) -> None:
        """Initialize GPU monitoring (NVIDIA via pynvml)."""
        try:
            import pynvml

            pynvml.nvmlInit()
            device_count = pynvml.nvmlDeviceGetCount()
            self._gpu_handles = [pynvml.nvmlDeviceGetHandleByIndex(i) for i in range(device_count)]
            self._gpu_available = True
            _LOGGER.info("GPU metrics collection initialized (%d devices)", device_count)
        except Exception as exc:
            _LOGGER.warning("GPU metrics unavailable (will only log CPU/memory/disk): %s", exc)
            self._gpu_available = False

    def collect_metrics(self) -> dict[str, float]:
        """Collect all system metrics.

        Returns:
            Dictionary of system metrics with system/ prefix.
        """
        metrics: dict[str, float] = {}

        metrics.update(self._collect_cpu_metrics())
        metrics.update(self._collect_gpu_metrics())

        if self._collect_disk:
            metrics.update(self._collect_disk_metrics())

        return metrics

    def _collect_cpu_metrics(self) -> dict[str, float]:
        """Collect CPU and memory metrics using psutil.

        Returns:
            Dictionary with cpu_utilization_percentage and memory metrics.
        """
        import psutil

        metrics: dict[str, float] = {}

        try:
            metrics["system/cpu_utilization_percentage"] = psutil.cpu_percent(interval=None)

            mem = psutil.virtual_memory()
            metrics["system/memory_used_megabytes"] = mem.used / (1024 * 1024)
            metrics["system/memory_available_megabytes"] = mem.available / (1024 * 1024)
            metrics["system/memory_percent"] = mem.percent
        except Exception as exc:
            _LOGGER.debug("CPU/memory metrics collection failed: %s", exc)

        return metrics

    def _collect_gpu_metrics(self) -> dict[str, float]:
        """Collect GPU metrics using pynvml (NVIDIA only).

        Returns:
            Dictionary with gpu_{i}_* metrics, or empty dict if unavailable.
        """
        if not self._gpu_available:
            return {}

        import pynvml

        metrics: dict[str, float] = {}

        for i, handle in enumerate(self._gpu_handles):
            try:
                util = pynvml.nvmlDeviceGetUtilizationRates(handle)
                metrics[f"system/gpu_{i}_utilization_percentage"] = float(util.gpu)

                mem_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
                metrics[f"system/gpu_{i}_memory_used_megabytes"] = mem_info.used / (1024 * 1024)
                metrics[f"system/gpu_{i}_memory_percent"] = (mem_info.used / mem_info.total) * 100

                power = pynvml.nvmlDeviceGetPowerUsage(handle)
                metrics[f"system/gpu_{i}_power_watts"] = power / 1000
            except Exception as exc:
                _LOGGER.debug("GPU %d metrics collection failed: %s", i, exc)

        return metrics

    def _collect_disk_metrics(self) -> dict[str, float]:
        """Collect disk usage metrics using psutil.

        Returns:
            Dictionary with disk usage metrics for root filesystem.
        """
        import psutil

        metrics: dict[str, float] = {}

        try:
            disk = psutil.disk_usage("/")
            metrics["system/disk_used_gigabytes"] = disk.used / (1024 * 1024 * 1024)
            metrics["system/disk_available_gigabytes"] = disk.free / (1024 * 1024 * 1024)
            metrics["system/disk_percent"] = disk.percent
        except Exception as exc:
            _LOGGER.debug("Disk metrics collection failed: %s", exc)

        return metrics
