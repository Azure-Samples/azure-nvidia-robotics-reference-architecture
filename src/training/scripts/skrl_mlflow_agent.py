"""SKRL agent wrapper for MLflow metric logging.

Available Metrics
-----------------
This wrapper extracts the following metric categories from SKRL agents:

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
"""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional, Set

_LOGGER = logging.getLogger(__name__)


class MLflowAgentWrapper:
    """Wrapper around SKRL agents to intercept _update and log metrics to MLflow.

    This wrapper uses delegation to transparently proxy all agent operations while
    intercepting _update() calls to extract and log training metrics to MLflow.
    The _update() method is the correct hook point because SKRL agents only populate
    their tracking_data dict during _update() calls (after collecting rollouts), not
    during post_interaction() which happens after every environment step.

    Args:
        agent: The SKRL agent instance to wrap
        mlflow_module: The mlflow module for logging metrics
        log_interval: Deprecated parameter, kept for backward compatibility but not used.
            Metrics are now logged on every _update() call when tracking_data is populated.
        metric_filter: Optional set of metric names to log. If None, all metrics are logged.
            Use this to reduce MLflow API load by only logging specific metrics of interest.
    """

    def __init__(
        self,
        agent: Any,
        mlflow_module: Any,
        log_interval: int = 10,
        metric_filter: Optional[Set[str]] = None,
    ) -> None:
        self._agent = agent
        self._mlflow = mlflow_module
        self._metric_filter = metric_filter

        if not hasattr(agent, "tracking_data"):
            raise AttributeError(
                "Agent must have 'tracking_data' attribute for MLflow metric logging. "
                f"Agent type {type(agent).__name__} does not support metric tracking."
            )
        if not isinstance(agent.tracking_data, dict):
            raise TypeError(
                f"Agent 'tracking_data' must be a dict, got {type(agent.tracking_data).__name__}. "
                "Cannot extract metrics from non-dict tracking_data."
            )

    def __getattr__(self, name: str) -> Any:
        """Delegate all attribute access to the wrapped agent except for explicitly overridden methods."""
        return getattr(self._agent, name)

    def _update(self, timestep: int, timesteps: int) -> Any:
        """Override _update to extract and log metrics to MLflow after each training update.

        Calls the original agent's _update method first (which populates tracking_data),
        then extracts metrics and logs them to MLflow. This is the correct hook point
        because SKRL agents only populate tracking_data during _update() calls, not
        during post_interaction() which happens after every environment step.

        Args:
            timestep: Current timestep in the training process
            timesteps: Total number of timesteps for training

        Returns:
            The return value from the wrapped agent's _update method
        """
        result = self._agent._update(timestep, timesteps)

        try:
            metrics = self._extract_metrics()
            if metrics and self._mlflow:
                self._mlflow.log_metrics(metrics, step=timestep)
                _LOGGER.debug("Logged %d metrics to MLflow at timestep %d", len(metrics), timestep)
        except Exception as exc:
            _LOGGER.warning("Failed to extract or log metrics at timestep %d: %s", timestep, exc)

        return result

    def _extract_metrics(self) -> Dict[str, float]:
        """Extract metrics from the SKRL agent's internal state.

        Extracts metrics from multiple sources:
        - agent.tracking_data dict (SKRL's primary tracking mechanism)
        - Direct agent attributes for common metrics
        - Nested structures in tracking_data
        - Statistical aggregations (mean, std, min, max) when available

        Returns:
            Dictionary of metric names to float values, filtered by metric_filter if set
        """
        metrics: Dict[str, float] = {}

        if hasattr(self._agent, "tracking_data") and isinstance(self._agent.tracking_data, dict):
            self._extract_from_tracking_data(self._agent.tracking_data, metrics, prefix="")

        metric_attrs = [
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

        for attr_name in metric_attrs:
            if hasattr(self._agent, attr_name):
                self._extract_from_value(attr_name, getattr(self._agent, attr_name), metrics)

        if self._metric_filter:
            metrics = {k: v for k, v in metrics.items() if k in self._metric_filter}

        return metrics

    def _extract_from_tracking_data(
        self,
        data: Dict[str, Any],
        metrics: Dict[str, float],
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
                self._extract_from_tracking_data(value, metrics, f"{metric_name}/", max_depth - 1)
            else:
                self._extract_from_value(metric_name, value, metrics)

    def _extract_from_value(self, name: str, value: Any, metrics: Dict[str, float]) -> None:
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
            if hasattr(value, "item"):
                if hasattr(value, "numel") and value.numel() == 1:
                    metrics[name] = float(value.item())
                elif hasattr(value, "numel") and value.numel() > 1:
                    if hasattr(value, "mean"):
                        metrics[f"{name}/mean"] = float(value.mean().item())
                    if hasattr(value, "std"):
                        metrics[f"{name}/std"] = float(value.std().item())
                    if hasattr(value, "min"):
                        metrics[f"{name}/min"] = float(value.min().item())
                    if hasattr(value, "max"):
                        metrics[f"{name}/max"] = float(value.max().item())
                else:
                    metrics[name] = float(value.item())
            elif hasattr(value, "mean") and hasattr(value, "__len__") and len(value) > 1:
                import numpy as np

                arr = np.asarray(value)
                metrics[f"{name}/mean"] = float(np.mean(arr))
                metrics[f"{name}/std"] = float(np.std(arr))
                metrics[f"{name}/min"] = float(np.min(arr))
                metrics[f"{name}/max"] = float(np.max(arr))
            elif hasattr(value, "__len__") and len(value) == 1:
                metrics[name] = float(value[0])
            else:
                metrics[name] = float(value)
        except (ValueError, TypeError, AttributeError, IndexError) as exc:
            _LOGGER.debug("Could not convert %s to float: %s", name, exc)
