"""Replay joint positions from temp_bag_data.json on the UR10e robot.

Reads the pre-extracted joint trajectory from the JSON file, reorders
joints to standard UR10e order, and sends them via RTDE servoJ.

Usage
-----
    # Dry-run (no robot commands)
    python replay_json_trajectory.py

    # Live replay at original speed
    python replay_json_trajectory.py --enable-control

    # Replay at half speed, 30 Hz
    python replay_json_trajectory.py --enable-control --speed-factor 0.5 --target-hz 30

    # Just print trajectory info
    python replay_json_trajectory.py --info
"""

from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
import time
from pathlib import Path

import numpy as np

logger = logging.getLogger(__name__)

# Standard UR10e joint order expected by RTDE
STANDARD_JOINT_ORDER = [
    "shoulder_pan_joint",   # base
    "shoulder_lift_joint",  # shoulder
    "elbow_joint",          # elbow
    "wrist_1_joint",        # wrist1
    "wrist_2_joint",        # wrist2
    "wrist_3_joint",        # wrist3
]

JOINT_DISPLAY_NAMES = ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"]

# Default robot IP — matches deploy.yaml
DEFAULT_ROBOT_IP = "192.168.2.102"

# Default JSON file path (sibling to this script)
DEFAULT_JSON_PATH = Path(__file__).resolve().parent / "temp_bag_data.json"


# ── Trajectory loader ─────────────────────────────────────────────────

def load_trajectory(json_path: str | Path) -> tuple[np.ndarray, np.ndarray, dict]:
    """Load joint positions from temp_bag_data.json.

    Returns
    -------
    positions : np.ndarray
        Shape ``(N, 6)`` — joint positions in standard UR10e order (rad).
    timestamps_s : np.ndarray
        Shape ``(N,)`` — timestamps in seconds relative to first sample.
    metadata : dict
        Source metadata (sample_count, duration, etc.).
    """
    json_path = Path(json_path)
    logger.info("Loading trajectory from %s ...", json_path)

    with open(json_path) as f:
        data = json.load(f)

    reorder_map = data["reorder_map"]  # bag order → standard order
    joint_states = data["joint_states"]

    positions = []
    timestamps_ns = []

    for state in joint_states:
        pos = np.array(state["position"], dtype=np.float64)
        # Reorder from bag joint order to standard UR10e order
        positions.append(pos[reorder_map])
        timestamps_ns.append(state["timestamp_ns"])

    positions = np.array(positions, dtype=np.float64)
    ts = np.array(timestamps_ns, dtype=np.int64)
    timestamps_s = (ts - ts[0]) / 1e9

    metadata = {
        "source": data.get("source", "unknown"),
        "sample_count": data.get("sample_count", len(positions)),
        "duration_seconds": data.get("duration_seconds", timestamps_s[-1]),
        "sample_rate_hz": data.get("sample_rate_hz", 0),
        "standard_joint_order": data.get("standard_joint_order", STANDARD_JOINT_ORDER),
    }

    logger.info(
        "Loaded %d samples, %.1f s, %.1f Hz",
        len(positions), timestamps_s[-1], metadata["sample_rate_hz"],
    )
    return positions, timestamps_s, metadata


def downsample(
    positions: np.ndarray,
    timestamps_s: np.ndarray,
    target_hz: float,
) -> tuple[np.ndarray, float]:
    """Downsample trajectory to a target rate using nearest-neighbor.

    Returns
    -------
    frames : np.ndarray  — shape ``(M, 6)``
    dt : float           — time step (seconds)
    """
    dt = 1.0 / target_hz
    t_out = np.arange(0, timestamps_s[-1], dt)
    indices = np.searchsorted(timestamps_s, t_out, side="right") - 1
    indices = np.clip(indices, 0, len(positions) - 1)
    frames = positions[indices]
    logger.info(
        "Downsampled %d → %d frames (%.1f → %.1f Hz)",
        len(positions), len(frames),
        len(positions) / timestamps_s[-1] if timestamps_s[-1] > 0 else 0,
        target_hz,
    )
    return frames, dt


# ── Robot interface (minimal, self-contained) ─────────────────────────

class UR10eConnection:
    """Minimal RTDE wrapper for trajectory replay.

    Only requires ``ur_rtde`` (pip install ur-rtde).
    """

    def __init__(self, ip: str, servo_lookahead: float = 0.1, servo_gain: int = 300):
        self.ip = ip
        self.servo_lookahead = servo_lookahead
        self.servo_gain = servo_gain
        self._ctrl = None
        self._recv = None

    def connect(self):
        import rtde_control
        import rtde_receive

        logger.info("Connecting to UR10e at %s ...", self.ip)
        self._recv = rtde_receive.RTDEReceiveInterface(self.ip)
        self._ctrl = rtde_control.RTDEControlInterface(self.ip)
        logger.info("Connected.")

    def disconnect(self):
        if self._ctrl is not None:
            try:
                self._ctrl.servoStop()
            except Exception:
                pass
            try:
                self._ctrl.stopScript()
            except Exception:
                pass
            self._ctrl = None
        self._recv = None

    def get_joint_positions(self) -> np.ndarray:
        return np.array(self._recv.getActualQ(), dtype=np.float64)

    def servo_joint(self, target: np.ndarray, dt: float):
        self._ctrl.servoJ(
            target.tolist(),
            0.0, 0.0, dt,
            self.servo_lookahead,
            self.servo_gain,
        )

    def move_to(self, target: np.ndarray, speed: float = 0.3, accel: float = 0.2):
        logger.info("moveJ to [%s] ...", ", ".join(f"{v:+.3f}" for v in target))
        self._ctrl.moveJ(target.tolist(), speed, accel)
        logger.info("moveJ complete.")

    def stop(self):
        if self._ctrl is not None:
            self._ctrl.servoStop()

    def is_protective_stopped(self) -> bool:
        return self._recv.isProtectiveStopped() if self._recv else False


# ── Safety clamp ──────────────────────────────────────────────────────

def clamp_delta(
    target: np.ndarray,
    current: np.ndarray,
    max_delta_rad: float = 0.05,
) -> np.ndarray:
    """Clamp per-step joint displacement to a maximum delta."""
    delta = target - current
    clamped = np.clip(delta, -max_delta_rad, max_delta_rad)
    return current + clamped


# ── Replay logic ──────────────────────────────────────────────────────

def print_info(positions: np.ndarray, timestamps_s: np.ndarray, metadata: dict):
    """Print trajectory summary."""
    n = len(positions)
    dur = timestamps_s[-1]
    hz = n / dur if dur > 0 else 0

    print(f"\n  Source:     {metadata['source']}")
    print(f"  Samples:    {n}")
    print(f"  Duration:   {dur:.1f} s")
    print(f"  Rate:       {hz:.1f} Hz")

    print(f"\n  Start position (standard UR10e order, rad):")
    for j, name in enumerate(JOINT_DISPLAY_NAMES):
        print(f"    {name:10s}: {positions[0, j]:+.4f}  ({np.degrees(positions[0, j]):+.1f}°)")

    print(f"\n  End position:")
    for j, name in enumerate(JOINT_DISPLAY_NAMES):
        print(f"    {name:10s}: {positions[-1, j]:+.4f}  ({np.degrees(positions[-1, j]):+.1f}°)")

    deltas = np.diff(positions, axis=0)
    dts = np.diff(timestamps_s)
    dts[dts == 0] = 1e-9
    vels = deltas / dts[:, None]

    print(f"\n  Statistics:")
    print(f"    Max per-sample delta: {np.degrees(np.max(np.abs(deltas))):.2f}°")
    print(f"    Max joint velocity:   {np.max(np.abs(vels)):.3f} rad/s")
    print(f"    Mean joint velocity:  {np.mean(np.abs(vels)):.3f} rad/s")
    print()


def replay_on_robot(
    frames: np.ndarray,
    dt: float,
    robot_ip: str,
    speed_factor: float,
    move_speed: float,
    max_delta_rad: float,
    stop_event: list,
):
    """Send trajectory frames to the UR10e via RTDE servoJ."""
    num_frames = len(frames)
    effective_dt = dt / speed_factor
    servo_dt = dt

    robot = UR10eConnection(robot_ip)
    try:
        robot.connect()
    except Exception as e:
        print(f"  ERROR: Cannot connect to robot at {robot_ip}: {e}")
        return

    try:
        if robot.is_protective_stopped():
            print("  WARNING: Robot in protective stop — clear it first.")
            return

        current_q = robot.get_joint_positions()
        start_target = frames[0]

        dist = np.max(np.abs(current_q - start_target))
        print(f"\n  Current → Start distance: {np.degrees(dist):.1f}° (max joint)")

        if dist > 0.01:  # > 0.6°
            print(f"  Will moveJ to start position at {move_speed:.2f} rad/s")
            input("  Press ENTER to move to start (Ctrl+C to abort) ")
            robot.move_to(start_target, speed=move_speed)
            time.sleep(0.5)

        input("  Press ENTER to begin replay (Ctrl+C to stop) ")
        print(f"\n  Replaying {num_frames} frames ...")

        max_delta_seen = 0.0
        violations = 0
        t_wall_start = time.monotonic()

        for i in range(num_frames):
            if stop_event:
                print(f"\n  Stopped at frame {i}/{num_frames}")
                break

            t_start = time.monotonic()
            current_q = robot.get_joint_positions()
            target = frames[i]

            # Safety clamp
            raw_delta = np.max(np.abs(target - current_q))
            safe_target = clamp_delta(target, current_q, max_delta_rad)
            if raw_delta > max_delta_rad:
                violations += 1

            max_delta_seen = max(max_delta_seen, raw_delta)

            if robot.is_protective_stopped():
                print(f"\n  Protective stop at frame {i} — aborting!")
                break

            robot.servo_joint(safe_target, dt=servo_dt)

            # Progress every 10 %
            if (i + 1) % max(1, num_frames // 10) == 0 or i == num_frames - 1:
                pct = (i + 1) / num_frames * 100
                elapsed = time.monotonic() - t_start
                print(
                    f"    [{pct:5.1f}%] Frame {i + 1:5d}/{num_frames}  "
                    f"max_Δ={np.degrees(raw_delta):.2f}°  "
                    f"violations={violations}"
                )

            sleep_time = effective_dt - (time.monotonic() - t_start)
            if sleep_time > 0:
                time.sleep(sleep_time)

        robot.stop()
        total_time = time.monotonic() - t_wall_start
        print(f"\n  Replay complete:")
        print(f"    Frames sent:    {num_frames}")
        print(f"    Wall time:      {total_time:.1f} s")
        print(f"    Max joint Δ:    {np.degrees(max_delta_seen):.2f}°")
        print(f"    Safety clamps:  {violations}")

    except KeyboardInterrupt:
        print("\n  Keyboard interrupt — stopping.")
    finally:
        robot.stop()
        robot.disconnect()
        print("  Robot disconnected.")


def replay_dry_run(frames: np.ndarray, dt: float, speed_factor: float, stop_event: list):
    """Print trajectory targets without connecting to the robot."""
    num_frames = len(frames)
    effective_dt = dt / speed_factor

    print(f"\n  DRY-RUN: {num_frames} frames, dt={dt * 1000:.1f} ms, "
          f"speed={speed_factor}x\n")

    step = max(1, num_frames // 20)
    prev = frames[0]

    for i in range(0, num_frames, step):
        if stop_event:
            break
        target = frames[i]
        max_delta = np.max(np.abs(target - prev))
        print(f"  Frame {i:5d}/{num_frames}  t={i * dt:.2f}s  "
              f"max_Δ={np.degrees(max_delta):.2f}°")
        for j, name in enumerate(JOINT_DISPLAY_NAMES):
            print(f"    {name:10s}: {target[j]:+.4f} rad  ({np.degrees(target[j]):+.1f}°)")
        print()
        prev = target
        time.sleep(effective_dt * step)

    print("  DRY-RUN complete. Use --enable-control for live replay.\n")


# ── CLI ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Replay temp_bag_data.json joint positions on the UR10e.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--json", "-j",
        type=str,
        default=str(DEFAULT_JSON_PATH),
        help=f"Path to the JSON trajectory file. (default: {DEFAULT_JSON_PATH.name})",
    )
    parser.add_argument(
        "--info",
        action="store_true",
        help="Print trajectory info and exit.",
    )
    parser.add_argument(
        "--robot-ip",
        type=str,
        default=DEFAULT_ROBOT_IP,
        help=f"UR10e IP address. (default: {DEFAULT_ROBOT_IP})",
    )
    parser.add_argument(
        "--enable-control",
        action="store_true",
        help="Send commands to the real robot. Without this, runs dry-run.",
    )
    parser.add_argument(
        "--speed-factor",
        type=float,
        default=1.0,
        help="Playback speed multiplier. (default: 1.0)",
    )
    parser.add_argument(
        "--target-hz",
        type=float,
        default=30.0,
        help="Replay rate in Hz after downsampling. (default: 30)",
    )
    parser.add_argument(
        "--move-speed",
        type=float,
        default=0.3,
        help="Joint speed (rad/s) for initial moveJ. (default: 0.3)",
    )
    parser.add_argument(
        "--max-delta",
        type=float,
        default=0.05,
        help="Max per-step joint delta in rad (~2.86°). (default: 0.05)",
    )

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stdout,
    )

    # Load trajectory
    positions, timestamps_s, metadata = load_trajectory(args.json)

    if args.info:
        print_info(positions, timestamps_s, metadata)
        return

    # Downsample
    frames, dt = downsample(positions, timestamps_s, args.target_hz)
    num_frames = len(frames)
    duration = num_frames * dt
    speed_factor = max(0.01, min(args.speed_factor, 5.0))

    print(f"\n  Trajectory: {metadata['source']}")
    print(f"  Original:   {len(positions)} samples at {metadata['sample_rate_hz']:.1f} Hz")
    print(f"  Replay:     {num_frames} frames at {args.target_hz:.0f} Hz")
    print(f"  Duration:   {duration:.1f} s  (×{speed_factor} → {duration / speed_factor:.1f} s wall)")
    print(f"  Control:    {'ENABLED — robot will move!' if args.enable_control else 'DRY-RUN'}")

    # Graceful stop via Ctrl+C
    stop_event: list[bool] = []

    def _sigint(sig, frame):
        print("\n  Interrupt — stopping ...")
        stop_event.append(True)

    signal.signal(signal.SIGINT, _sigint)

    if args.enable_control:
        replay_on_robot(
            frames=frames.astype(np.float64),
            dt=dt,
            robot_ip=args.robot_ip,
            speed_factor=speed_factor,
            move_speed=args.move_speed,
            max_delta_rad=args.max_delta,
            stop_event=stop_event,
        )
    else:
        replay_dry_run(frames.astype(np.float64), dt, speed_factor, stop_event)


if __name__ == "__main__":
    main()
