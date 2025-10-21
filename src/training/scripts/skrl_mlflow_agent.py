"""SKRL MLflow integration utilities.

This module provides utility functions for integrating SKRL agent training with
MLflow metric logging via monkey-patching agent._update methods.

Available Metrics
-----------------
Extracts the following metric categories from SKRL agents:

**Episode Statistics:**
- Reward metrics: episode_reward, episode_reward_mean, cumulative_rewards, mean_rewards
- Episode length metrics: episode_length, episode_length_mean, episode_lengths
- Success metrics: success_rate

**Training Losses:**
- Policy loss: policy_loss
- Value/Critic loss: value_loss, critic_loss
- Entropy: entropy

**Optimization Metrics:**
- Learning rate: learning_rate, lr
- Gradient norm: grad_norm, gradient_norm
- KL divergence: kl_divergence, kl

**Timing Metrics:**
- Timesteps: timesteps, timesteps_total, total_timesteps
- Iterations: iterations, iterations_total
- FPS: fps
- Timing: time_elapsed, epoch_time, rollout_time, learning_time

**Additional Metrics:**
All entries in agent.tracking_data dict are extracted, supporting custom metrics
from different SKRL algorithms (PPO, SAC, TD3, DDPG, A2C, etc.).

**System Metrics:**
Collected via psutil and pynvml with system/ prefix:
- CPU: system/cpu_utilization_percentage
- Memory: system/memory_used_megabytes, system/memory_percent, system/memory_available_megabytes
- GPU: system/gpu_{i}_utilization_percentage, system/gpu_{i}_memory_percent, system/gpu_{i}_memory_used_megabytes, system/gpu_{i}_power_watts
- Disk: system/disk_used_gigabytes, system/disk_percent, system/disk_available_gigabytes

Metric Logging
--------------
Metrics are logged to MLflow after each agent._update() call, which is when SKRL
agents populate their tracking_data dict. This occurs after collecting rollouts
(e.g., every 16 environment steps for default PPO config), ensuring metrics
reflect actual training updates rather than environment interactions.

Metric Filtering
----------------
Use the metric_filter parameter to control which metrics are logged:
- None (default): Log all available metrics
- set of str: Only log metrics whose names are in the set
- Useful for reducing MLflow API load in production environments

Usage Example
-------------
```python
from training.scripts.skrl_mlflow_agent import create_mlflow_logging_wrapper
import mlflow

# After creating SKRL runner with agent
wrapper_func = create_mlflow_logging_wrapper(
    agent=runner.agent,
    mlflow_module=mlflow,
    metric_filter=None,
    collect_gpu_metrics=True,
)

# Monkey-patch the agent's _update method
runner.agent._update = wrapper_func

# Now when runner.run() executes, metrics will be logged to MLflow
runner.run()
```
"""

from __future__ import annotations

import logging
from typing import Any, Callable, Protocol, runtime_checkable

_LOGGER = logging.getLogger(__name__)


@runtime_checkable
class SkrlAgent(Protocol):
    """Protocol defining the interface expected from SKRL agents for metric extraction."""

    tracking_data: dict[str, Any]
    _update: Callable[[int, int], Any]


@runtime_checkable
class MLflowModule(Protocol):
    """Protocol defining the MLflow API used for logging metrics."""

    def log_metrics(
        self,
        metrics: dict[str, float],
        step: int | None = None,
        synchronous: bool = True,
    ) -> None: ...


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


def _has_tracking_data(agent: SkrlAgent) -> bool:
    """Check if agent has valid tracking_data dict."""
    return hasattr(agent, "tracking_data") and isinstance(agent.tracking_data, dict)


def _extract_metrics_from_agent(
    agent: SkrlAgent,
    metric_filter: set[str] | None = None,
) -> dict[str, float]:
    """Extract metrics from SKRL agent's internal state.

    Extracts from agent.tracking_data dict, direct attributes, and nested
    structures. Multi-element values produce mean/std/min/max statistics.

    Args:
        agent: SKRL agent instance with tracking_data dict.
        metric_filter: Optional set of metric names to include.

    Returns:
        Dictionary of metric names to float values.
    """
    metrics: dict[str, float] = {}

    if _has_tracking_data(agent):
        _extract_from_tracking_data(agent.tracking_data, metrics, prefix="")

    for attr_name in _STANDARD_METRIC_ATTRS:
        if hasattr(agent, attr_name):
            _extract_from_value(attr_name, getattr(agent, attr_name), metrics)

    if metric_filter:
        metrics = {k: v for k, v in metrics.items() if k in metric_filter}

    return metrics


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
            _LOGGER.debug("GPU metrics collection initialized (%d devices)", device_count)
        except Exception as exc:
            _LOGGER.debug("GPU metrics unavailable: %s", exc)
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


def create_mlflow_logging_wrapper(
    agent: SkrlAgent,
    mlflow_module: MLflowModule,
    metric_filter: set[str] | None = None,
    collect_gpu_metrics: bool = True,
) -> Callable[[int, int], Any]:
    """Create closure that wraps agent._update with MLflow logging.

    Returns a function that calls the original agent._update method then
    extracts and logs metrics to MLflow.

    Args:
        agent: SKRL agent instance to extract metrics from.
        mlflow_module: MLflow module for logging metrics.
        metric_filter: Optional set of metric names to include.
        collect_gpu_metrics: Enable GPU metrics collection (default: True).

    Returns:
        Closure function suitable for monkey-patching agent._update.

    Raises:
        AttributeError: If agent lacks tracking_data attribute.

    Example:
        >>> wrapper = create_mlflow_logging_wrapper(runner.agent, mlflow)
        >>> runner.agent._update = wrapper
    """
    if not _has_tracking_data(agent):
        raise AttributeError(
            "Agent must have 'tracking_data' attribute for MLflow metric logging. "
            f"Agent type {type(agent).__name__} does not support metric tracking."
        )

    system_metrics_collector = SystemMetricsCollector(
        collect_gpu=collect_gpu_metrics,
        collect_disk=True,
    )
    _LOGGER.debug(
        "System metrics collector initialized (GPU: %s)",
        collect_gpu_metrics,
    )

    original_update = agent._update

    def mlflow_logging_update(timestep: int, timesteps: int) -> Any:
        """Call original _update and log metrics to MLflow."""
        result = original_update(timestep, timesteps)

        try:
            training_metrics = _extract_metrics_from_agent(agent, metric_filter)

            system_metrics = {}
            try:
                system_metrics = system_metrics_collector.collect_metrics()
                _LOGGER.debug(
                    "System metrics collected: %d metrics",
                    len(system_metrics),
                )
            except Exception as exc:
                _LOGGER.debug("System metrics collection failed: %s", exc)

            all_metrics = {**training_metrics, **system_metrics}

            if all_metrics and mlflow_module:
                mlflow_module.log_metrics(all_metrics, step=timestep, synchronous=False)
            elif not all_metrics:
                _LOGGER.debug("No metrics extracted at timestep %d", timestep)
        except Exception as exc:
            _LOGGER.warning("Failed to log metrics at timestep %d: %s", timestep, exc)

        return result

    return mlflow_logging_update
