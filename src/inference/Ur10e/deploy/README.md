# UR10e ACT Policy Deployment

Deploy the trained LeRobot ACT policy on a UR10e robot at `192.168.2.102` using RTDE (Real-Time Data Exchange) — no ROS2 required.

## Architecture

```text
┌─────────────┐    ┌───────────┐    ┌──────────────┐    ┌───────────┐
│   Camera    │───▶│  Policy   │───▶│   Safety     │───▶│  UR10e    │
│  480×848    │    │  ACT      │    │   Guard      │    │  RTDE     │
│  30 Hz      │    │  (GPU)    │    │  (clamp)     │    │  servoJ   │
└─────────────┘    └───────────┘    └──────────────┘    └───────────┘
                         ▲                                    │
                         │           Joint state (6 DOF)      │
                         └────────────────────────────────────┘
```

## Prerequisites

| Component           | Requirement                          |
| ------------------- | ------------------------------------ |
| Python              | 3.10+                                |
| CUDA GPU            | Required for real-time inference      |
| UR10e               | Firmware 5.x (e-Series), RTDE enabled|
| Network             | Direct Ethernet to 192.168.2.102     |
| Camera              | USB webcam or Intel RealSense D435   |

## Quick Start

### 1. Install dependencies

```bash
cd deploy
uv venv .venv --python 3.10
uv pip install -e .
```

For Intel RealSense cameras:

```bash
uv pip install -e ".[realsense]"
```

### 2. Verify robot connectivity

```bash
ping 192.168.2.102
```

The robot must have RTDE enabled (PolyScope → Settings → System → RTDE).

### 3. Dry-run (no robot commands)

```bash
python -m ur10e_deploy.main --config deploy.yaml
```

This connects to the robot and camera, runs inference, and logs predictions **without** sending any motion commands. Monitor the log output to verify predicted actions are reasonable.

### 4. Live control

> **WARNING**: Ensure the workspace is clear, the E-stop is accessible, and you have verified dry-run output before enabling live control.

```bash
python -m ur10e_deploy.main --config deploy.yaml --enable-control
```

The program waits 5 seconds before starting. Press `Ctrl+C` to stop at any time.

## Configuration

Edit [deploy.yaml](deploy.yaml) or use CLI overrides:

```bash
python -m ur10e_deploy.main \
  --config deploy.yaml \
  --robot-ip 192.168.2.102 \
  --checkpoint ../hve-robo-act-train \
  --device cuda \
  --enable-control
```

### Key Parameters

| Parameter                  | Default | Description                                        |
| -------------------------- | ------- | -------------------------------------------------- |
| `robot.ip`                 | `192.168.2.102` | UR10e controller IP                         |
| `robot.max_delta_rad`      | `0.05`  | Max per-step joint change (rad) — safety clamp     |
| `robot.max_joint_vel`      | `1.0`   | Max joint velocity (rad/s) — safety clamp          |
| `camera.backend`           | `opencv`| `opencv` or `realsense`                            |
| `policy.checkpoint_dir`    | `../hve-robo-act-train` | Path to model weights              |
| `policy.device`            | `cuda`  | Inference device                                   |
| `policy.action_mode`       | `delta` | `delta` (add to current) or `absolute`             |
| `control_hz`               | `30.0`  | Control loop frequency                             |
| `enable_control`           | `false` | Send commands to robot when `true`                 |

## Safety Architecture

Four layers of protection:

| Layer | Component       | What It Does                                          |
| ----- | --------------- | ----------------------------------------------------- |
| 1     | Software guard  | Clamps deltas, positions, and velocities in Python    |
| 2     | RTDE limits     | UR controller rejects out-of-range servoJ targets     |
| 3     | Safety config   | Joint/speed limits configured in PolyScope            |
| 4     | Physical E-stop | Hardware emergency stop button                        |

## Logs

Each episode writes a JSON log to `./logs/episode_YYYYMMDD_HHMMSS.json` containing per-step data:

- `current_q` — observed joint positions
- `action` — raw policy output
- `target_q` — clamped command sent to robot
- `buffer_depth` — action chunk buffer level

## Project Structure

```text
deploy/
├── deploy.yaml                    # Runtime configuration
├── pyproject.toml                 # Python project / dependencies
├── README.md                      # This file
└── ur10e_deploy/
    ├── __init__.py
    ├── camera.py                  # Camera capture (OpenCV / RealSense)
    ├── config.py                  # Configuration dataclasses + YAML loader
    ├── main.py                    # Entry point and control loop
    ├── policy_runner.py           # ACT policy loading and inference
    ├── robot.py                   # UR10e RTDE interface
    └── safety.py                  # Software safety guard
```

## Troubleshooting

| Issue                          | Solution                                            |
| ------------------------------ | --------------------------------------------------- |
| `Cannot connect to robot`      | Check IP, ping, RTDE enabled in PolyScope           |
| `ur_rtde not installed`        | Run `uv pip install ur-rtde`                        |
| `CUDA out of memory`           | Use `--device cpu` (slower but works)               |
| `Camera device not found`      | Check `device_id` or try `--camera-backend realsense`|
| `Loop overrun warnings`        | Reduce `control_hz` or use faster GPU               |
| `Protective stop`              | Robot hit safety limits — widen in PolyScope or reduce `max_delta_rad` |
