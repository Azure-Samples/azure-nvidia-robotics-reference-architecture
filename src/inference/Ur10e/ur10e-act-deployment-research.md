# UR10e ACT Policy Deployment: Technical Research Document

> **Date:** 2026-02-09
> **Scope:** Standalone Python deployment of a LeRobot ACT policy on a UR10e robot via RTDE (no ROS2)

---

## 1. UR10e RTDE (Real-Time Data Exchange) Protocol

### 1.1 Protocol Overview

RTDE is Universal Robots' official real-time communication interface, operating over TCP on port 30004. It provides synchronous, deterministic data exchange at the controller's native frequency:

- **e-Series (UR10e):** 500 Hz native controller frequency
- **CB-Series:** 125 Hz native controller frequency

RTDE replaces the older Real-Time Interface (port 30003) with structured, configurable I/O recipes that avoid the overhead of parsing unstructured byte streams.

### 1.2 Python Library: `ur_rtde`

**Recommended library:** [`ur_rtde`](https://sdurobotics.gitlab.io/ur_rtde/) (PyPI: `ur-rtde`, version 1.6.2+)

```bash
pip install ur_rtde
```

**Why `ur_rtde` over alternatives:**

| Library | Protocol | Real-time | Servo commands | Maintained |
|---------|----------|-----------|----------------|------------|
| **`ur_rtde`** | RTDE (port 30004) | Yes (RT priority support) | `servoJ`, `speedJ`, `servoL` | Active (2025) |
| `python-urx` | Secondary (port 30002) | No (30 Hz max, unreliable timing) | `movej` only | Archived |
| `ur_dashboard` | Dashboard (port 29999) | No | None | Utility only |

`ur_rtde` provides three main Python interfaces, imported as:

```python
from rtde_control import RTDEControlInterface as RTDEControl
from rtde_receive import RTDEReceiveInterface as RTDEReceive
from rtde_io import RTDEIOInterface as RTDEIO
```

### 1.3 Connecting to the UR10e at 192.168.2.102

```python
ROBOT_IP = "192.168.2.102"
CONTROL_FREQUENCY = 500.0  # Hz (e-Series native)

rtde_r = RTDEReceive(ROBOT_IP, CONTROL_FREQUENCY)
rtde_c = RTDEControl(ROBOT_IP, CONTROL_FREQUENCY)
```

**Constructor parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `hostname` | `str` | required | Robot IP address |
| `frequency` | `float` | `-1.0` (use robot default) | RTDE exchange frequency |
| `flags` | `uint16` | `FLAGS_DEFAULT` | `FLAG_VERBOSE \| FLAG_UPLOAD_SCRIPT` etc. |
| `ur_cap_port` | `int` | `50002` | ExternalControl URCap port |
| `rt_priority` | `int` | undefined | OS real-time thread priority (0-99 on Linux) |

### 1.4 Reading Joint Positions

```python
# Returns list of 6 doubles: [base, shoulder, elbow, wrist1, wrist2, wrist3] in radians
actual_q = rtde_r.getActualQ()       # Actual encoder positions
target_q = rtde_r.getTargetQ()       # Target (commanded) positions
actual_qd = rtde_r.getActualQd()     # Actual joint velocities [rad/s]
```

Additional receive interface methods:

- `getActualTCPPose()` → `[x, y, z, rx, ry, rz]` Cartesian pose
- `getActualTCPForce()` → TCP wrench
- `getJointTemperatures()` → 6 joint temperatures in °C
- `getSafetyMode()` → current safety mode enum
- `getSafetyStatusBits()` → bitmask for protective stop, e-stop, etc.
- `isProtectiveStopped()` → `bool`
- `isEmergencyStopped()` → `bool`
- `getRobotMode()` → robot mode integer (7 = RUNNING)
- `getSpeedScaling()` → current speed slider value

### 1.5 Sending Joint Position Commands

#### 1.5.1 `servoJ` — Position Servoing (Recommended for 30 Hz Policy)

```python
rtde_c.servoJ(
    q,                    # list[6] target joint positions [rad]
    speed=0,              # NOT used in current version
    acceleration=0,       # NOT used in current version
    time=1.0/30.0,        # time step = dt = 1/control_freq [s]
    lookahead_time=0.1,   # smoothing [0.03, 0.2] seconds
    gain=300              # proportional gain [100, 2000]
)
```

**Key `servoJ` parameters for 30 Hz control:**

| Parameter | Recommended Value | Notes |
|-----------|-------------------|-------|
| `time` (dt) | `0.0333` (1/30) | Blocking time per step |
| `lookahead_time` | `0.1` | Higher = smoother but more latency |
| `gain` | `300` | Lower = smoother; higher = more responsive. Start low for safety |

**Timing loop pattern:**

```python
while running:
    t_start = rtde_c.initPeriod()
    # ... compute target_q ...
    rtde_c.servoJ(target_q, 0, 0, dt, lookahead_time, gain)
    rtde_c.waitPeriod(t_start)
```

`initPeriod()` + `waitPeriod()` provide sub-millisecond jitter timing using a combination of sleep and spin-wait.

#### 1.5.2 `speedJ` — Velocity Control (Alternative)

```python
rtde_c.speedJ(
    qd,                   # list[6] target joint velocities [rad/s]
    acceleration=0.5,     # joint acceleration [rad/s^2]
    time=0.0              # 0 = continuous until next command
)
```

**`servoJ` vs `speedJ` for delta-action policy:**

- **`servoJ`** is better when the policy outputs absolute target positions (current_q + delta). The built-in PD controller handles smooth tracking.
- **`speedJ`** would require converting position deltas to velocities (delta / dt), adding numerical noise.
- **Recommendation:** Use `servoJ` with the delta actions applied as: `target_q = current_q + action_delta`

#### 1.5.3 Stopping servo mode

```python
rtde_c.servoStop()    # Graceful deceleration from servo mode
rtde_c.stopScript()   # Terminate the control script on robot
```

### 1.6 Safety Features and Limits

#### 1.6.1 Built-in Safety Checks

```python
# Check if a joint target is within safety limits BEFORE sending
is_safe = rtde_c.isJointsWithinSafetyLimits(target_q)

# Check Cartesian pose safety
is_safe = rtde_c.isPoseWithinSafetyLimits(target_pose)
```

#### 1.6.2 Watchdog

```python
# Set minimum communication frequency watchdog
rtde_c.setWatchdog(min_frequency=10.0)  # Robot stops if no command for >100ms

# Must call in control loop to keep watchdog alive
rtde_c.kickWatchdog()
```

#### 1.6.3 Safety Status Monitoring

```python
# Monitor safety state every cycle
if rtde_r.isProtectiveStopped():
    print("Protective stop triggered")
if rtde_r.isEmergencyStopped():
    print("Emergency stop triggered")

safety_bits = rtde_r.getSafetyStatusBits()
# Bits 0-10: normal_mode | reduced_mode | protective_stopped |
#            recovery_mode | safeguard_stopped | system_emergency_stopped |
#            robot_emergency_stopped | emergency_stopped | violation |
#            fault | stopped_due_to_safety
```

#### 1.6.4 Dashboard Client for Power Management

```python
from rtde_control import DashboardClient

dashboard = DashboardClient(ROBOT_IP)
dashboard.connect()
dashboard.powerOn()
dashboard.brakeRelease()
# ... after error ...
dashboard.unlockProtectiveStop()
dashboard.closeSafetyPopup()
```

#### 1.6.5 UR10e Joint Limits (Hardware)

| Joint | Range (rad) | Max Speed (rad/s) | Max Speed (deg/s) |
|-------|-------------|--------------------|--------------------|
| Base (J0) | ±2π (±360°) | 2.094 | 120 |
| Shoulder (J1) | ±2π (±360°) | 2.094 | 120 |
| Elbow (J2) | ±2π (±360°) | 3.142 | 180 |
| Wrist 1 (J3) | ±2π (±360°) | 3.142 | 180 |
| Wrist 2 (J4) | ±2π (±360°) | 3.142 | 180 |
| Wrist 3 (J5) | ±2π (±360°) | 3.142 | 180 |

### 1.7 Control Frequency Capabilities

**Can `ur_rtde` sustain 30 Hz?** — **Yes, easily.**

- The e-Series controller runs at **500 Hz** natively.
- `ur_rtde` has been demonstrated at 500 Hz with real-time priority.
- 30 Hz (33.3 ms per cycle) is **well within** the capability, even without a real-time kernel.
- On Windows, the NT kernel is real-time capable by default. Running as Administrator enables `REALTIME_PRIORITY_CLASS`.
- The `initPeriod()` / `waitPeriod()` API handles precise timing with low jitter.

**Important:** Even though the policy runs at 30 Hz, the RTDE connection itself should be configured at a higher frequency (e.g., 500 Hz) so that `getActualQ()` returns fresh data. The control loop rate (30 Hz) is managed by the `initPeriod()` / `waitPeriod()` calls.

---

## 2. LeRobot ACT Policy Inference

### 2.1 Policy Architecture Summary

From the checkpoint configuration:

| Property | Value |
|----------|-------|
| Policy type | ACT (Action Chunking with Transformers) |
| Parameters | 51.6M |
| Vision backbone | ResNet-18 (ImageNet pretrained) |
| Transformer | 4 encoder layers, 1 decoder layer, dim=512, 8 heads |
| VAE | Enabled (latent_dim=32, 4 VAE encoder layers) |
| chunk_size | 100 |
| n_action_steps | 100 |
| n_obs_steps | 1 |
| State input | `observation.state` → shape (6,) joint radians |
| Image input | `observation.images.color` → shape (3, 480, 848) RGB |
| Action output | `action` → shape (6,) joint position deltas |
| Normalization | MEAN_STD for STATE, ACTION, and VISUAL features |

### 2.2 Loading the Policy from Local Checkpoint

```python
from lerobot.policies.act.modeling_act import ACTPolicy
from lerobot.common.processors.pipeline import DataProcessorPipeline

CHECKPOINT_DIR = "./hve-robo-act-train"

# Load policy model
policy = ACTPolicy.from_pretrained(CHECKPOINT_DIR)
policy.to("cuda")
policy.eval()

# Load preprocessor (normalization, batching, device placement)
preprocessor = DataProcessorPipeline.from_pretrained(
    CHECKPOINT_DIR, config_filename="policy_preprocessor.json"
)

# Load postprocessor (unnormalization, move to CPU)
postprocessor = DataProcessorPipeline.from_pretrained(
    CHECKPOINT_DIR, config_filename="policy_postprocessor.json"
)
```

**What `from_pretrained` does internally:**

1. Reads `config.json` → instantiates `ACTConfig`
2. Creates `ACTPolicy(config)` → builds the ACT transformer model
3. Loads `model.safetensors` weights into the model
4. Places model on the configured device

### 2.3 Preprocessor Pipeline (4 steps)

From `policy_preprocessor.json`:

| Step | Processor | Purpose |
|------|-----------|---------|
| 0 | `rename_observations_processor` | Remap observation keys (empty map in this case) |
| 1 | `to_batch_processor` | Add batch dimension: `(6,)` → `(1, 6)` |
| 2 | `device_processor` | Move tensors to CUDA |
| 3 | `normalizer_processor` | Apply MEAN_STD normalization using learned statistics |

The normalizer loads its mean/std parameters from `policy_preprocessor_step_3_normalizer_processor.safetensors`.

### 2.4 Postprocessor Pipeline (2 steps)

From `policy_postprocessor.json`:

| Step | Processor | Purpose |
|------|-----------|---------|
| 0 | `unnormalizer_processor` | Reverse MEAN_STD normalization on action output |
| 1 | `device_processor` | Move action tensor to CPU |

The unnormalizer loads its parameters from `policy_postprocessor_step_0_unnormalizer_processor.safetensors`.

### 2.5 Running Inference: Observation → Action

The core inference pipeline from LeRobot's `predict_action` utility:

```python
import torch
import numpy as np
from copy import copy

def predict_action(observation, policy, preprocessor, postprocessor, device):
    """
    observation: dict of numpy arrays
        - "observation.state": np.ndarray shape (6,) float32, joint radians
        - "observation.images.color": np.ndarray shape (480, 848, 3) uint8 RGB
    Returns: np.ndarray shape (6,) float32, action delta
    """
    observation = copy(observation)

    # Convert numpy → torch tensors
    # State: already float32
    observation["observation.state"] = torch.from_numpy(
        observation["observation.state"]
    ).float()

    # Image: HWC uint8 → CHW float32 [0,1]
    img = observation["observation.images.color"]
    img = torch.from_numpy(img).permute(2, 0, 1).float() / 255.0
    observation["observation.images.color"] = img

    with torch.inference_mode():
        # Preprocessor: batch, move to device, normalize
        batch = preprocessor(observation)

        # Policy inference: returns single action from action queue
        action = policy.select_action(batch)

        # Postprocessor: unnormalize, move to CPU
        action = postprocessor(action)

    # Remove batch dimension → (6,)
    return action.squeeze(0).numpy()
```

### 2.6 Action Chunking Behavior

With `chunk_size=100` and `n_action_steps=100`:

1. **First call** to `select_action()`:
   - Internal action queue is empty → calls `predict_action_chunk(batch)`
   - Model forward pass produces `(1, 100, 6)` action tensor (100-step chunk)
   - First 100 actions (= `n_action_steps`) are loaded into the action queue
   - Returns the **first** action from the queue

2. **Subsequent calls** (steps 2-100):
   - Queue is not empty → pops and returns the next action
   - **No model forward pass** — just queue dequeue (~0 ms)

3. **Step 101**: Queue is depleted → new forward pass, new 100-action chunk

**Implications for 30 Hz control:**
- Every 100 steps (every ~3.33 seconds), one forward pass occurs.
- The offline benchmark shows **130 steps/s** throughput on GPU — at 30 Hz, only ~23% GPU utilization during inference steps.
- The 99 "free" steps between forward passes provide deterministic, zero-latency actions.

**Important:** Call `policy.reset()` when starting a new episode/task to clear the action queue and any temporal ensemble state.

### 2.7 MEAN_STD Normalization Details

The normalizer applies:

$$x_{\text{normalized}} = \frac{x - \mu}{\sigma + \epsilon}$$

The unnormalizer reverses:

$$x_{\text{original}} = x_{\text{normalized}} \cdot (\sigma + \epsilon) + \mu$$

Where $\epsilon = 10^{-8}$ and $\mu$, $\sigma$ are stored in the `.safetensors` state files, computed from the training dataset statistics.

---

## 3. Camera Integration

### 3.1 Requirements

- **Resolution:** 480 × 848 RGB
- **Frame rate:** 30 Hz (matching control frequency)
- **Output format:** NumPy array, shape `(480, 848, 3)`, dtype `uint8`

### 3.2 Option A: Intel RealSense (Recommended for Robotics)

```bash
pip install pyrealsense2
```

```python
import pyrealsense2 as rs
import numpy as np

class RealSenseCamera:
    def __init__(self, width=848, height=480, fps=30):
        self.pipeline = rs.pipeline()
        config = rs.config()
        config.enable_stream(rs.stream.color, width, height, rs.format.rgb8, fps)
        self.pipeline.start(config)

    def capture(self) -> np.ndarray:
        """Returns (480, 848, 3) uint8 RGB array."""
        frames = self.pipeline.wait_for_frames()
        color_frame = frames.get_color_frame()
        return np.asanyarray(color_frame.get_data())

    def close(self):
        self.pipeline.stop()
```

**Advantages:**

- Hardware-synchronized timestamps
- Depth stream available (future use)
- 848 is a native RealSense D400-series resolution (no rescaling needed)
- Global shutter option (D435i) reduces motion blur

### 3.3 Option B: USB Webcam via OpenCV

```bash
pip install opencv-python
```

```python
import cv2
import numpy as np

class USBCamera:
    def __init__(self, device_id=0, width=848, height=480, fps=30):
        self.cap = cv2.VideoCapture(device_id)
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        self.cap.set(cv2.CAP_PROP_FPS, fps)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # Minimize latency

    def capture(self) -> np.ndarray:
        """Returns (480, 848, 3) uint8 RGB array."""
        ret, frame = self.cap.read()
        if not ret:
            raise RuntimeError("Failed to capture frame")
        # OpenCV returns BGR → convert to RGB
        return cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

    def close(self):
        self.cap.release()
```

**Important considerations:**

- Most webcams don't natively support 848px width. Use 640×480 or 1280×720 and resize:

  ```python
  frame = cv2.resize(frame, (848, 480), interpolation=cv2.INTER_LINEAR)
  ```

- Set `CAP_PROP_BUFFERSIZE = 1` to avoid stale frames.
- USB bandwidth can be a bottleneck with multiple cameras.

### 3.4 Latency Comparison

| Camera | Typical Latency | Cost | Notes |
|--------|----------------|------|-------|
| RealSense D435/D435i | 30-50 ms | ~$300 | Best for robotics, native 848px |
| Logitech C920/C922 | 60-120 ms | ~$80 | Auto-exposure can add latency |
| FLIR/Basler industrial | 10-30 ms | $500+ | Lowest latency, SDK complexity |

---

## 4. Standalone Deployment Architecture

### 4.1 System Overview

```
┌─────────────────────────────────────────────────────────┐
│                  Control Loop (30 Hz)                    │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │  Camera   │→ │  Policy   │→ │  Safety  │→ │  RTDE  │ │
│  │ Capture   │  │ Inference │  │  Filter  │  │ Send   │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
│       ↑                                         │       │
│       │              ┌──────────┐               │       │
│       └──────────────│  RTDE    │←──────────────┘       │
│                      │ Receive  │                       │
│                      └──────────┘                       │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Complete Deployment Script

```python
#!/usr/bin/env python3
"""
Standalone UR10e ACT Policy Deployment (No ROS2)
Connects to UR10e via RTDE, captures camera images,
runs ACT policy inference, sends joint commands at 30 Hz.
"""

import time
import signal
import threading
import numpy as np
import torch
from copy import copy
from collections import deque
from dataclasses import dataclass, field
from rtde_control import RTDEControlInterface as RTDEControl
from rtde_receive import RTDEReceiveInterface as RTDEReceive

# Camera import — choose one:
import pyrealsense2 as rs  # Option A
# import cv2               # Option B


# ─── Configuration ────────────────────────────────────────

@dataclass
class DeploymentConfig:
    robot_ip: str = "192.168.2.102"
    checkpoint_dir: str = "./hve-robo-act-train"
    device: str = "cuda"
    control_hz: float = 30.0
    action_mode: str = "delta"  # "delta" or "absolute"

    # Camera
    camera_width: int = 848
    camera_height: int = 480
    camera_fps: int = 30

    # ServoJ tuning
    servo_lookahead: float = 0.1   # [0.03, 0.2] seconds
    servo_gain: float = 300        # [100, 2000]

    # Safety limits (conservative, tighten for your application)
    joint_pos_limits: list = field(default_factory=lambda: [
        (-2 * np.pi, 2 * np.pi),   # Base
        (-2 * np.pi, 2 * np.pi),   # Shoulder
        (-2 * np.pi, 2 * np.pi),   # Elbow
        (-2 * np.pi, 2 * np.pi),   # Wrist 1
        (-2 * np.pi, 2 * np.pi),   # Wrist 2
        (-2 * np.pi, 2 * np.pi),   # Wrist 3
    ])
    max_joint_delta: float = 0.05       # rad per step (~2.9°) at 30 Hz
    max_joint_velocity: float = 1.0     # rad/s
    max_tcp_velocity: float = 0.25      # m/s
    enable_watchdog: bool = True
    watchdog_freq: float = 10.0         # Hz


# ─── Safety Filter ────────────────────────────────────────

class SafetyFilter:
    """Pre-command safety checks for UR10e joint commands."""

    def __init__(self, config: DeploymentConfig):
        self.config = config
        self.prev_q = None
        self.violation_count = 0
        self.max_violations = 5  # consecutive violations before e-stop

    def check(self, current_q: np.ndarray, target_q: np.ndarray,
              dt: float) -> tuple[bool, np.ndarray, str]:
        """
        Returns: (is_safe, clamped_target_q, reason)
        """
        # 1. Joint position limits
        for i in range(6):
            lo, hi = self.config.joint_pos_limits[i]
            if target_q[i] < lo or target_q[i] > hi:
                target_q[i] = np.clip(target_q[i], lo, hi)

        # 2. Per-step delta limit
        delta = target_q - current_q
        max_delta = self.config.max_joint_delta
        if np.any(np.abs(delta) > max_delta):
            scale = max_delta / np.max(np.abs(delta))
            delta = delta * scale
            target_q = current_q + delta
            self.violation_count += 1
            if self.violation_count >= self.max_violations:
                return False, current_q, "MAX_VIOLATIONS_EXCEEDED"
            return True, target_q, f"DELTA_CLAMPED (max={np.max(np.abs(delta)):.4f})"

        # 3. Implied velocity check
        implied_vel = np.abs(delta) / dt
        if np.any(implied_vel > self.config.max_joint_velocity):
            scale = self.config.max_joint_velocity / np.max(implied_vel)
            delta = delta * scale
            target_q = current_q + delta
            return True, target_q, "VELOCITY_CLAMPED"

        self.violation_count = 0  # Reset on safe step
        return True, target_q, "OK"


# ─── Camera ──────────────────────────────────────────────

class RealSenseCamera:
    def __init__(self, width=848, height=480, fps=30):
        self.pipeline = rs.pipeline()
        config = rs.config()
        config.enable_stream(rs.stream.color, width, height,
                             rs.format.rgb8, fps)
        self.pipeline.start(config)
        # Warm up
        for _ in range(30):
            self.pipeline.wait_for_frames()

    def capture(self) -> np.ndarray:
        frames = self.pipeline.wait_for_frames()
        color_frame = frames.get_color_frame()
        if not color_frame:
            raise RuntimeError("No color frame")
        return np.asanyarray(color_frame.get_data())

    def close(self):
        self.pipeline.stop()


# ─── Policy Wrapper ──────────────────────────────────────

class ACTPolicyRunner:
    def __init__(self, checkpoint_dir: str, device: str = "cuda"):
        from lerobot.policies.act.modeling_act import ACTPolicy
        from lerobot.common.processors.pipeline import DataProcessorPipeline

        print(f"Loading ACT policy from {checkpoint_dir}...")
        self.policy = ACTPolicy.from_pretrained(checkpoint_dir)
        self.policy.to(device)
        self.policy.eval()

        self.preprocessor = DataProcessorPipeline.from_pretrained(
            checkpoint_dir,
            config_filename="policy_preprocessor.json"
        )
        self.postprocessor = DataProcessorPipeline.from_pretrained(
            checkpoint_dir,
            config_filename="policy_postprocessor.json"
        )
        self.device = torch.device(device)
        print("Policy loaded successfully.")

    def reset(self):
        """Call at the start of each episode to clear action queue."""
        self.policy.reset()

    @torch.inference_mode()
    def predict(self, joint_positions: np.ndarray,
                color_image: np.ndarray) -> np.ndarray:
        """
        Args:
            joint_positions: (6,) float32 array, radians
            color_image: (480, 848, 3) uint8 RGB

        Returns:
            action: (6,) float32 array, joint position deltas
        """
        # Build observation dict
        obs = {
            "observation.state": torch.from_numpy(
                joint_positions.astype(np.float32)
            ),
            "observation.images.color": torch.from_numpy(
                color_image
            ).permute(2, 0, 1).float() / 255.0,
        }

        # Preprocess (batch, device, normalize)
        batch = self.preprocessor(obs)

        # Inference
        action = self.policy.select_action(batch)

        # Postprocess (unnormalize, CPU)
        action = self.postprocessor(action)

        return action.squeeze(0).numpy()


# ─── Main Control Loop ──────────────────────────────────

class UR10eACTDeployment:
    def __init__(self, config: DeploymentConfig):
        self.config = config
        self.running = False
        self.dt = 1.0 / config.control_hz

        # Components (initialized in start())
        self.rtde_r = None
        self.rtde_c = None
        self.camera = None
        self.policy_runner = None
        self.safety = SafetyFilter(config)

        # Telemetry
        self.step_count = 0
        self.timing_history = deque(maxlen=100)

    def start(self):
        """Initialize all connections and begin control."""
        print("=" * 60)
        print("UR10e ACT Policy Deployment")
        print("=" * 60)

        # 1. Connect to robot
        print(f"Connecting to UR10e at {self.config.robot_ip}...")
        self.rtde_r = RTDEReceive(self.config.robot_ip)
        self.rtde_c = RTDEControl(self.config.robot_ip)
        print(f"  Robot mode: {self.rtde_r.getRobotMode()}")
        print(f"  Safety mode: {self.rtde_r.getSafetyMode()}")

        # 2. Initialize camera
        print("Initializing camera...")
        self.camera = RealSenseCamera(
            self.config.camera_width,
            self.config.camera_height,
            self.config.camera_fps
        )

        # 3. Load policy
        self.policy_runner = ACTPolicyRunner(
            self.config.checkpoint_dir,
            self.config.device
        )
        self.policy_runner.reset()

        # 4. Set watchdog
        if self.config.enable_watchdog:
            self.rtde_c.setWatchdog(self.config.watchdog_freq)

        # 5. Read initial state
        init_q = np.array(self.rtde_r.getActualQ())
        print(f"  Initial joints (deg): {np.degrees(init_q).round(1)}")

        # 6. Register interrupt handler
        signal.signal(signal.SIGINT, self._signal_handler)

        print(f"\nStarting control loop at {self.config.control_hz} Hz")
        print("Press Ctrl+C to stop\n")

        self.running = True
        self._control_loop()

    def _control_loop(self):
        """Main 30 Hz control loop."""
        try:
            while self.running:
                t_start = self.rtde_c.initPeriod()
                loop_start = time.perf_counter()

                # ── Step 1: Read robot state ──
                current_q = np.array(self.rtde_r.getActualQ())

                # ── Step 2: Check robot safety ──
                if self.rtde_r.isProtectiveStopped():
                    print("PROTECTIVE STOP — halting")
                    break
                if self.rtde_r.isEmergencyStopped():
                    print("EMERGENCY STOP — halting")
                    break

                # ── Step 3: Capture camera image ──
                color_image = self.camera.capture()

                # ── Step 4: Run policy inference ──
                action_delta = self.policy_runner.predict(
                    current_q, color_image
                )

                # ── Step 5: Compute target joint positions ──
                if self.config.action_mode == "delta":
                    target_q = current_q + action_delta
                else:
                    target_q = action_delta  # absolute mode

                # ── Step 6: Safety filter ──
                is_safe, target_q, reason = self.safety.check(
                    current_q, target_q, self.dt
                )

                if not is_safe:
                    print(f"SAFETY VIOLATION: {reason} — stopping")
                    break

                # ── Step 7: Send command to robot ──
                self.rtde_c.servoJ(
                    target_q.tolist(),
                    0, 0,  # speed, accel (unused by servoJ)
                    self.dt,
                    self.config.servo_lookahead,
                    self.config.servo_gain,
                )

                # ── Telemetry ──
                loop_time = time.perf_counter() - loop_start
                self.timing_history.append(loop_time)
                self.step_count += 1

                if self.step_count % 30 == 0:  # Print every ~1 second
                    avg_ms = np.mean(self.timing_history) * 1000
                    max_ms = np.max(self.timing_history) * 1000
                    print(
                        f"Step {self.step_count:5d} | "
                        f"loop: {avg_ms:.1f}ms avg, {max_ms:.1f}ms max | "
                        f"delta: {reason} | "
                        f"q: {np.degrees(current_q).round(1)}"
                    )

                # ── Wait for period ──
                self.rtde_c.waitPeriod(t_start)

        except Exception as e:
            print(f"\nERROR in control loop: {e}")
        finally:
            self._shutdown()

    def _shutdown(self):
        """Graceful shutdown."""
        print("\nShutting down...")
        self.running = False

        if self.rtde_c:
            try:
                self.rtde_c.servoStop()
                self.rtde_c.stopScript()
            except Exception:
                pass

        if self.camera:
            self.camera.close()

        if self.rtde_r:
            self.rtde_r.disconnect()
        if self.rtde_c:
            self.rtde_c.disconnect()

        print(f"Completed {self.step_count} steps.")
        if self.timing_history:
            print(
                f"Timing: {np.mean(self.timing_history)*1000:.1f}ms avg, "
                f"{np.max(self.timing_history)*1000:.1f}ms max"
            )

    def _signal_handler(self, sig, frame):
        print("\nCtrl+C received — stopping...")
        self.running = False


# ─── Entry Point ─────────────────────────────────────────

if __name__ == "__main__":
    config = DeploymentConfig(
        robot_ip="192.168.2.102",
        checkpoint_dir="./hve-robo-act-train",
        device="cuda",
        control_hz=30.0,
        action_mode="delta",
        servo_lookahead=0.1,
        servo_gain=300,
        max_joint_delta=0.05,    # ~2.9° per step at 30 Hz
        max_joint_velocity=1.0,  # rad/s
    )

    deployment = UR10eACTDeployment(config)
    deployment.start()
```

### 4.3 Dependencies

```
# requirements.txt
torch>=2.0
lerobot
safetensors
ur_rtde
pyrealsense2       # or: opencv-python
numpy
```

### 4.4 Safety Architecture

#### Layer 1: Software Safety Filter (Python)

- Per-step delta clamping (`max_joint_delta`)
- **Implied** velocity limiting
- Joint position limit enforcement
- Consecutive violation counter → auto-stop after N violations

#### Layer 2: ur_rtde Safety

- `isJointsWithinSafetyLimits()` pre-check
- Watchdog (auto-stop if communication drops below 10 Hz)
- `servoStop()` for graceful deceleration

#### Layer 3: UR Controller Safety

- Hardware joint limits (cannot be overridden by software)
- Protective stop on collision detection
- Safety planes defined in UR safety configuration
- Emergency stop via pendant or external I/O
- Speed/force limits defined in safety configuration

#### Layer 4: Physical E-Stop

- Always have the teach pendant within reach
- External E-stop circuit wired to safety I/O

### 4.5 Recommended Startup Procedure

1. **Power on** the robot via Dashboard or teach pendant.
2. **Verify** the robot is in `ROBOT_MODE_RUNNING` (mode 7).
3. Start the script with `enable_control=false` equivalent:
   - Run the loop but **log** predicted actions without sending them.
   - Verify predictions are reasonable (small deltas, within limits).
4. Enable control with **very conservative** `max_joint_delta` (e.g., 0.01 rad).
5. Gradually increase `max_joint_delta` as confidence grows.
6. Monitor `servo_gain` and `lookahead_time` for smooth tracking.

### 4.6 Timing Budget at 30 Hz (33.3 ms per cycle)

| Component | Typical Time | Notes |
|-----------|-------------|-------|
| `getActualQ()` | < 0.1 ms | RTDE read |
| Camera capture | 1-5 ms | Frame already buffered |
| Policy inference (cache hit) | < 0.1 ms | Action queue dequeue |
| Policy inference (forward pass) | 7-8 ms | Every 100 steps on GPU |
| Safety filter | < 0.1 ms | NumPy operations |
| `servoJ()` | < 0.5 ms | RTDE command send |
| **Total (typical)** | **~2-6 ms** | **Well within 33.3 ms budget** |
| **Total (forward pass step)** | **~9-14 ms** | **Still within budget** |

### 4.7 Key Tuning Parameters

| Parameter | Start Value | Range | Effect |
|-----------|-------------|-------|--------|
| `servo_gain` | 300 | 100-2000 | Higher → stiffer tracking, more overshoot |
| `servo_lookahead` | 0.1 | 0.03-0.2 | Higher → smoother but laggier |
| `max_joint_delta` | 0.02 | 0.005-0.1 | Safety clamp per 33ms step |
| `control_hz` | 30 | 10-500 | Must match policy training freq |

### 4.8 Error Recovery

```python
# After a protective stop:
dashboard = DashboardClient(ROBOT_IP)
dashboard.connect()
time.sleep(5)  # Must wait ≥5 seconds
dashboard.unlockProtectiveStop()
dashboard.closeSafetyPopup()

# Reconnect RTDE interfaces
rtde_c.reconnect()
rtde_r.reconnect()
```

---

## 5. Summary and Recommendations

### 5.1 Architecture Decision Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Robot interface | `ur_rtde` via RTDE | Official protocol, real-time capable, Python bindings |
| Control command | `servoJ` | Natural fit for position-delta policy output |
| Camera | Intel RealSense D435 | Native 848×480, low latency, USB3 |
| Inference device | CUDA GPU | 130 steps/s throughput, 7-8ms per forward pass |
| Control frequency | 30 Hz | Matches training frequency exactly |
| Safety strategy | 4-layer defense-in-depth | Software filter → RTDE checks → controller limits → physical E-stop |

### 5.2 Critical Safety Notes

1. **Never run a learned policy on a real robot without a proven safety filter and physical E-stop within reach.**
2. Start with `max_joint_delta = 0.01` (0.57°/step) and increase only after verifying behavior.
3. The policy was trained at 30 Hz — running at a different frequency will produce incorrect behavior.
4. Action deltas are added to **current** joint positions, not the previous command. This provides implicit drift correction.
5. Call `policy.reset()` at the start of each episode to clear the action queue.
6. Monitor `getSpeedScaling()` — if the teach pendant speed slider is not at 100%, servo motion will be scaled.

### 5.3 Pre-flight Checklist

- [ ] Robot is powered on and in `ROBOT_MODE_RUNNING`
- [ ] No active protective stops or safety violations
- [ ] Camera producing 480×848 RGB frames at 30 Hz
- [ ] Policy loaded and producing reasonable predictions on test data
- [ ] Safety filter configured with conservative limits
- [ ] E-stop pendant is within arm's reach
- [ ] Speed slider on teach pendant is at expected value
- [ ] Workspace is clear of obstacles not present during training
