"""Replay a rosbag recording directly on the UR10e robot.

Reads joint positions straight from a ROS 2 bag (SQLite .db3) and sends
them to the physical robot via RTDE servoJ — no LeRobot conversion needed.

The rosbag ``/joint_states`` topic is read, joints are reordered to the
standard UR10e order [base, shoulder, elbow, wrist1, wrist2, wrist3],
and optionally downsampled to a target replay rate.

Usage
-----
    # Inspect the bag
    python -m ur10e_deploy.rosbag_replay --bag ../rosbag-to-lerobot/temp_bag --info

    # Dry-run at original rate
    python -m ur10e_deploy.rosbag_replay --bag ../rosbag-to-lerobot/temp_bag

    # Replay on robot at half speed
    python -m ur10e_deploy.rosbag_replay --bag ../rosbag-to-lerobot/temp_bag --enable-control --speed-factor 0.5

    # Replay downsampled to 30 Hz
    python -m ur10e_deploy.rosbag_replay --bag ../rosbag-to-lerobot/temp_bag --enable-control --target-hz 30
"""

from __future__ import annotations

import argparse
import logging
import signal
import sys
import time
from pathlib import Path

import numpy as np

from .config import DeployConfig, load_config
from .robot import UR10eRTDE
from .safety import SafetyGuard

logger = logging.getLogger(__name__)

# Standard UR10e joint order expected by RTDE / safety / replay
STANDARD_JOINT_ORDER = [
    "shoulder_pan_joint",   # base
    "shoulder_lift_joint",  # shoulder
    "elbow_joint",          # elbow
    "wrist_1_joint",        # wrist1
    "wrist_2_joint",        # wrist2
    "wrist_3_joint",        # wrist3
]

JOINT_DISPLAY_NAMES = ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"]


def _build_reorder_map(bag_names: list[str]) -> list[int]:
    """Build index map from bag joint order → standard UR10e order.

    Returns a list where ``result[i]`` is the index in ``bag_names``
    that corresponds to ``STANDARD_JOINT_ORDER[i]``.
    """
    name_to_idx = {name: idx for idx, name in enumerate(bag_names)}
    reorder = []
    for std_name in STANDARD_JOINT_ORDER:
        if std_name not in name_to_idx:
            raise ValueError(
                f"Joint {std_name!r} not found in bag. "
                f"Available: {bag_names}"
            )
        reorder.append(name_to_idx[std_name])
    return reorder


class RosbagTrajectory:
    """Joint trajectory extracted from a ROS 2 bag file.

    Attributes
    ----------
    positions : np.ndarray
        Shape ``(N, 6)`` — joint positions in standard UR10e order, radians.
    timestamps_s : np.ndarray
        Shape ``(N,)`` — timestamps in seconds relative to the first sample.
    bag_hz : float
        Measured sample rate from the bag.
    duration_s : float
        Total duration in seconds.
    num_samples : int
        Number of joint samples.
    """

    def __init__(
        self,
        bag_path: str | Path,
        joint_topic: str = "/joint_states",
        ros_distro: str = "ROS2_HUMBLE",
    ) -> None:
        from rosbags.highlevel import AnyReader
        from rosbags.typesys import Stores, get_typestore

        typestore = get_typestore(Stores[ros_distro])
        bag_path = Path(bag_path)

        positions_raw: list[np.ndarray] = []
        timestamps_ns: list[int] = []
        reorder_map: list[int] | None = None

        with AnyReader([bag_path], default_typestore=typestore) as reader:
            self._topic_info = {
                c.topic: (c.msgtype, c.msgcount) for c in reader.connections
            }
            conns = [c for c in reader.connections if c.topic == joint_topic]
            if not conns:
                available = [c.topic for c in reader.connections]
                raise ValueError(
                    f"Topic {joint_topic!r} not found in bag. "
                    f"Available: {available}"
                )

            for conn, timestamp, rawdata in reader.messages(connections=conns):
                msg = reader.deserialize(rawdata, conn.msgtype)
                pos = np.array(msg.position, dtype=np.float64)
                if len(pos) != 6:
                    continue

                # Build reorder map from the first message's joint names
                if reorder_map is None:
                    bag_names = list(msg.name)
                    reorder_map = _build_reorder_map(bag_names)
                    logger.info(
                        "Bag joint order: %s → reorder map: %s",
                        bag_names, reorder_map,
                    )

                # Reorder to standard UR10e order
                positions_raw.append(pos[reorder_map])
                timestamps_ns.append(timestamp)

        if not positions_raw:
            raise ValueError(f"No joint state messages found on {joint_topic!r}")

        self.positions = np.array(positions_raw, dtype=np.float64)
        ts = np.array(timestamps_ns, dtype=np.int64)
        self.timestamps_s = (ts - ts[0]) / 1e9
        self.num_samples = len(self.positions)
        self.duration_s = self.timestamps_s[-1] if self.num_samples > 1 else 0.0
        self.bag_hz = self.num_samples / self.duration_s if self.duration_s > 0 else 0.0

        logger.info(
            "Loaded %d joint samples, %.1f s, %.1f Hz from %s",
            self.num_samples, self.duration_s, self.bag_hz, bag_path.name,
        )

    def downsample(self, target_hz: float) -> tuple[np.ndarray, float]:
        """Downsample the trajectory to a target rate.

        Uses nearest-neighbor selection at uniform time steps.

        Parameters
        ----------
        target_hz : float
            Desired output sample rate.

        Returns
        -------
        frames : np.ndarray
            Shape ``(M, 6)`` downsampled positions.
        dt : float
            Time step ``1 / target_hz``.
        """
        dt = 1.0 / target_hz
        t_out = np.arange(0, self.duration_s, dt)
        # Find nearest original sample for each output time
        indices = np.searchsorted(self.timestamps_s, t_out, side="right") - 1
        indices = np.clip(indices, 0, self.num_samples - 1)
        frames = self.positions[indices]
        logger.info(
            "Downsampled %d → %d frames (%.1f → %.1f Hz)",
            self.num_samples, len(frames), self.bag_hz, target_hz,
        )
        return frames, dt

    def print_info(self) -> None:
        """Print bag and trajectory summary."""
        print(f"\n  Bag topics:")
        for topic, (msgtype, count) in self._topic_info.items():
            print(f"    {topic:50s}  {msgtype:40s}  {count:5d} msgs")

        print(f"\n  Joint trajectory:")
        print(f"    Samples:   {self.num_samples}")
        print(f"    Duration:  {self.duration_s:.1f} s")
        print(f"    Rate:      {self.bag_hz:.1f} Hz")

        print(f"\n  Start position (RTDE, rad):")
        for j, name in enumerate(JOINT_DISPLAY_NAMES):
            print(f"    {name:10s}: {self.positions[0, j]:+.4f}  ({np.degrees(self.positions[0, j]):+.1f}°)")

        print(f"\n  End position (RTDE, rad):")
        for j, name in enumerate(JOINT_DISPLAY_NAMES):
            print(f"    {name:10s}: {self.positions[-1, j]:+.4f}  ({np.degrees(self.positions[-1, j]):+.1f}°)")

        # Delta statistics
        deltas = np.diff(self.positions, axis=0)
        dts = np.diff(self.timestamps_s)
        vels = deltas / dts[:, None]
        print(f"\n  Trajectory statistics:")
        print(f"    Max per-sample delta: {np.degrees(np.max(np.abs(deltas))):.2f}°")
        print(f"    Max joint velocity:   {np.max(np.abs(vels)):.3f} rad/s")
        print(f"    Mean joint velocity:  {np.mean(np.abs(vels)):.3f} rad/s")
        print()


class RosbagReplayer:
    """Replay a rosbag joint trajectory on the UR10e.

    Parameters
    ----------
    config : DeployConfig
        Robot and safety configuration.
    bag_path : str | Path
        Path to the rosbag directory.
    enable_control : bool
        If False, dry-run mode.
    speed_factor : float
        Playback speed multiplier.
    move_speed : float
        Joint speed for initial moveJ to start position.
    target_hz : float
        Replay sample rate. The bag is downsampled to this rate.
    """

    def __init__(
        self,
        config: DeployConfig,
        bag_path: str | Path,
        enable_control: bool = False,
        speed_factor: float = 1.0,
        move_speed: float = 0.3,
        target_hz: float = 30.0,
    ) -> None:
        self.cfg = config
        self.enable_control = enable_control
        self.speed_factor = max(0.01, min(speed_factor, 5.0))
        self.move_speed = move_speed
        self.target_hz = target_hz
        self._stop_requested = False

        # Load trajectory from bag
        self.trajectory = RosbagTrajectory(bag_path)
        self.robot: UR10eRTDE | None = None
        self.safety = SafetyGuard(config.robot)

    def request_stop(self) -> None:
        """Signal the replay loop to stop gracefully."""
        self._stop_requested = True

    def replay(self) -> None:
        """Replay the rosbag trajectory."""
        self._stop_requested = False

        # Downsample to target rate
        frames, dt = self.trajectory.downsample(self.target_hz)
        num_frames = len(frames)
        duration = num_frames * dt

        print(f"\n  Replay parameters:")
        print(f"    Source:       {self.trajectory.num_samples} samples at {self.trajectory.bag_hz:.1f} Hz")
        print(f"    Replay:       {num_frames} frames at {self.target_hz:.0f} Hz")
        print(f"    Duration:     {duration:.1f} s")
        print(f"    Speed factor: {self.speed_factor}x → effective {duration / self.speed_factor:.1f} s")
        print(f"    Control:      {'ENABLED — robot will move!' if self.enable_control else 'DRY-RUN (no robot commands)'}")

        # Preview positions
        print(f"\n  Start position (RTDE, rad):")
        for j, name in enumerate(JOINT_DISPLAY_NAMES):
            print(f"    {name:10s}: {frames[0, j]:+.4f}  ({np.degrees(frames[0, j]):+.1f}°)")
        print(f"\n  End position (RTDE, rad):")
        for j, name in enumerate(JOINT_DISPLAY_NAMES):
            print(f"    {name:10s}: {frames[-1, j]:+.4f}  ({np.degrees(frames[-1, j]):+.1f}°)")

        if self.enable_control:
            self._replay_on_robot(frames.astype(np.float32), dt)
        else:
            self._replay_dry_run(frames.astype(np.float32), dt)

    def _replay_on_robot(self, frames: np.ndarray, dt: float) -> None:
        """Execute replay on the physical robot."""
        num_frames = len(frames)

        print("\nConnecting to robot ...")
        self.robot = UR10eRTDE(self.cfg.robot)
        try:
            self.robot.connect()
        except Exception as e:
            print(f"ERROR: Failed to connect to robot: {e}")
            return

        try:
            if self.robot.is_protective_stopped():
                print("WARNING: Robot is in protective stop. Clear it first.")
                return

            current_q = self.robot.get_joint_positions()
            start_target = frames[0]

            dist = np.max(np.abs(current_q - start_target))
            print(f"\n  Current → Start distance: {np.degrees(dist):.1f}° (max joint)")

            if dist > 0.01:
                print(f"  Moving to start position at {self.move_speed:.2f} rad/s ...")
                input("  Press ENTER to move to start position (Ctrl+C to abort) ")
                self.robot.move_to(start_target, speed=self.move_speed, acceleration=0.2)
                print("  At start position.")
                time.sleep(0.5)

            self.safety.reset()
            self.safety.set_initial_q(start_target)
            self.safety.set_drift_watchdog_enabled(False)

            # Pre-analyze trajectory
            frame_deltas = np.diff(frames, axis=0)
            max_per_frame = np.max(np.abs(frame_deltas), axis=1)
            peak_delta = np.max(max_per_frame)
            peak_vel = peak_delta / dt
            fast_frames = int(np.sum(max_per_frame > self.cfg.robot.max_delta_rad))
            print(f"\n  Trajectory analysis:")
            print(f"    Peak per-frame delta: {np.degrees(peak_delta):.2f}° ({peak_vel:.2f} rad/s)")
            print(f"    Frames exceeding safety delta: {fast_frames}/{num_frames - 1}")

            input("\n  Press ENTER to start replay (Ctrl+C to stop) ")
            print(f"\n  Replaying {num_frames} frames ...")

            effective_dt = dt / self.speed_factor
            servo_dt = dt
            catch_up_threshold = self.cfg.robot.max_delta_rad * 3

            max_delta_rad = 0.0
            total_steps = 0
            total_time = 0.0
            skipped_total = 0

            i = 0
            while i < num_frames:
                if self._stop_requested:
                    print(f"\n  Stopped at frame {i}/{num_frames}")
                    break

                t_start = time.monotonic()
                current_q = self.robot.get_joint_positions()
                target = frames[i]

                # Frame-skipping catch-up
                tracking_error = np.max(np.abs(target - current_q))
                if tracking_error > catch_up_threshold and i < num_frames - 1:
                    best_i, best_err = i, tracking_error
                    for j in range(i + 1, min(i + 30, num_frames)):
                        err_j = np.max(np.abs(frames[j] - current_q))
                        if err_j < best_err:
                            best_err = err_j
                            best_i = j
                        if err_j > best_err + 0.01:
                            break
                    if best_i > i:
                        skipped_total += best_i - i
                        i = best_i
                        target = frames[i]

                safe_target = self.safety.clamp_action(target, current_q, servo_dt)

                if self.safety.drift_triggered:
                    print(f"\n  DRIFT WATCHDOG triggered at frame {i} — stopping!")
                    break

                if self.robot.is_protective_stopped():
                    print(f"\n  Protective stop detected at frame {i} — stopping!")
                    break

                self.robot.servo_joint(safe_target, dt=servo_dt)

                loop_dt = time.monotonic() - t_start
                delta = np.max(np.abs(safe_target - current_q))
                max_delta_rad = max(max_delta_rad, delta)
                total_steps += 1
                total_time += loop_dt

                if (i + 1) % (num_frames // 10 or 1) == 0 or i == num_frames - 1:
                    pct = (i + 1) / num_frames * 100
                    skip_msg = f"  skipped={skipped_total}" if skipped_total else ""
                    print(
                        f"    [{pct:5.1f}%] Frame {i + 1:5d}/{num_frames}  "
                        f"max_Δ={np.degrees(delta):.2f}°  "
                        f"loop={loop_dt * 1000:.1f}ms  "
                        f"violations={self.safety.violation_count}{skip_msg}"
                    )

                elapsed = time.monotonic() - t_start
                sleep_time = effective_dt - elapsed
                if sleep_time > 0:
                    time.sleep(sleep_time)

                i += 1

            self.robot.stop()

            if total_steps > 0:
                avg_dt = total_time / total_steps * 1000
                print(f"\n  Replay complete:")
                print(f"    Steps:          {total_steps}")
                print(f"    Total time:     {total_time:.1f} s")
                print(f"    Avg loop:       {avg_dt:.1f} ms")
                print(f"    Max joint Δ:    {np.degrees(max_delta_rad):.2f}°")
                print(f"    Safety clamps:  {self.safety.violation_count}")
                if skipped_total > 0:
                    print(f"    Frames skipped: {skipped_total}")

        except KeyboardInterrupt:
            print("\n  Keyboard interrupt — stopping robot.")
        finally:
            if self.robot is not None:
                self.robot.stop()
                self.robot.disconnect()
                print("  Robot disconnected.")

    def _replay_dry_run(self, frames: np.ndarray, dt: float) -> None:
        """Print replay targets without connecting to the robot."""
        num_frames = len(frames)

        print(f"\n  DRY-RUN: {num_frames} frames at {1 / dt:.0f} Hz "
              f"(speed {self.speed_factor}x)\n")

        step = max(1, num_frames // 20)
        prev = frames[0]
        effective_dt = dt / self.speed_factor

        for i in range(0, num_frames, step):
            if self._stop_requested:
                break
            target = frames[i]
            delta = target - prev
            max_delta = np.max(np.abs(delta))
            print(f"  Frame {i:5d}/{num_frames}  t={i * dt:.2f}s  max_Δ={np.degrees(max_delta):.2f}°")
            for j, name in enumerate(JOINT_DISPLAY_NAMES):
                print(f"    {name:10s}: {target[j]:+.4f} rad  ({np.degrees(target[j]):+.1f}°)")
            print()
            prev = target
            time.sleep(effective_dt * step)

        if not self._stop_requested and (num_frames - 1) % step != 0:
            target = frames[-1]
            max_delta = np.max(np.abs(target - prev))
            print(f"  Frame {num_frames - 1:5d}/{num_frames}  t={(num_frames - 1) * dt:.2f}s  max_Δ={np.degrees(max_delta):.2f}°")
            for j, name in enumerate(JOINT_DISPLAY_NAMES):
                print(f"    {name:10s}: {target[j]:+.4f} rad  ({np.degrees(target[j]):+.1f}°)")
            print()

        print("  DRY-RUN complete. Use --enable-control for real playback.\n")


def main() -> None:
    """CLI entry point for rosbag replay."""
    parser = argparse.ArgumentParser(
        description="Replay a rosbag recording directly on the UR10e robot.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--bag", "-b",
        type=str,
        required=True,
        help="Path to the rosbag directory (containing metadata.yaml and .db3 file).",
    )
    parser.add_argument(
        "--info",
        action="store_true",
        help="Print bag information and exit.",
    )
    parser.add_argument(
        "--joint-topic",
        type=str,
        default="/joint_states",
        help="Topic name for joint state messages. (default: /joint_states)",
    )
    parser.add_argument(
        "--config", "-c",
        type=str,
        default=None,
        help="Path to deploy.yaml config file (for robot/safety params).",
    )
    parser.add_argument(
        "--enable-control",
        action="store_true",
        help="Enable real robot control. Without this flag, runs in dry-run mode.",
    )
    parser.add_argument(
        "--speed-factor",
        type=float,
        default=1.0,
        help="Playback speed multiplier. (default: 1.0)",
    )
    parser.add_argument(
        "--move-speed",
        type=float,
        default=0.3,
        help="Joint speed (rad/s) for initial move to start position. (default: 0.3)",
    )
    parser.add_argument(
        "--target-hz",
        type=float,
        default=30.0,
        help="Target replay rate in Hz. Bag is downsampled to this rate. (default: 30)",
    )

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stdout,
    )

    # Load trajectory
    print(f"\nLoading rosbag: {args.bag}")
    traj = RosbagTrajectory(args.bag, joint_topic=args.joint_topic)

    if args.info:
        traj.print_info()
        return

    # Load config
    config_path = args.config
    if config_path is None:
        default_yaml = Path(__file__).resolve().parent.parent / "deploy.yaml"
        if default_yaml.exists():
            config_path = str(default_yaml)
            logger.info("Auto-loaded config from %s", default_yaml)
    cfg = load_config(config_path)

    replayer = RosbagReplayer(
        config=cfg,
        bag_path=args.bag,
        enable_control=args.enable_control,
        speed_factor=args.speed_factor,
        move_speed=args.move_speed,
        target_hz=args.target_hz,
    )

    def _sigint_handler(sig, frame):
        print("\n  Interrupt received — stopping ...")
        replayer.request_stop()

    signal.signal(signal.SIGINT, _sigint_handler)

    replayer.replay()


if __name__ == "__main__":
    main()
