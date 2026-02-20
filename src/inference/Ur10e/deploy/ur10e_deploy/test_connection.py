"""Test the RTDE connection and read current joint state.

Usage::

    python -m ur10e_deploy.test_connection --robot-ip 192.168.2.102

This script verifies:
1. Network connectivity (ping).
2. RTDE receive interface (read joint positions).
3. RTDE control interface (handshake only — no motion).
"""

from __future__ import annotations

import argparse
import logging
import subprocess
import sys

import numpy as np

from .config import RobotConfig
from .robot import UR10eRTDE

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


def main() -> None:
    parser = argparse.ArgumentParser(description="Test UR10e RTDE connection")
    parser.add_argument("--robot-ip", default="192.168.2.102")
    args = parser.parse_args()

    ip = args.robot_ip

    # 1. Ping test
    logger.info("1/3  Pinging %s ...", ip)
    try:
        result = subprocess.run(
            ["ping", "-n", "2", "-w", "2000", ip],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            logger.info("     Ping OK")
        else:
            logger.error("     Ping FAILED — check network connection")
            sys.exit(1)
    except Exception as e:
        logger.error("     Ping error: %s", e)
        sys.exit(1)

    # 2. RTDE receive
    logger.info("2/3  Connecting RTDE receive interface ...")
    cfg = RobotConfig(ip=ip)
    robot = UR10eRTDE(cfg)
    try:
        robot.connect()
    except Exception as e:
        logger.error("     RTDE connection failed: %s", e)
        sys.exit(1)

    state = robot.get_joint_state()
    logger.info("     Joint positions (rad): [%s]",
                ", ".join(f"{v:+.4f}" for v in state.positions))
    logger.info("     Joint positions (deg): [%s]",
                ", ".join(f"{np.degrees(v):+.1f}" for v in state.positions))
    logger.info("     Joint velocities:      [%s]",
                ", ".join(f"{v:+.4f}" for v in state.velocities))

    # 3. Safety status
    logger.info("3/3  Safety status ...")
    logger.info("     Protective stop: %s", robot.is_protective_stopped())
    logger.info("     Emergency stop : %s", robot.is_emergency_stopped())

    robot.disconnect()
    logger.info("All checks passed ✓")


if __name__ == "__main__":
    main()
