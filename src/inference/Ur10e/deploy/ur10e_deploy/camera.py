"""Camera capture backends — OpenCV and Intel RealSense.

Provides a uniform interface for grabbing 480×848 RGB frames at 30 Hz.
Includes thread-safe lifecycle management and atexit cleanup to prevent
camera pipelines from being held by zombie processes.
"""

from __future__ import annotations

import atexit
import logging
import threading
import time
import weakref
from abc import ABC, abstractmethod

import cv2
import numpy as np

from .config import CameraConfig

logger = logging.getLogger(__name__)

# Global registry of active cameras for atexit cleanup.
# Uses weak references so cameras that are properly garbage-collected
# don't prevent cleanup of others.
_active_cameras: list[weakref.ref] = []
_cleanup_registered = False


def _atexit_cleanup_all() -> None:
    """Stop all active camera pipelines at interpreter shutdown."""
    for ref in _active_cameras:
        cam = ref()
        if cam is not None and cam.is_running:
            try:
                logger.info("atexit: stopping %s", type(cam).__name__)
                cam.stop()
            except Exception as exc:
                logger.debug("atexit cleanup error: %s", exc)


def _register_camera(camera: "CameraBase") -> None:
    """Add a camera to the global cleanup registry."""
    global _cleanup_registered
    if not _cleanup_registered:
        atexit.register(_atexit_cleanup_all)
        _cleanup_registered = True
    _active_cameras.append(weakref.ref(camera))


# ---------------------------------------------------------------------------
# Image resizing helpers
# ---------------------------------------------------------------------------


def _letterbox_resize(
    image: np.ndarray,
    target_w: int,
    target_h: int,
    pad_color: tuple[int, int, int] = (0, 0, 0),
) -> np.ndarray:
    """Resize *image* to fit within (target_w, target_h) preserving aspect ratio.

    Black bars are added to fill the remaining space (letterboxing).
    This avoids the horizontal stretch that distorts spatial features.

    Parameters
    ----------
    image : np.ndarray
        Source image, shape ``(H, W, 3)``.
    target_w, target_h : int
        Desired output dimensions.
    pad_color : tuple
        RGB fill color for letterbox bars.

    Returns
    -------
    np.ndarray
        Resized and padded image, shape ``(target_h, target_w, 3)``.
    """
    h, w = image.shape[:2]
    scale = min(target_w / w, target_h / h)
    new_w = int(w * scale)
    new_h = int(h * scale)

    resized = cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_LINEAR)

    # Create canvas and center the resized image
    canvas = np.full((target_h, target_w, 3), pad_color, dtype=np.uint8)
    x_offset = (target_w - new_w) // 2
    y_offset = (target_h - new_h) // 2
    canvas[y_offset : y_offset + new_h, x_offset : x_offset + new_w] = resized

    return canvas


def _crop_and_resize(
    image: np.ndarray,
    target_w: int,
    target_h: int,
) -> np.ndarray:
    """Crop the image to the target aspect ratio, then resize.

    Crops from the center (removing top/bottom or left/right as needed)
    so the entire output frame contains real image content with no black
    bars.  This is preferred when the target aspect ratio differs
    significantly from the source.

    Parameters
    ----------
    image : np.ndarray
        Source image, shape ``(H, W, 3)``.
    target_w, target_h : int
        Desired output dimensions.

    Returns
    -------
    np.ndarray
        Cropped and resized image, shape ``(target_h, target_w, 3)``.
    """
    h, w = image.shape[:2]
    target_ratio = target_w / target_h  # e.g. 1.767
    src_ratio = w / h  # e.g. 1.333

    if src_ratio > target_ratio:
        # Source is wider → crop sides
        new_w = int(h * target_ratio)
        x_off = (w - new_w) // 2
        image = image[:, x_off : x_off + new_w]
    else:
        # Source is taller → crop top/bottom
        new_h = int(w / target_ratio)
        y_off = (h - new_h) // 2
        image = image[y_off : y_off + new_h, :]

    return cv2.resize(image, (target_w, target_h), interpolation=cv2.INTER_LINEAR)


class CameraBase(ABC):
    """Abstract camera interface with safe lifecycle management.

    Supports context-manager usage::

        with create_camera(cfg) as cam:
            frame = cam.grab_rgb()

    Thread-safe ``start()`` / ``stop()`` with idempotency — calling
    ``start()`` twice is harmless, and ``stop()`` always releases
    resources even if errors occur.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._started = False

    # --- Context manager ---

    def __enter__(self) -> "CameraBase":
        self.start()
        return self

    def __exit__(self, *exc) -> None:
        self.stop()

    # --- Properties ---

    @property
    def is_running(self) -> bool:
        """Whether the camera pipeline is active."""
        return self._started

    # --- Lifecycle ---

    @abstractmethod
    def _do_start(self) -> None:
        """Backend-specific start logic (called under lock)."""
        ...

    @abstractmethod
    def _do_stop(self) -> None:
        """Backend-specific stop logic (called under lock)."""
        ...

    def start(self) -> None:
        """Start the camera pipeline (idempotent, thread-safe)."""
        with self._lock:
            if self._started:
                logger.warning("%s already started — skipping", type(self).__name__)
                return
            self._do_start()
            self._started = True
            _register_camera(self)

    def stop(self) -> None:
        """Stop the camera pipeline and release resources (idempotent, thread-safe)."""
        with self._lock:
            if not self._started:
                return
            self._started = False
            try:
                self._do_stop()
            except Exception as exc:
                logger.warning("Error during %s stop: %s", type(self).__name__, exc)

    @abstractmethod
    def grab_rgb(self) -> np.ndarray:
        """Return (H, W, 3) uint8 RGB image."""
        ...


# ---------------------------------------------------------------------------
# OpenCV backend (USB webcam / V4L2)
# ---------------------------------------------------------------------------


class OpenCVCamera(CameraBase):
    """OpenCV VideoCapture backend."""

    def __init__(self, config: CameraConfig) -> None:
        super().__init__()
        self.cfg = config
        self._cap: cv2.VideoCapture | None = None

    def _do_start(self) -> None:
        logger.info("Opening camera device %d via OpenCV ...", self.cfg.device_id)
        self._cap = cv2.VideoCapture(self.cfg.device_id)
        if not self._cap.isOpened():
            self._cap = None
            raise RuntimeError(f"Cannot open camera device {self.cfg.device_id}")
        self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.cfg.width)
        self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.cfg.height)
        self._cap.set(cv2.CAP_PROP_FPS, self.cfg.fps)
        # Verify
        actual_w = int(self._cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        actual_h = int(self._cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        logger.info("Camera opened — resolution: %d×%d", actual_w, actual_h)

    def _do_stop(self) -> None:
        if self._cap is not None:
            try:
                self._cap.release()
            except Exception as exc:
                logger.debug("OpenCV release error: %s", exc)
            finally:
                self._cap = None
        logger.info("Camera released")

    def grab_rgb(self, max_retries: int = 5) -> np.ndarray:
        if self._cap is None:
            raise RuntimeError("Camera not started")
        for attempt in range(max_retries):
            ret, frame = self._cap.read()
            if ret and frame is not None:
                # OpenCV returns BGR → convert to RGB
                frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                # Crop to target aspect ratio then resize — no black bars
                h, w = frame.shape[:2]
                if w != self.cfg.width or h != self.cfg.height:
                    frame = _crop_and_resize(
                        frame, self.cfg.width, self.cfg.height
                    )
                return frame
            logger.warning("Frame grab failed (attempt %d/%d)", attempt + 1, max_retries)
            time.sleep(0.01)
        raise RuntimeError(f"Failed to capture frame after {max_retries} retries")


# ---------------------------------------------------------------------------
# Intel RealSense backend
# ---------------------------------------------------------------------------


class RealSenseCamera(CameraBase):
    """Intel RealSense D4xx color stream backend.

    Adds robust resource management:
    - Thread-safe start/stop with idempotency
    - Timeout on ``wait_for_frames`` to detect disconnections
    - Retry on start if a previous pipeline is still releasing
    - ``atexit`` cleanup to prevent zombie pipelines
    """

    #: Maximum time (ms) to wait for a single frame before raising.
    FRAME_TIMEOUT_MS = 5000

    #: Retries when starting the pipeline (device may be held briefly
    #: by a previous process that is shutting down).
    START_RETRIES = 3
    START_RETRY_DELAY = 1.0  # seconds between retries

    def __init__(self, config: CameraConfig) -> None:
        super().__init__()
        self.cfg = config
        self._pipeline = None
        self._needs_resize = False

    def _do_start(self) -> None:
        try:
            import pyrealsense2 as rs
        except ImportError:
            raise RuntimeError(
                "pyrealsense2 not installed. "
                "Install with: pip install pyrealsense2"
            )

        # Check that at least one RealSense device is connected
        ctx = rs.context()
        devices = ctx.query_devices()
        if len(devices) == 0:
            raise RuntimeError(
                "No RealSense devices found. "
                "Check USB connection and driver installation."
            )
        dev_name = devices[0].get_info(rs.camera_info.name)
        dev_serial = devices[0].get_info(rs.camera_info.serial_number)

        cap_w = self.cfg.capture_width or self.cfg.width
        cap_h = self.cfg.capture_height or self.cfg.height

        last_err: Exception | None = None
        for attempt in range(1, self.START_RETRIES + 1):
            try:
                logger.info(
                    "Starting RealSense pipeline (attempt %d/%d) — %s [%s] ...",
                    attempt, self.START_RETRIES, dev_name, dev_serial,
                )
                pipeline = rs.pipeline()
                rs_config = rs.config()
                rs_config.enable_stream(
                    rs.stream.color,
                    cap_w,
                    cap_h,
                    rs.format.rgb8,
                    self.cfg.fps,
                )
                pipeline.start(rs_config)
                self._pipeline = pipeline
                last_err = None
                break
            except RuntimeError as exc:
                last_err = exc
                logger.warning(
                    "RealSense start failed (attempt %d/%d): %s",
                    attempt, self.START_RETRIES, exc,
                )
                if attempt < self.START_RETRIES:
                    time.sleep(self.START_RETRY_DELAY)

        if last_err is not None:
            raise RuntimeError(
                f"Failed to start RealSense after {self.START_RETRIES} attempts. "
                f"The device may be held by another process. "
                f"Last error: {last_err}"
            ) from last_err

        self._needs_resize = (cap_w != self.cfg.width or cap_h != self.cfg.height)

        # Warm up — discard first few frames so auto-exposure settles
        for _ in range(10):
            try:
                self._pipeline.wait_for_frames(timeout_ms=self.FRAME_TIMEOUT_MS)
            except RuntimeError:
                pass  # tolerate warm-up drops

        logger.info(
            "RealSense pipeline started — capture %d×%d, output %d×%d @ %d fps",
            cap_w, cap_h, self.cfg.width, self.cfg.height, self.cfg.fps,
        )

    def _do_stop(self) -> None:
        if self._pipeline is not None:
            try:
                self._pipeline.stop()
            except Exception as exc:
                logger.debug("RealSense pipeline stop error: %s", exc)
            finally:
                self._pipeline = None
            # Brief pause to let the USB device fully release
            time.sleep(0.3)
        logger.info("RealSense pipeline stopped")

    def grab_rgb(self) -> np.ndarray:
        if not self._started or self._pipeline is None:
            raise RuntimeError("RealSense pipeline not started")
        try:
            frames = self._pipeline.wait_for_frames(
                timeout_ms=self.FRAME_TIMEOUT_MS,
            )
        except RuntimeError as exc:
            raise RuntimeError(
                f"RealSense frame timeout ({self.FRAME_TIMEOUT_MS} ms) — "
                f"device may be disconnected: {exc}"
            ) from exc
        color_frame = frames.get_color_frame()
        if not color_frame:
            raise RuntimeError("No color frame received")
        image = np.asarray(color_frame.get_data())
        if self._needs_resize:
            image = _crop_and_resize(image, self.cfg.width, self.cfg.height)
        return image


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------


def create_camera(config: CameraConfig) -> CameraBase:
    """Create camera instance based on backend configuration."""
    if config.backend == "realsense":
        return RealSenseCamera(config)
    return OpenCVCamera(config)
