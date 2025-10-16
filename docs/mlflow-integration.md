# MLflow Integration for SKRL Training

This document explains how to use the `MLflowAgentWrapper` to automatically log training metrics from SKRL agents to MLflow during Isaac Lab training runs.

## Overview

The `MLflowAgentWrapper` transparently wraps SKRL agents to intercept their `post_interaction()` calls and extract training metrics for logging to MLflow. This provides comprehensive experiment tracking without modifying the underlying training code.

## Available Metrics

The wrapper automatically extracts metrics from SKRL agents across several categories:

### Episode Statistics

* `episode_reward` - Reward for the current episode
* `episode_reward_mean` - Mean reward across recent episodes
* `episode_length` - Length of the current episode
* `episode_length_mean` - Mean episode length across recent episodes
* `cumulative_rewards` - Cumulative rewards over time
* `mean_rewards` - Mean reward values
* `success_rate` - Success rate for task-specific metrics

### Training Losses

* `policy_loss` - Policy network loss
* `value_loss` - Value network loss (critic loss for some algorithms)
* `critic_loss` - Critic network loss (SAC, TD3, DDPG)
* `entropy` - Policy entropy for exploration

### Optimization Metrics

* `learning_rate` - Current learning rate
* `grad_norm` - Gradient norm for monitoring optimization
* `kl_divergence` - KL divergence between old and new policies (PPO)

### Timing Metrics

* `timesteps` - Total environment timesteps
* `iterations` - Training iteration count
* `fps` - Training frames per second
* `epoch_time` - Time per training epoch
* `rollout_time` - Time spent collecting experience
* `learning_time` - Time spent in optimization

### Multi-Element Metrics

For metrics with multiple values (tensors or arrays), the wrapper extracts statistical aggregates:

* `metric_name/mean` - Mean value
* `metric_name/std` - Standard deviation
* `metric_name/min` - Minimum value
* `metric_name/max` - Maximum value

### Custom Metrics

All entries in `agent.tracking_data` are automatically extracted, supporting algorithm-specific metrics from PPO, SAC, TD3, DDPG, A2C, and other SKRL implementations.

## Configuration Options

### Basic Configuration

```python
from skrl_mlflow_agent import MLflowAgentWrapper

wrapped_agent = MLflowAgentWrapper(
    agent=skrl_agent,
    mlflow_module=mlflow,
    log_interval=10,
)
```

### Parameters

* `agent` - The SKRL agent instance to wrap (required)
* `mlflow_module` - The mlflow module for logging metrics (required)
* `log_interval` - Number of steps between metric logging (default: 10)
  * Lower values provide more frequent updates but increase MLflow API load
  * Higher values reduce overhead but provide coarser-grained tracking
  * Recommended: 10-100 for most training runs
* `metric_filter` - Optional set of metric names to log (default: None)
  * When None, all available metrics are logged
  * Use a set of strings to only log specific metrics
  * Useful for reducing MLflow API load in production environments

### Metric Filtering Examples

```python
from skrl_mlflow_agent import MLflowAgentWrapper

basic_metrics = {
    "episode_reward_mean",
    "episode_length_mean",
    "policy_loss",
    "value_loss",
}

wrapped_agent = MLflowAgentWrapper(
    agent=skrl_agent,
    mlflow_module=mlflow,
    log_interval=50,
    metric_filter=basic_metrics,
)
```

```python
optimization_metrics = {
    "learning_rate",
    "grad_norm",
    "kl_divergence",
    "policy_loss",
    "value_loss",
}

wrapped_agent = MLflowAgentWrapper(
    agent=skrl_agent,
    mlflow_module=mlflow,
    log_interval=10,
    metric_filter=optimization_metrics,
)
```

## Usage Examples

### Integration with SKRL Training

```python
import mlflow
from skrl.agents.ppo import PPO
from skrl_mlflow_agent import MLflowAgentWrapper

mlflow.set_tracking_uri("azureml://...")
mlflow.set_experiment("isaaclab-training")

with mlflow.start_run():
    agent = PPO(...)
    
    wrapped_agent = MLflowAgentWrapper(
        agent=agent,
        mlflow_module=mlflow,
        log_interval=10,
    )
    
    wrapped_agent.train()
```

### Configuring Logging Intervals

```python
fast_logging = MLflowAgentWrapper(
    agent=agent,
    mlflow_module=mlflow,
    log_interval=1,
)

balanced_logging = MLflowAgentWrapper(
    agent=agent,
    mlflow_module=mlflow,
    log_interval=10,
)

minimal_logging = MLflowAgentWrapper(
    agent=agent,
    mlflow_module=mlflow,
    log_interval=100,
)
```

### Filtering Metrics for Production

```python
production_metrics = {
    "episode_reward_mean",
    "episode_length_mean",
    "success_rate",
}

wrapped_agent = MLflowAgentWrapper(
    agent=agent,
    mlflow_module=mlflow,
    log_interval=100,
    metric_filter=production_metrics,
)
```

## Integration with Isaac Lab

The wrapper is automatically used in `skrl_training.py` when training with Isaac Lab tasks:

```python
python src/training/scripts/skrl_training.py \
    --task Isaac-Cartpole-v0 \
    --num_envs 512 \
    --headless
```

The training script handles MLflow setup and agent wrapping automatically. To customize the logging interval or metric filter, modify the wrapper instantiation in `skrl_training.py`.

## Troubleshooting

### No Metrics Logged to MLflow

**Symptom:** Training runs complete but no metrics appear in MLflow.

**Possible Causes:**

1. MLflow not configured or authenticated
   * Verify `mlflow.set_tracking_uri()` is called with correct Azure ML workspace URI
   * Check Azure authentication is valid
   * Confirm MLflow experiment exists

2. Wrapper not initialized correctly
   * Ensure `MLflowAgentWrapper` is wrapping the agent before `train()` is called
   * Verify `mlflow_module` parameter is the actual mlflow module, not None

3. Log interval too high
   * If training runs are short, reduce `log_interval` to ensure at least one logging event occurs
   * Example: For 1000-step training, use `log_interval <= 1000`

### Missing Specific Metrics

**Symptom:** Some expected metrics are not logged while others are.

**Possible Causes:**

1. Metric not available in agent
   * Different SKRL algorithms expose different metrics
   * Check `agent.tracking_data` to see what the agent actually tracks
   * Some metrics only appear after certain training phases

2. Metric filtered out
   * If using `metric_filter`, ensure desired metric names are included
   * Check spelling and casing of metric names in filter set

3. Metric extraction failed
   * Check logs for warnings about failed metric extraction
   * Some metrics may have incompatible types or structures

### AttributeError on Agent

**Symptom:** `AttributeError: Agent must have 'tracking_data' attribute`

**Possible Causes:**

1. Incompatible agent type
   * Ensure the agent is a SKRL agent with `tracking_data` attribute
   * Verify SKRL version is compatible

2. Agent not fully initialized
   * Wrap the agent after full initialization
   * Ensure the agent has been configured with all required parameters

### High MLflow API Load

**Symptom:** Training slows down due to excessive MLflow API calls.

**Solutions:**

1. Increase `log_interval`
   * Change from `log_interval=10` to `log_interval=100` or higher
   * Balance between metric granularity and performance

2. Use `metric_filter`
   * Log only essential metrics to reduce payload size
   * Remove high-cardinality or nested metrics

3. Batch metric logging
   * The wrapper already batches metrics per step
   * Ensure MLflow is using asynchronous logging if available

### Metric Extraction Warnings

**Symptom:** Log messages like `"Failed to extract or log metrics at step X"`

**Possible Causes:**

1. Transient data structure changes
   * Some algorithms modify `tracking_data` structure during training
   * Usually harmless if only occasional warnings appear

2. Incompatible metric types
   * The wrapper attempts to convert all metrics to float
   * Some complex objects cannot be converted and are skipped

**Solutions:**

1. Check warning details in logs
   * Warnings include the exception message for debugging
   * Determine if the failed metric is critical

2. Add custom extraction logic
   * Modify `_extract_from_value()` for specific metric types
   * Contribute improvements back to the wrapper

### Empty Metrics Dictionary

**Symptom:** Wrapper runs but extracts zero metrics.

**Possible Causes:**

1. Agent `tracking_data` is empty
   * Agent may not have started tracking yet
   * Check agent initialization and training state

2. All metrics filtered out
   * If using `metric_filter` with no matching metric names
   * Verify filter set contains correct metric names

3. Metric extraction depth exceeded
   * Nested metrics beyond `max_depth=2` are not extracted
   * Increase `max_depth` in `_extract_from_tracking_data()` if needed
