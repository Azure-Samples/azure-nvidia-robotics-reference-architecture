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

    def log_metrics(self, metrics: dict[str, float], step: int | None = None) -> None: ...


def _is_tensor_scalar(value: Any) -> bool:
    return hasattr(value, "item") and hasattr(value, "numel") and value.numel() == 1


def _is_tensor_array(value: Any) -> bool:
    return hasattr(value, "item") and hasattr(value, "numel") and value.numel() > 1


def _is_numpy_array(value: Any) -> bool:
    return hasattr(value, "mean") and hasattr(value, "__len__") and len(value) > 1


def _is_single_element_sequence(value: Any) -> bool:
    return hasattr(value, "__len__") and len(value) == 1


def _extract_tensor_scalar(name: str, value: Any, metrics: dict[str, float]) -> None:
    metrics[name] = float(value.item())


def _extract_tensor_statistics(name: str, value: Any, metrics: dict[str, float]) -> None:
    if hasattr(value, "mean"):
        metrics[f"{name}/mean"] = float(value.mean().item())
    if hasattr(value, "std"):
        metrics[f"{name}/std"] = float(value.std().item())
    if hasattr(value, "min"):
        metrics[f"{name}/min"] = float(value.min().item())
    if hasattr(value, "max"):
        metrics[f"{name}/max"] = float(value.max().item())


def _extract_numpy_statistics(name: str, value: Any, metrics: dict[str, float]) -> None:
    import numpy as np

    arr = np.asarray(value)
    metrics[f"{name}/mean"] = float(np.mean(arr))
    metrics[f"{name}/std"] = float(np.std(arr))
    metrics[f"{name}/min"] = float(np.min(arr))
    metrics[f"{name}/max"] = float(np.max(arr))


def _extract_from_value(name: str, value: int | float | Any, metrics: dict[str, float]) -> None:
    """Extract numeric value and add to metrics dict.

    Handles tensors, arrays, and numeric types. For tensors/arrays with multiple
    elements, extracts mean, std, min, max statistics.

    Args:
        name: Metric name
        value: Value to extract (can be tensor, array, or numeric)
        metrics: Output dictionary to populate
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
        data: Dictionary to extract from (tracking_data or nested dict)
        metrics: Output dictionary to populate with metrics
        prefix: Metric name prefix for nested structures
        max_depth: Maximum recursion depth to prevent infinite loops
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
    return hasattr(agent, "tracking_data") and isinstance(agent.tracking_data, dict)


def _extract_metrics_from_agent(
    agent: SkrlAgent,
    metric_filter: set[str] | None = None,
) -> dict[str, float]:
    """Extract metrics from the SKRL agent's internal state.

    Extracts metrics from multiple sources:
    - agent.tracking_data dict (SKRL's primary tracking mechanism)
    - Direct agent attributes for common metrics
    - Nested structures in tracking_data
    - Statistical aggregations (mean, std, min, max) when available

    Args:
        agent: SKRL agent instance with tracking_data dict
        metric_filter: Optional set of metric names to include

    Returns:
        Dictionary of metric names to float values, filtered by metric_filter if set
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


def create_mlflow_logging_wrapper(
    agent: SkrlAgent,
    mlflow_module: MLflowModule,
    metric_filter: set[str] | None = None,
) -> Callable[[int, int], Any]:
    """Create closure that wraps agent._update with MLflow logging.

    Returns a function suitable for monkey-patching agent._update. The returned
    closure will call the original agent._update method and then extract and log
    metrics to MLflow.

    Args:
        agent: SKRL agent instance to extract metrics from
        mlflow_module: MLflow module for logging metrics
        metric_filter: Optional set of metric names to include

    Returns:
        Closure function with signature (timestep: int, timesteps: int) -> Any
        that can be assigned to agent._update for monkey-patching

    Example:
        >>> wrapper_func = create_mlflow_logging_wrapper(runner.agent, mlflow, None)
        >>> runner.agent._update = wrapper_func
    """
    if not _has_tracking_data(agent):
        if not hasattr(agent, "tracking_data"):
            raise AttributeError(
                "Agent must have 'tracking_data' attribute for MLflow metric logging. "
                f"Agent type {type(agent).__name__} does not support metric tracking."
            )
        raise TypeError(
            f"Agent 'tracking_data' must be a dict, got {type(agent.tracking_data).__name__}. "
            "Cannot extract metrics from non-dict tracking_data."
        )

    original_update = agent._update

    def mlflow_logging_update(timestep: int, timesteps: int) -> Any:
        """Wrapped _update that logs metrics to MLflow after each training update."""
        result = original_update(timestep, timesteps)

        try:
            metrics = _extract_metrics_from_agent(agent, metric_filter)
            if metrics and mlflow_module:
                mlflow_module.log_metrics(metrics, step=timestep)
            elif not metrics:
                _LOGGER.debug("No metrics extracted at timestep %d", timestep)
        except Exception as exc:
            _LOGGER.warning("Failed to log metrics at timestep %d: %s", timestep, exc)

        return result

    return mlflow_logging_update
