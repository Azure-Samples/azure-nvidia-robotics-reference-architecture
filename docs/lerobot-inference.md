# LeRobot ACT Policy Inference

Run a trained ACT (Action Chunking with Transformers) policy locally against dataset observations or on a live UR10E robot via ROS2.

## 📋 Prerequisites

| Tool              | Version | Install                    |
| ----------------- | ------- | -------------------------- |
| Python            | 3.10+   | System or `pyenv`          |
| `uv` or `pip`     | Latest  | `pip install uv`           |
| Azure CLI         | 2.50+   | `uv pip install azure-cli` |
| `az ml` extension | 2.22+   | `az extension add -n ml`   |

## 🚀 Quick Start

### Pull the Model

The trained checkpoint is available from two sources.

**From Azure ML:**

```bash
az ml model download \
  --name hve-robo-act-train --version 1 \
  --download-path ./checkpoint \
  --resource-group rg-osmorbt3-dev-001 \
  --workspace-name mlw-osmorbt3-dev-001
```

**From HuggingFace Hub:**

```bash
pip install huggingface-hub
huggingface-cli download alizaidi/hve-robo-act-train --local-dir ./checkpoint/hve-robo-act-train
```

Both produce the same directory:

```text
hve-robo-act-train/
├── config.json                                                # Policy architecture config
├── model.safetensors                                          # Trained weights (197 MB)
├── policy_preprocessor.json                                   # Input normalization pipeline
├── policy_preprocessor_step_3_normalizer_processor.safetensors
├── policy_postprocessor.json                                  # Output unnormalization pipeline
├── policy_postprocessor_step_0_unnormalizer_processor.safetensors
└── train_config.json                                          # Training hyperparameters
```

### Install Dependencies

```bash
uv pip install lerobot av pyarrow
```

### Run Offline Inference

Validate the model against recorded dataset observations:

```bash
python scripts/test-lerobot-inference.py \
  --policy-repo alizaidi/hve-robo-act-train \
  --dataset-dir /path/to/hve-robo-cell \
  --episode 0 --start-frame 100 --num-steps 30 \
  --device cuda
```

Use `--policy-repo ./checkpoint/hve-robo-act-train` when loading from a local path instead of HuggingFace Hub.

Expected output:

```text
Episode 0: 668 frames, starting at frame 100, testing 30 steps
  step   0: pred=[  0.001,   0.002,  -0.001,  -0.004,  -0.019,   0.000]  gt=[  0.001,   0.002,  -0.002,  -0.005,  -0.019,   0.000]

============================================================
Inference Results
============================================================
  Steps evaluated:    30
  MSE (all joints):   0.000004
  MAE (all joints):   0.001173
  Throughput:         130.0 steps/s
  Realtime capable:   yes (need 30 Hz)
```

## ⚙️ Configuration

### Inference Script Parameters

| Parameter       | Default                       | Description                             |
| --------------- | ----------------------------- | --------------------------------------- |
| `--policy-repo` | `alizaidi/hve-robo-act-train` | HuggingFace repo ID or local path       |
| `--dataset-dir` | (required)                    | LeRobot v3 dataset root directory       |
| `--episode`     | `0`                           | Episode index for test observations     |
| `--start-frame` | `0`                           | Starting frame within the episode       |
| `--num-steps`   | `30`                          | Number of inference steps               |
| `--device`      | `cuda`                        | Inference device (`cuda`, `cpu`, `mps`) |
| `--output`      | (none)                        | Save predictions to `.npz` file         |

### Model Details

| Property          | Value                                   |
| ----------------- | --------------------------------------- |
| Policy type       | ACT (Action Chunking with Transformers) |
| Parameters        | 51.6M                                   |
| State dim         | 6 (UR10E joint positions in radians)    |
| Action dim        | 6 (joint position deltas)               |
| Image input       | 480 x 848 RGB                           |
| Control frequency | 30 Hz                                   |
| Backbone          | ResNet-18                               |

## 🤖 ROS2 Deployment

For real robot control, use the ROS2 inference node in `src/inference/scripts/act_inference_node.py`.

### Data Classes

`src/inference/robot_types.py` defines the interface between the robot and the policy:

| Type                               | Maps to                    | Shape                 |
| ---------------------------------- | -------------------------- | --------------------- |
| `RobotObservation.joint_positions` | `observation.state`        | `(6,)` radians        |
| `RobotObservation.color_image`     | `observation.images.color` | `(480, 848, 3)` uint8 |
| `JointPositionCommand.positions`   | `action`                   | `(6,)` radians        |

### Dry Run (No Robot Commands)

```bash
ros2 run lerobot_inference act_inference_node \
  --ros-args -p policy_repo:=alizaidi/hve-robo-act-train \
             -p device:=cuda \
             -p enable_control:=false
```

Monitor predictions on `/lerobot/status`.

### Live Control

```bash
ros2 run lerobot_inference act_inference_node \
  --ros-args -p policy_repo:=alizaidi/hve-robo-act-train \
             -p device:=cuda \
             -p enable_control:=true \
             -p action_mode:=delta
```

> [!WARNING]
> Set `enable_control:=false` first and verify predictions on `/lerobot/status` are reasonable before enabling live robot commands.

### ROS2 Node Parameters

| Parameter            | Default                       | Description                            |
| -------------------- | ----------------------------- | -------------------------------------- |
| `policy_repo`        | `alizaidi/hve-robo-act-train` | Model source                           |
| `device`             | `cuda`                        | Inference device                       |
| `control_hz`         | `30.0`                        | Control loop frequency                 |
| `action_mode`        | `delta`                       | `delta` (add to current) or `absolute` |
| `enable_control`     | `false`                       | Publish commands to the robot          |
| `camera_topic`       | `/camera/color/image_raw`     | RGB image topic                        |
| `joint_states_topic` | `/joint_states`               | Joint state topic                      |

### ROS2 Topics

| Topic                     | Type                              | Direction |
| ------------------------- | --------------------------------- | --------- |
| `/joint_states`           | `sensor_msgs/JointState`          | Subscribe |
| `/camera/color/image_raw` | `sensor_msgs/Image`               | Subscribe |
| `/lerobot/joint_commands` | `trajectory_msgs/JointTrajectory` | Publish   |
| `/lerobot/status`         | `std_msgs/String`                 | Publish   |

## 🔗 Related Documentation

- [MLflow Integration](mlflow-integration.md) for experiment tracking during training
- [Workflows README](../workflows/README.md) for training workflow definitions
- [Scripts README](../scripts/README.md) for submission script usage
