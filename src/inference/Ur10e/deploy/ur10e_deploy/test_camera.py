"""Test camera capture and display a sample frame.

Usage::

    python -m ur10e_deploy.test_camera --backend opencv --device-id 0

Verifies the camera produces the expected 480×848 RGB frames.
"""

from __future__ import annotations

import argparse
import logging

import cv2
import numpy as np

from .camera import create_camera
from .config import CameraConfig

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


def main() -> None:
    parser = argparse.ArgumentParser(description="Test camera capture")
    parser.add_argument("--backend", default="opencv", choices=["opencv", "realsense"])
    parser.add_argument("--device-id", type=int, default=0)
    parser.add_argument("--width", type=int, default=848)
    parser.add_argument("--height", type=int, default=480)
    args = parser.parse_args()

    cfg = CameraConfig(
        backend=args.backend,
        device_id=args.device_id,
        width=args.width,
        height=args.height,
    )

    camera = create_camera(cfg)
    camera.start()

    try:
        for i in range(5):
            frame = camera.grab_rgb()
            logger.info(
                "Frame %d: shape=%s  dtype=%s  range=[%d, %d]",
                i, frame.shape, frame.dtype, frame.min(), frame.max(),
            )

        # Save a sample frame
        sample = camera.grab_rgb()
        sample_bgr = cv2.cvtColor(sample, cv2.COLOR_RGB2BGR)
        cv2.imwrite("test_frame.png", sample_bgr)
        logger.info("Sample frame saved to test_frame.png")
        logger.info("Expected shape: (480, 848, 3) — got: %s", sample.shape)

        if sample.shape == (480, 848, 3):
            logger.info("Camera test PASSED")
        else:
            logger.warning(
                "Shape mismatch — policy expects (480, 848, 3). "
                "Frames will be resized automatically."
            )
    finally:
        camera.stop()


if __name__ == "__main__":
    main()
