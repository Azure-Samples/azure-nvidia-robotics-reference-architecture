---
title: MLflow Integration for SKRL Training
description: MLflow metric logging integration with SKRL agent training during Isaac Lab training runs
author: Microsoft Robotics-AI Team
ms.date: 2026-02-24
ms.topic: reference
keywords:
  - MLflow
  - SKRL
  - Isaac Lab
  - training
  - metrics
  - experiment tracking
---

## MLflow Integration for SKRL Training

MLflow metric logging integration with SKRL agent training during Isaac Lab training runs.

## Overview

The training pipeline uses monkey-patching to wrap the agent's `_update` method, intercepting training updates to extract and log metrics to MLflow. This approach provides comprehensive experiment tracking without modifying the underlying SKRL agent implementation or training code.

## Available Metrics

The MLflow integration automatically extracts metrics from SKRL agents across several categories:

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

For metrics with multiple values (tensors or arrays), the integration extracts statistical aggregates:

* `metric_name/mean` - Mean value
* `metric_name/std` - Standard deviation
* `metric_name/min` - Minimum value
* `metric_name/max` - Maximum value

### Custom Metrics

All entries in `agent.tracking_data` are automatically extracted, supporting algorithm-specific metrics from PPO, SAC, TD3, DDPG, A2C, and other SKRL implementations.

## Implementation Details

The integration uses the `create_mlflow_logging_wrapper` function from `skrl_mlflow_agent` module to create a closure that wraps the agent's `_update` method. The wrapper is applied after the SKRL Runner is instantiated but before training begins.

### Configuration Parameters

* `agent` - The SKRL agent instance to extract metrics from (required)
* `mlflow_module` - The mlflow module for logging metrics (required)
* `metric_filter` - Optional set of metric names to log (default: None)
  * When None, all available metrics are logged
  * Use a set of strings to only log specific metrics
  * Useful for reducing MLflow API load in production environments

### Logging Interval

The MLflow logging interval is controlled via the `--mlflow_log_interval` CLI argument:

* `step` - Log metrics after every training step (most frequent)
* `balanced` - Log metrics every 10 steps (default, recommended)
* `rollout` - Log metrics once per rollout cycle
* Integer value - Custom interval in steps

### Metric Filtering Examples

To customize which metrics are logged, modify the `create_mlflow_logging_wrapper` call in `skrl_training.py`:

```python
from training.scripts.skrl_mlflow_agent import create_mlflow_logging_wrapper

basic_metrics = {
    "episode_reward_mean",
    "episode_length_mean",
    "policy_loss",
    "value_loss",
}

wrapper_func = create_mlflow_logging_wrapper(
    agent=runner.agent,
    mlflow_module=mlflow,
    metric_filter=basic_metrics,
)
runner.agent._update = wrapper_func
```

```python
optimization_metrics = {
    "learning_rate",
    "grad_norm",
    "kl_divergence",
    "policy_loss",
    "value_loss",
}

wrapper_func = create_mlflow_logging_wrapper(
    agent=runner.agent,
    mlflow_module=mlflow,
    metric_filter=optimization_metrics,
)
runner.agent._update = wrapper_func
```

## Usage Examples

### Integration with SKRL Training

The monkey-patching approach is applied after creating the SKRL Runner:

```python
import mlflow
from skrl.utils.runner.torch import Runner
from training.scripts.skrl_mlflow_agent import create_mlflow_logging_wrapper

mlflow.set_tracking_uri("azureml://...")
mlflow.set_experiment("isaaclab-training")

with mlflow.start_run():
    runner = Runner(env, agent_cfg)

    wrapper_func = create_mlflow_logging_wrapper(
        agent=runner.agent,
        mlflow_module=mlflow,
        metric_filter=None,
    )

    runner.agent._update = wrapper_func
    runner.run()
```

### Configuring Logging Intervals

Use CLI arguments to control logging frequency:

```bash
# Log after every training step
python src/training/scripts/skrl_training.py --mlflow_log_interval step

# Log every 10 steps (default)
python src/training/scripts/skrl_training.py --mlflow_log_interval balanced

# Log once per rollout
python src/training/scripts/skrl_training.py --mlflow_log_interval rollout

# Log every 100 steps
python src/training/scripts/skrl_training.py --mlflow_log_interval 100
```

### Filtering Metrics for Production

Modify the wrapper creation in `skrl_training.py`:

```python
production_metrics = {
    "episode_reward_mean",
    "episode_length_mean",
    "success_rate",
}

wrapper_func = create_mlflow_logging_wrapper(
    agent=runner.agent,
    mlflow_module=mlflow,
    metric_filter=production_metrics,
)
runner.agent._update = wrapper_func
```

## Integration with Isaac Lab

The MLflow integration is automatically applied in `skrl_training.py` when training with Isaac Lab tasks:

```bash
python src/training/scripts/skrl_training.py \
    --task Isaac-Cartpole-v0 \
    --num_envs 512 \
    --headless
```

The training script handles MLflow setup and monkey-patching automatically. To customize the logging interval, use the `--mlflow_log_interval` argument. To customize metric filtering, modify the `create_mlflow_logging_wrapper` call in `skrl_training.py`.

## Troubleshooting

### No Metrics Logged to MLflow

**Symptom:** Training runs complete but no metrics appear in MLflow.

| Cause                       | Resolution                                                                                                            |
|-----------------------------|-----------------------------------------------------------------------------------------------------------------------|
| MLflow not configured       | Verify `mlflow.set_tracking_uri()` with correct Azure ML workspace URI and authentication                             |
| Monkey-patching not applied | Call `create_mlflow_logging_wrapper` after Runner instantiation, replace `runner.agent._update` before `runner.run()` |
| Short training run          | Metrics capture after rollouts complete, not after every environment step                                             |

### Missing or Empty Metrics

**Symptom:** Some expected metrics are missing, or the integration extracts zero metrics.

| Cause                     | Resolution                                                                                   |
|---------------------------|----------------------------------------------------------------------------------------------|
| Metric not in agent       | Different SKRL algorithms expose different metrics; check `agent.tracking_data`              |
| Metric filtered out       | Verify `metric_filter` set contains correct metric names and spelling                        |
| Agent not tracking yet    | Training updates occur after rollouts; wait for first rollout to complete                    |
| Extraction depth exceeded | Nested metrics beyond `max_depth=2` are skipped; increase in `_extract_from_tracking_data()` |

### AttributeError on Agent

**Symptom:** `AttributeError: Agent must have 'tracking_data' attribute`

| Cause                   | Resolution                                                                         |
|-------------------------|------------------------------------------------------------------------------------|
| Incompatible agent type | Use a SKRL agent with `tracking_data` attribute; verify SKRL version compatibility |
| Agent not initialized   | Apply monkey-patch after Runner instantiation with all required parameters         |
| Timing issue            | Verify `runner.agent` and `runner.agent._update` exist before replacement          |

### High MLflow API Load

**Symptom:** Training slows down due to excessive MLflow API calls.

| Solution                  | Details                                                                          |
|---------------------------|----------------------------------------------------------------------------------|
| Increase logging interval | Use `--mlflow_log_interval 100` or higher                                        |
| Use `metric_filter`       | Log only essential metrics to reduce payload size                                |
| Verify batch logging      | Integration already batches per update; enable asynchronous logging if available |

### Metric Extraction Warnings

**Symptom:** Log messages like `"Failed to extract or log metrics at step X"`

| Cause                     | Resolution                                                                            |
|---------------------------|---------------------------------------------------------------------------------------|
| Transient data changes    | Algorithms may modify `tracking_data` during training; usually harmless if occasional |
| Incompatible metric types | Integration converts to float; complex objects are skipped                            |
| Custom metric types       | Modify `_extract_from_value()` in `skrl_mlflow_agent.py` for specific types           |

## Related Documentation

* [Training Guide](README.md)
* [Inference Guide](../inference/README.md)
* [Workflow Templates](../../workflows/README.md)

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
