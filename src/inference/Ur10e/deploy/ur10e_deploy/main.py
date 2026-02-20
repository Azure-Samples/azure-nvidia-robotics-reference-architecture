"""Main control loop — ties together robot, camera, policy, and safety.

Usage
-----
Dry-run (no robot commands)::

    python -m ur10e_deploy.main --config deploy.yaml

Live control (sends commands to the robot)::

    python -m ur10e_deploy.main --config deploy.yaml --enable-control

"""

from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np

from .camera import create_camera
from .config import DeployConfig, load_config
from .dashboard import start_dashboard
from .policy_runner import PolicyRunner, _wrap_to_pi
from .robot import UR10eRTDE
from .safety import SafetyGuard
from .telemetry import StepRecord, TelemetryStore

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Joint convention adapter
# ---------------------------------------------------------------------------
# The training data uses a different sign convention for shoulder (j1)
# and elbow (j2) compared to what UR RTDE reports.  This mask is
# applied element-wise: multiply RTDE values to get training-convention
# values, and vice-versa (the mask is its own inverse).
# ---------------------------------------------------------------------------
_JOINT_SIGN = np.array([1.0, -1.0, -1.0, 1.0, 1.0, 1.0], dtype=np.float32)


def rtde_to_policy(q: np.ndarray) -> np.ndarray:
    """Convert RTDE joint positions to training convention (negate shoulder/elbow)."""
    return q * _JOINT_SIGN


def policy_to_rtde_delta(delta: np.ndarray) -> np.ndarray:
    """Convert a policy action delta to RTDE convention (negate shoulder/elbow)."""
    return delta * _JOINT_SIGN


# Training-mean home position **in training convention** (from preprocessor).
TRAINING_HOME_Q = np.array([
    -1.529079,   # base
     2.133681,   # shoulder  (training convention)
    -2.233993,   # elbow     (training convention)
    -1.552526,   # wrist1
    -1.437930,   # wrist2
    -0.149820,   # wrist3
])

# Same position in RTDE convention (for moveJ commands).
RTDE_HOME_Q = TRAINING_HOME_Q * _JOINT_SIGN

TRAINING_STD_Q = np.array([
    0.157801,
    0.174243,
    0.073973,
    0.051418,
    1.276485,
    0.167053,
])

JOINT_NAMES = ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"]


def _check_ood(current_q: np.ndarray, threshold_z: float = 3.0) -> None:
    """Log a warning for each joint whose position is far from training mean.

    Parameters
    ----------
    current_q : np.ndarray
        Raw RTDE joint positions (radians).
    threshold_z : float
        Number of standard deviations beyond which a joint is flagged.
    """
    converted = _wrap_to_pi(rtde_to_policy(current_q))
    z_scores = (converted - TRAINING_HOME_Q) / TRAINING_STD_Q
    any_ood = False
    for j, name in enumerate(JOINT_NAMES):
        z = z_scores[j]
        if abs(z) > threshold_z:
            any_ood = True
            logger.warning(
                "OOD  %-10s: policy_conv=%.3f rad  train_mean=%.3f  z=%+.1f",
                name, converted[j], TRAINING_HOME_Q[j], z,
            )
    if any_ood:
        logger.warning(
            "One or more joints are far from the training distribution. "
            "Consider using --home to move to the training home position."
        )
    else:
        logger.info("All joints within %.0f\u03c3 of training distribution.", threshold_z)

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------

_shutdown_requested = False


def _signal_handler(signum, frame):
    global _shutdown_requested
    _shutdown_requested = True
    logger.info("Shutdown requested (signal %d)", signum)


# ---------------------------------------------------------------------------
# Control loop
# ---------------------------------------------------------------------------


def run_episode(
    robot: UR10eRTDE,
    camera,
    policy: PolicyRunner,
    safety: SafetyGuard,
    cfg: DeployConfig,
    telemetry: TelemetryStore | None = None,
) -> dict:
    """Run a single inference episode.

    Returns
    -------
    dict
        Episode statistics (steps, duration, violations, etc.).
    """
    global _shutdown_requested

    dt = 1.0 / cfg.control_hz
    step = 0
    log_data: list[dict] = []

    policy.reset()
    safety.reset()

    logger.info(
        "Starting episode — control_hz=%.0f  enable_control=%s  max_steps=%d",
        cfg.control_hz,
        cfg.enable_control,
        cfg.max_episode_steps,
    )

    telemetry_active = telemetry is not None
    if telemetry_active:
        telemetry.set_episode_active(True)

    t_episode_start = time.monotonic()

    try:
        while step < cfg.max_episode_steps and not _shutdown_requested:
            t_loop_start = time.monotonic()

            # --- 1. Read robot state ---
            joint_state = robot.get_joint_state()
            current_q = joint_state.positions

            # Record initial position for drift tracking
            if step == 0 and telemetry_active:
                telemetry.set_initial_q(current_q)
            if step == 0:
                safety.set_initial_q(current_q)

            # --- 2. Capture image ---
            try:
                image = camera.grab_rgb()
            except RuntimeError:
                logger.warning("Camera frame dropped at step %d — reusing last image", step)
                if "image" not in dir() or image is None:
                    logger.error("No previous frame available — skipping step")
                    step += 1
                    continue

            # Stream camera frame to dashboard
            if telemetry_active:
                telemetry.record_image(image)

            # --- 3. Run policy ---
            # Convert RTDE joint angles to training convention
            # (negate shoulder/elbow) before feeding to policy.
            policy_q = rtde_to_policy(current_q)
            t_infer = time.monotonic()
            action = policy.predict(policy_q, image)
            inference_dt = (time.monotonic() - t_infer) * 1000  # ms

            # --- 4. Compute target ---
            if cfg.policy.action_mode == "delta":
                # Action delta is in training convention — convert back
                # to RTDE convention before applying to RTDE positions.
                rtde_delta = policy_to_rtde_delta(action)
                target_q = current_q + rtde_delta
            else:
                target_q = action

            pre_clamp = target_q.copy()

            # --- 5. Safety clamp ---
            safe_target = safety.clamp_action(target_q, current_q, dt)
            was_clamped = not np.allclose(pre_clamp, safe_target)

            # --- 6. Send command ---
            if cfg.enable_control:
                robot.servo_joint(safe_target, dt)
            else:
                pass  # Dry-run — no commands sent

            # --- 7. Check robot safety ---
            if robot.is_protective_stopped() or robot.is_emergency_stopped():
                logger.error("Robot safety stop detected — aborting episode")
                break

            if safety.drift_triggered:
                logger.error("Drift watchdog triggered — aborting episode")
                break

            # --- 8. Timing measurement ---
            elapsed = time.monotonic() - t_loop_start
            loop_dt_ms = elapsed * 1000

            # --- 9. Telemetry ---
            if telemetry_active:
                record = StepRecord(
                    step=step,
                    timestamp=time.monotonic() - t_episode_start,
                    current_q=current_q.tolist(),
                    target_q=safe_target.tolist(),
                    raw_action=action.tolist(),
                    was_clamped=was_clamped,
                    pre_clamp_target=pre_clamp.tolist(),
                    loop_dt_ms=loop_dt_ms,
                    inference_dt_ms=inference_dt,
                    buffer_depth=policy.buffer_size,
                )
                telemetry.record_step(record)

                # Normalization diagnostics (emitted by policy_runner)
                if policy.last_norm_input is not None:
                    telemetry.record_norm_diagnostics(
                        input_state=policy.last_norm_input,
                        output_action=action.tolist(),
                    )

            # --- 10. Logging ---
            entry = {
                "step": step,
                "timestamp": time.monotonic() - t_episode_start,
                "current_q": current_q.tolist(),
                "action": action.tolist(),
                "target_q": safe_target.tolist(),
                "buffer_depth": policy.buffer_size,
            }
            log_data.append(entry)

            if step % 30 == 0:
                logger.info(
                    "Step %4d | q=[%s] | buf=%d",
                    step,
                    ", ".join(f"{v:+.3f}" for v in current_q),
                    policy.buffer_size,
                )

            # --- 11. Timing ---
            sleep_time = dt - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)
            elif sleep_time < -0.005:
                logger.warning(
                    "Loop overrun: %.1f ms (budget %.1f ms)",
                    elapsed * 1000,
                    dt * 1000,
                )

            step += 1

    except KeyboardInterrupt:
        logger.info("Episode interrupted by user")

    if telemetry_active:
        telemetry.set_episode_active(False)

    duration = time.monotonic() - t_episode_start
    stats = {
        "steps": step,
        "duration_s": round(duration, 2),
        "avg_hz": round(step / duration, 1) if duration > 0 else 0,
        "safety_violations": safety.violation_count,
        "enable_control": cfg.enable_control,
    }

    # Save log
    log_dir = Path(cfg.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = log_dir / f"episode_{ts}.json"
    with open(log_path, "w") as f:
        json.dump({"stats": stats, "steps": log_data}, f, indent=2)
    logger.info("Episode log saved to %s", log_path)

    return stats


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Deploy ACT policy on UR10e via RTDE"
    )
    parser.add_argument(
        "--config", type=str, default=None,
        help="Path to YAML config file (optional, uses defaults otherwise)",
    )
    parser.add_argument(
        "--enable-control", action="store_true",
        help="Enable live robot control (default: dry-run)",
    )
    parser.add_argument(
        "--checkpoint", type=str, default=None,
        help="Override policy checkpoint directory",
    )
    parser.add_argument(
        "--device", type=str, default=None,
        help="Override inference device (cuda, cpu, mps)",
    )
    parser.add_argument(
        "--robot-ip", type=str, default=None,
        help="Override robot IP address",
    )
    parser.add_argument(
        "--dashboard-port", type=int, default=5000,
        help="Dashboard HTTP port (default: 5000)",
    )
    parser.add_argument(
        "--no-dashboard", action="store_true",
        help="Disable the web dashboard",
    )
    parser.add_argument(
        "--home", action="store_true",
        help="Move robot to training home position before starting episode",
    )
    parser.add_argument(
        "--home-speed", type=float, default=0.3,
        help="Joint speed for home move in rad/s (default: 0.3)",
    )
    args = parser.parse_args()

    # Logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    # Config
    cfg = load_config(args.config)
    if args.enable_control:
        cfg.enable_control = True
    if args.checkpoint:
        cfg.policy.checkpoint_dir = args.checkpoint
    if args.device:
        cfg.policy.device = args.device
    if args.robot_ip:
        cfg.robot.ip = args.robot_ip

    # Signal handling
    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)

    # --- Initialize components ---
    logger.info("=" * 60)
    logger.info("UR10e ACT Policy Deployment")
    logger.info("=" * 60)
    logger.info("Robot IP     : %s", cfg.robot.ip)
    logger.info("Control Hz   : %.0f", cfg.control_hz)
    logger.info("Enable ctrl  : %s", cfg.enable_control)
    logger.info("Checkpoint   : %s", cfg.policy.checkpoint_dir)
    logger.info("Device       : %s", cfg.policy.device)
    logger.info("Action mode  : %s", cfg.policy.action_mode)
    logger.info("=" * 60)

    if cfg.enable_control:
        logger.warning(
            "LIVE CONTROL ENABLED — robot WILL move. "
            "Ensure workspace is clear and E-stop is accessible."
        )
        logger.info("Starting in 5 seconds ... press Ctrl+C to abort")
        time.sleep(5)

    # 0. Create telemetry store & launch dashboard
    telemetry = TelemetryStore()
    if not args.no_dashboard:
        dash_thread = start_dashboard(telemetry, port=args.dashboard_port)
        logger.info("Dashboard available at http://localhost:%d", args.dashboard_port)
    else:
        telemetry = TelemetryStore()  # still track data for logging

    # 1. Load policy
    policy = PolicyRunner(cfg.policy)
    policy.load()
    telemetry.set_status(policy_loaded=True)

    # 2. Connect to robot
    robot = UR10eRTDE(cfg.robot)
    robot.connect()
    telemetry.set_status(robot_connected=True)

    # 3. Start camera
    camera = create_camera(cfg.camera)
    camera.start()
    telemetry.set_status(camera_connected=True)

    # Grab an initial frame so the dashboard has something to show
    # before the episode loop begins.
    try:
        init_frame = camera.grab_rgb()
        telemetry.record_image(init_frame)
        logger.info(
            "Initial camera frame captured: %d×%d",
            init_frame.shape[1], init_frame.shape[0],
        )
    except Exception as exc:
        logger.warning("Could not grab initial camera frame: %s", exc)

    # 4. Set control status
    telemetry.set_status(control_enabled=cfg.enable_control)

    # 4. Create safety guard
    safety = SafetyGuard(cfg.robot)

    try:
        # Read and display initial joint state
        init_state = robot.get_joint_state()
        logger.info(
            "Initial joints: [%s]",
            ", ".join(f"{v:+.4f}" for v in init_state.positions),
        )
        logger.info(
            "Wrapped joints: [%s]",
            ", ".join(f"{v:+.4f}" for v in _wrap_to_pi(init_state.positions)),
        )
        _check_ood(init_state.positions)

        # Move to training home position if requested
        if args.home:
            logger.info("Moving to training home position ...")
            logger.info(
                "Home target (RTDE): [%s]",
                ", ".join(f"{v:+.4f}" for v in RTDE_HOME_Q),
            )
            robot.move_to(RTDE_HOME_Q, speed=args.home_speed)
            # Re-read and verify
            init_state = robot.get_joint_state()
            logger.info(
                "Post-home joints: [%s]",
                ", ".join(f"{v:+.4f}" for v in init_state.positions),
            )
            _check_ood(init_state.positions)

        # Run episode
        stats = run_episode(robot, camera, policy, safety, cfg, telemetry=telemetry)
        logger.info("Episode complete: %s", stats)

    finally:
        # Cleanup — always release resources even on error.
        # Each stop/disconnect is protected individually so a failure
        # in one does not prevent cleanup of the others.
        logger.info("Shutting down ...")
        try:
            robot.stop()
        except Exception as exc:
            logger.debug("Robot stop error: %s", exc)
        try:
            camera.stop()
        except Exception as exc:
            logger.debug("Camera stop error: %s", exc)
        telemetry.set_status(camera_connected=False)
        try:
            robot.disconnect()
        except Exception as exc:
            logger.debug("Robot disconnect error: %s", exc)
        telemetry.set_status(robot_connected=False)
        logger.info("Shutdown complete")


if __name__ == "__main__":
    main()
