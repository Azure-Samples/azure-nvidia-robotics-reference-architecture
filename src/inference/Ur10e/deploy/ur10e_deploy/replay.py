"""Replay a LeRobot episode on the UR10e robot.

Reads recorded joint positions from a LeRobot dataset and sends them
to the physical robot via RTDE servoJ at the original recording rate.

Usage
-----
    # List available episodes
    python -m ur10e_deploy.replay --dataset ../rosbag-to-lerobot/output --list

    # Replay episode 0 (dry-run — print targets only)
    python -m ur10e_deploy.replay --dataset ../rosbag-to-lerobot/output --episode 0

    # Replay episode 0 on the real robot
    python -m ur10e_deploy.replay --dataset ../rosbag-to-lerobot/output --episode 0 --enable-control

    # Replay at half speed
    python -m ur10e_deploy.replay --dataset ../rosbag-to-lerobot/output --episode 0 --enable-control --speed-factor 0.5
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
from .dataset_reader import LeRobotDatasetReader
from .replay_dashboard import ReplayState, start_replay_dashboard
from .robot import UR10eRTDE
from .safety import SafetyGuard

logger = logging.getLogger(__name__)

# Joint sign mask: converts LeRobot training convention → RTDE convention.
# Shoulder (j1) and elbow (j2) are negated.  Mask is self-inverse.
SIGN_MASK = np.array([1.0, -1.0, -1.0, 1.0, 1.0, 1.0], dtype=np.float32)

# Known RTDE home position for convention detection.
_RTDE_HOME = np.array([-1.529, -2.134, +2.234, -1.553, -1.438, -0.150])
_TRAIN_HOME = np.array([-1.529, +2.134, -2.234, -1.553, -1.438, -0.150])


def _training_to_rtde(positions: np.ndarray) -> np.ndarray:
    """Convert joint positions from training convention to RTDE convention."""
    return positions * SIGN_MASK


def _wrap_to_pi(angles: np.ndarray) -> np.ndarray:
    """Wrap angles to (-pi, pi]."""
    return np.arctan2(np.sin(angles), np.cos(angles))


def detect_convention(first_frame: np.ndarray) -> str:
    """Auto-detect whether dataset joint values are in RTDE or training convention.

    Compares the shoulder (j1) and elbow (j2) signs against known home positions.

    Returns
    -------
    str
        "rtde" if data appears to be in RTDE convention,
        "training" if data appears to be in training convention.
    """
    shoulder, elbow = first_frame[1], first_frame[2]
    dist_rtde = abs(shoulder - _RTDE_HOME[1]) + abs(elbow - _RTDE_HOME[2])
    dist_train = abs(shoulder - _TRAIN_HOME[1]) + abs(elbow - _TRAIN_HOME[2])
    detected = "rtde" if dist_rtde < dist_train else "training"
    logger.info(
        "Convention auto-detect: shoulder=%.3f elbow=%.3f → "
        "dist_rtde=%.3f dist_train=%.3f → %s",
        shoulder, elbow, dist_rtde, dist_train, detected,
    )
    return detected


class EpisodeReplayer:
    """Replay recorded joint trajectories on the UR10e.

    Parameters
    ----------
    config : DeployConfig
        Robot and safety configuration.
    dataset_dir : str | Path
        Path to the LeRobot dataset root.
    enable_control : bool
        If False, run in dry-run mode (print targets, don't send commands).
    speed_factor : float
        Playback speed multiplier. 1.0 = original speed, 0.5 = half speed.
    move_speed : float
        Joint speed (rad/s) for the initial moveJ to the start position.
    """

    def __init__(
        self,
        config: DeployConfig,
        dataset_dir: str | Path,
        enable_control: bool = False,
        speed_factor: float = 1.0,
        move_speed: float = 0.3,
        replay_state: ReplayState | None = None,
        convention: str = "auto",
    ) -> None:
        self.cfg = config
        self.enable_control = enable_control
        self.speed_factor = max(0.01, min(speed_factor, 5.0))
        self.move_speed = move_speed
        self._stop_requested = False
        self._convention = convention  # "auto", "rtde", or "training"

        # Load dataset
        self.dataset = LeRobotDatasetReader(dataset_dir)
        self.robot: UR10eRTDE | None = None
        self.safety = SafetyGuard(config.robot)

        # Dashboard state — shared with the web UI
        self.state = replay_state or ReplayState()
        self.state.update(
            speed_factor=self.speed_factor,
            enable_control=self.enable_control,
        )

    def request_stop(self) -> None:
        """Signal the replay loop to stop gracefully."""
        self._stop_requested = True

    def list_episodes(self) -> None:
        """Print all available episodes to stdout."""
        info = self.dataset.info
        print(f"\nDataset: {self.dataset.root}")
        print(f"Robot: {info.robot_type}  |  FPS: {info.fps}  |  Total frames: {info.total_frames}")
        print(f"\n{'Ep':>4}  {'Frames':>7}  {'Duration':>10}  Task")
        print("-" * 55)
        for ep in self.dataset.episodes:
            duration = ep.length / info.fps
            print(f"{ep.index:4d}  {ep.length:7d}  {duration:8.1f} s  {ep.task}")
        print()

    def replay(self, episode_index: int) -> None:
        """Replay a single episode.

        Parameters
        ----------
        episode_index : int
            Which episode to replay.
        """
        self._stop_requested = False
        fps = self.dataset.info.fps
        dt = 1.0 / fps

        # Load episode data
        print(f"\nLoading episode {episode_index} ...")
        frames = self.dataset.get_episode_frames(episode_index)
        num_frames = len(frames)
        duration = num_frames / fps

        print(f"  Frames: {num_frames}")
        print(f"  Duration: {duration:.1f} s at {fps} Hz")
        print(f"  Speed factor: {self.speed_factor}x → effective {duration / self.speed_factor:.1f} s")
        print(f"  Control: {'ENABLED — robot will move!' if self.enable_control else 'DRY-RUN (no robot commands)'}")

        # Detect or use specified convention
        convention = self._convention
        if convention == "auto":
            convention = detect_convention(frames[0])
        print(f"  Convention: {convention} (source: {self._convention})")

        # Convert frames to RTDE convention if needed
        if convention == "training":
            rtde_frames = np.array([_training_to_rtde(f) for f in frames])
            print("  Applied sign flip: training → RTDE")
        else:
            rtde_frames = np.array(frames, dtype=np.float32)
            print("  No sign flip needed: data is already in RTDE convention")

        # Update dashboard state
        self.state.update(
            current_episode=episode_index,
            total_frames=num_frames,
            current_frame=0,
        )

        # Preview start and end positions
        joint_names = ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"]
        print(f"\n  Start position (RTDE, rad):")
        for j, name in enumerate(joint_names):
            print(f"    {name:10s}: {rtde_frames[0, j]:+.4f}  ({np.degrees(rtde_frames[0, j]):+.1f}°)")
        print(f"\n  End position (RTDE, rad):")
        for j, name in enumerate(joint_names):
            print(f"    {name:10s}: {rtde_frames[-1, j]:+.4f}  ({np.degrees(rtde_frames[-1, j]):+.1f}°)")

        if self.enable_control:
            self._replay_on_robot(rtde_frames, dt)
        else:
            self._replay_dry_run(rtde_frames, dt)

        self.state.update(is_playing=False)

    def _replay_on_robot(self, frames: np.ndarray, dt: float) -> None:
        """Execute replay on the physical robot."""
        num_frames = len(frames)

        # Connect to robot
        print("\nConnecting to robot ...")
        self.state.add_message("Connecting to robot...")
        self.robot = UR10eRTDE(self.cfg.robot)
        try:
            self.robot.connect()
            self.state.update(is_connected=True)
            self.state.add_message("Robot connected")
        except Exception as e:
            print(f"ERROR: Failed to connect to robot: {e}")
            self.state.add_message(f"Connection failed: {e}")
            return

        try:
            # Check for protective stop
            if self.robot.is_protective_stopped():
                print("WARNING: Robot is in protective stop. Clear it first.")
                return

            # Read current position
            current_q = self.robot.get_joint_positions()
            start_target = frames[0]

            # Check how far we are from the start
            dist = np.max(np.abs(current_q - start_target))
            print(f"\n  Current → Start distance: {np.degrees(dist):.1f}° (max joint)")

            if dist > 0.01:  # More than ~0.6 degrees away
                print(f"  Moving to start position at {self.move_speed:.2f} rad/s ...")
                input("  Press ENTER to move to start position (Ctrl+C to abort) ")
                self.robot.move_to(start_target, speed=self.move_speed, acceleration=0.2)
                print("  At start position.")
                time.sleep(0.5)

            # Initialize safety with the start position
            self.safety.reset()
            self.safety.set_initial_q(start_target)
            # Disable drift watchdog for replay — the trajectory is
            # recorded human demo data and may legitimately exceed the
            # drift limit.  Delta clamping, position limits, and
            # velocity limits still provide safety.
            self.safety.set_drift_watchdog_enabled(False)

            # Pre-analyze trajectory to report velocity demands
            frame_deltas = np.diff(frames, axis=0)  # (N-1, 6)
            max_per_frame = np.max(np.abs(frame_deltas), axis=1)  # (N-1,)
            peak_delta = np.max(max_per_frame)
            peak_vel = peak_delta / dt
            mean_delta = np.mean(max_per_frame)
            fast_frames = int(np.sum(max_per_frame > self.cfg.robot.max_delta_rad))
            print(f"\n  Trajectory analysis:")
            print(f"    Peak per-frame delta: {np.degrees(peak_delta):.2f}° ({peak_vel:.2f} rad/s)")
            print(f"    Mean per-frame delta: {np.degrees(mean_delta):.2f}°")
            print(f"    Frames exceeding safety delta ({np.degrees(self.cfg.robot.max_delta_rad):.1f}°): {fast_frames}/{num_frames-1}")
            if fast_frames > 0:
                print(f"    Frame-skipping enabled to handle fast segments")

            # Confirm before starting servo loop
            input("\n  Press ENTER to start replay (Ctrl+C to stop) ")
            print(f"\n  Replaying {num_frames} frames ...")

            effective_dt = dt / self.speed_factor
            servo_dt = dt  # servoJ always uses the original dt for smooth motion
            # Tracking-error threshold for frame skipping: if the robot
            # is further than this from the current frame target, skip
            # ahead to a frame closer to where the robot actually is.
            catch_up_threshold = self.cfg.robot.max_delta_rad * 3

            stats = _ReplayStats()
            self.state.update(
                is_playing=True,
                total_frames=num_frames,
            )
            self.state.add_message(f"Replaying {num_frames} frames...")

            i = 0
            skipped_total = 0
            while i < num_frames:
                if self._stop_requested:
                    print(f"\n  Stopped at frame {i}/{num_frames}")
                    self.state.add_message(f"Stopped at frame {i}")
                    break

                t_start = time.monotonic()

                # Get current state
                current_q = self.robot.get_joint_positions()
                target = frames[i]

                # --- Frame-skipping catch-up ---
                # If the robot is far from the current frame's target,
                # skip ahead to the nearest future frame it can reach
                # in one step.  This prevents cumulative lag.
                tracking_error = np.max(np.abs(target - current_q))
                if tracking_error > catch_up_threshold and i < num_frames - 1:
                    best_i = i
                    best_err = tracking_error
                    # Scan ahead (limited window) for a closer frame
                    for j in range(i + 1, min(i + 30, num_frames)):
                        err_j = np.max(np.abs(frames[j] - current_q))
                        if err_j < best_err:
                            best_err = err_j
                            best_i = j
                        # Stop scanning once error starts growing again
                        if err_j > best_err + 0.01:
                            break
                    if best_i > i:
                        skipped = best_i - i
                        skipped_total += skipped
                        logger.info(
                            "Frame skip: %d → %d (skipped %d, error %.3f→%.3f rad)",
                            i, best_i, skipped, tracking_error, best_err,
                        )
                        i = best_i
                        target = frames[i]

                # Safety check
                safe_target = self.safety.clamp_action(target, current_q, servo_dt)

                if self.safety.drift_triggered:
                    print(f"\n  DRIFT WATCHDOG triggered at frame {i} — stopping!")
                    self.state.update(drift_triggered=True)
                    self.state.add_message(f"DRIFT WATCHDOG at frame {i}")
                    break

                # Check for protective stop
                if self.robot.is_protective_stopped():
                    print(f"\n  Protective stop detected at frame {i} — stopping!")
                    self.state.add_message(f"Protective stop at frame {i}")
                    break

                # Send command
                self.robot.servo_joint(safe_target, dt=servo_dt)

                # Track stats
                loop_dt = time.monotonic() - t_start
                delta = np.max(np.abs(safe_target - current_q))
                stats.update(delta, loop_dt)

                # Push state to dashboard
                self.state.update(
                    current_frame=i,
                    robot_q=current_q.tolist(),
                    target_q=safe_target.tolist(),
                    loop_dt_ms=loop_dt * 1000,
                    safety_violations=self.safety.violation_count,
                )

                # Progress reporting
                if (i + 1) % (num_frames // 10 or 1) == 0 or i == num_frames - 1:
                    pct = (i + 1) / num_frames * 100
                    skip_msg = f"  skipped={skipped_total}" if skipped_total else ""
                    print(
                        f"    [{pct:5.1f}%] Frame {i + 1:5d}/{num_frames}  "
                        f"max_Δ={np.degrees(delta):.2f}°  "
                        f"loop={stats.last_dt_ms:.1f}ms  "
                        f"violations={self.safety.violation_count}{skip_msg}"
                    )

                # Pace to match desired speed
                elapsed = time.monotonic() - t_start
                sleep_time = effective_dt - elapsed
                if sleep_time > 0:
                    time.sleep(sleep_time)

                i += 1

            # Stop servo gracefully
            self.robot.stop()
            stats.print_summary(self.safety.violation_count, skipped_total)
            self.state.add_message("Replay complete")

        except KeyboardInterrupt:
            print("\n  Keyboard interrupt — stopping robot.")
            self.state.add_message("Keyboard interrupt")
        finally:
            if self.robot is not None:
                self.robot.stop()
                self.robot.disconnect()
                self.state.update(is_connected=False)
                print("  Robot disconnected.")

    def _replay_dry_run(self, frames: np.ndarray, dt: float) -> None:
        """Print replay targets without connecting to the robot."""
        num_frames = len(frames)
        joint_names = ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"]

        print(f"\n  DRY-RUN: {num_frames} frames at {1/dt:.0f} Hz "
              f"(speed {self.speed_factor}x)")
        print()

        self.state.update(
            is_playing=True,
            total_frames=num_frames,
        )
        self.state.add_message(f"Dry-run: {num_frames} frames")

        # Print every 10th frame
        step = max(1, num_frames // 20)
        prev = frames[0]
        effective_dt = dt / self.speed_factor

        for i in range(0, num_frames, step):
            if self._stop_requested:
                self.state.add_message(f"Stopped at frame {i}")
                break

            target = frames[i]
            delta = target - prev
            max_delta = np.max(np.abs(delta))
            print(f"  Frame {i:5d}/{num_frames}  t={i * dt:.2f}s  max_Δ={np.degrees(max_delta):.2f}°")
            for j, name in enumerate(joint_names):
                print(f"    {name:10s}: {target[j]:+.4f} rad  ({np.degrees(target[j]):+.1f}°)")
            print()
            prev = target

            # Push state to dashboard
            self.state.update(
                current_frame=i,
                target_q=target.tolist(),
                loop_dt_ms=0.0,
            )

            # Pace the dry-run output so the dashboard scrubber moves
            time.sleep(effective_dt * step)

        # Final frame if not already printed
        if not self._stop_requested and (num_frames - 1) % step != 0:
            target = frames[-1]
            delta = target - prev
            max_delta = np.max(np.abs(delta))
            print(f"  Frame {num_frames - 1:5d}/{num_frames}  t={(num_frames - 1) * dt:.2f}s  max_Δ={np.degrees(max_delta):.2f}°")
            for j, name in enumerate(joint_names):
                print(f"    {name:10s}: {target[j]:+.4f} rad  ({np.degrees(target[j]):+.1f}°)")
            print()

            self.state.update(
                current_frame=num_frames - 1,
                target_q=target.tolist(),
            )

        self.state.add_message("Dry-run complete")
        print("  DRY-RUN complete. Use --enable-control for real playback.\n")


class _ReplayStats:
    """Track loop timing and joint delta statistics during replay."""

    def __init__(self) -> None:
        self.max_delta_rad: float = 0.0
        self.total_steps: int = 0
        self.total_time: float = 0.0
        self.last_dt_ms: float = 0.0

    def update(self, delta_rad: float, loop_dt: float) -> None:
        self.max_delta_rad = max(self.max_delta_rad, delta_rad)
        self.total_steps += 1
        self.total_time += loop_dt
        self.last_dt_ms = loop_dt * 1000

    def print_summary(self, violations: int, skipped: int = 0) -> None:
        if self.total_steps == 0:
            return
        avg_dt = self.total_time / self.total_steps * 1000
        print(f"\n  Replay complete:")
        print(f"    Steps:          {self.total_steps}")
        print(f"    Total time:     {self.total_time:.1f} s")
        print(f"    Avg loop:       {avg_dt:.1f} ms")
        print(f"    Max joint Δ:    {np.degrees(self.max_delta_rad):.2f}°")
        print(f"    Safety clamps:  {violations}")
        if skipped > 0:
            print(f"    Frames skipped: {skipped}")


def main() -> None:
    """CLI entry point for episode replay."""
    parser = argparse.ArgumentParser(
        description="Replay a LeRobot episode on the UR10e robot.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--dataset", "-d",
        type=str,
        required=True,
        help="Path to the LeRobot dataset directory.",
    )
    parser.add_argument(
        "--episode", "-e",
        type=int,
        default=None,
        help="Episode index to replay. Omit to list episodes.",
    )
    parser.add_argument(
        "--list", "-l",
        action="store_true",
        help="List all available episodes and exit.",
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
        help="Playback speed multiplier. 1.0 = original speed, 0.5 = half speed. (default: 1.0)",
    )
    parser.add_argument(
        "--move-speed",
        type=float,
        default=0.3,
        help="Joint speed (rad/s) for the initial move to start position. (default: 0.3)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=5001,
        help="Port for the replay dashboard web UI. (default: 5001)",
    )
    parser.add_argument(
        "--no-dashboard",
        action="store_true",
        help="Disable the web dashboard.",
    )
    parser.add_argument(
        "--convention",
        type=str,
        choices=["auto", "rtde", "training"],
        default="auto",
        help=(
            "Joint convention of the dataset. 'auto' detects from first frame, "
            "'rtde' skips sign flip, 'training' applies sign flip. (default: auto)"
        ),
    )

    args = parser.parse_args()

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stdout,
    )

    # Load config — auto-discover deploy.yaml if no --config given
    config_path = args.config
    if config_path is None:
        default_yaml = Path(__file__).resolve().parent.parent / "deploy.yaml"
        if default_yaml.exists():
            config_path = str(default_yaml)
            logger.info("Auto-loaded config from %s", default_yaml)
    cfg = load_config(config_path)

    # Shared state for web dashboard
    replay_state = ReplayState()

    # Create replayer
    replayer = EpisodeReplayer(
        config=cfg,
        dataset_dir=args.dataset,
        enable_control=args.enable_control,
        speed_factor=args.speed_factor,
        move_speed=args.move_speed,
        replay_state=replay_state,
        convention=args.convention,
    )

    # Start web dashboard
    if not args.no_dashboard:
        start_replay_dashboard(
            dataset=replayer.dataset,
            replay_state=replay_state,
            port=args.port,
        )
        print(f"\n  Dashboard: http://localhost:{args.port}")

    # Handle Ctrl+C gracefully
    def _sigint_handler(sig, frame):
        print("\n  Interrupt received — stopping ...")
        replayer.request_stop()

    signal.signal(signal.SIGINT, _sigint_handler)

    # List or replay
    if args.list or args.episode is None:
        replayer.list_episodes()
    else:
        replayer.replay(args.episode)

    # Keep process alive while dashboard is running
    if not args.no_dashboard:
        print("  Dashboard running — press Ctrl+C to exit.")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n  Shutting down.")


if __name__ == "__main__":
    main()
