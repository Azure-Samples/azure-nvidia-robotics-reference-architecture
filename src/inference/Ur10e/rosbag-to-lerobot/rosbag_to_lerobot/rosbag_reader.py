"""Pure-Python rosbag reader using the rosbags library."""

from __future__ import annotations

import io
import logging
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image
from rosbags.highlevel import AnyReader
from rosbags.typesys import Stores, get_typestore

logger = logging.getLogger(__name__)

# Standard UR10e joint order expected by RTDE and the training pipeline.
STANDARD_JOINT_ORDER = [
    "shoulder_pan_joint",   # base
    "shoulder_lift_joint",  # shoulder
    "elbow_joint",          # elbow
    "wrist_1_joint",        # wrist1
    "wrist_2_joint",        # wrist2
    "wrist_3_joint",        # wrist3
]


def _build_reorder_map(bag_names: list[str]) -> list[int] | None:
    """Build index map from bag joint order to standard UR10e order.

    Returns a list where ``result[i]`` is the index in ``bag_names``
    that corresponds to ``STANDARD_JOINT_ORDER[i]``, or ``None`` if
    the bag is already in standard order.
    """
    if list(bag_names) == STANDARD_JOINT_ORDER:
        return None  # Already in standard order.
    name_to_idx = {name: idx for idx, name in enumerate(bag_names)}
    reorder = []
    for std_name in STANDARD_JOINT_ORDER:
        if std_name not in name_to_idx:
            raise ValueError(
                f"Joint {std_name!r} not found in bag. Available: {bag_names}"
            )
        reorder.append(name_to_idx[std_name])
    return reorder


@dataclass
class JointSample:
    """A single joint state sample from a rosbag."""

    timestamp_ns: int
    names: list[str]
    position: np.ndarray  # Shape (6,) float64, radians
    velocity: np.ndarray | None  # Shape (6,) float64, rad/s


@dataclass
class ImageSample:
    """A single camera image sample from a rosbag."""

    timestamp_ns: int
    image: np.ndarray  # Shape (H, W, 3) uint8 RGB
    width: int
    height: int


@dataclass
class BagContents:
    """Extracted contents from a rosbag."""

    joint_samples: list[JointSample]
    image_samples: list[ImageSample]
    duration_s: float
    topic_info: dict[str, str]  # topic -> message type mapping


def _get_typestore(ros_distro: str):
    """Get rosbags typestore for the given ROS distribution string.

    Maps strings like "ROS2_HUMBLE" to Stores enum values.

    Args:
        ros_distro: ROS distribution name, e.g. "ROS2_HUMBLE".

    Returns:
        A rosbags typestore instance for the specified distribution.

    Raises:
        ValueError: If the distribution string is not a valid Stores member.
    """
    try:
        store = Stores[ros_distro]
    except KeyError as exc:
        valid = [s.name for s in Stores]
        raise ValueError(f"Unknown ROS distro {ros_distro!r}. Valid options: {valid}") from exc
    return get_typestore(store)


def inspect_bag(bag_path: Path, ros_distro: str = "ROS2_HUMBLE") -> dict:
    """Inspect a rosbag and return topic list, message counts, duration.

    Args:
        bag_path: Path to the rosbag directory or file.
        ros_distro: ROS distribution name for type resolution.

    Returns:
        Dict with keys: topics (list of {name, type, count}),
        duration_s, start_time_ns, end_time_ns.
    """
    typestore = _get_typestore(ros_distro)
    bag_path = Path(bag_path)

    with AnyReader([bag_path], default_typestore=typestore) as reader:
        topics = []
        for conn in reader.connections:
            topics.append(
                {
                    "name": conn.topic,
                    "type": conn.msgtype,
                    "count": conn.msgcount,
                }
            )

        start_time_ns = reader.start_time
        end_time_ns = reader.end_time
        duration_s = (end_time_ns - start_time_ns) / 1e9

    logger.info(
        "Inspected %s: %d topics, %.1f s duration",
        bag_path.name,
        len(topics),
        duration_s,
    )

    return {
        "topics": topics,
        "duration_s": duration_s,
        "start_time_ns": start_time_ns,
        "end_time_ns": end_time_ns,
    }


def extract_from_bag(
    bag_path: Path,
    joint_topic: str = "/joint_states",
    image_topic: str = "/camera/color/image_raw",
    ros_distro: str = "ROS2_HUMBLE",
) -> BagContents:
    """Extract joint states and camera images from a rosbag.

    Reads through the bag once, deserialising joint-state and image messages
    from the requested topics. Results are sorted by timestamp.

    Args:
        bag_path: Path to the rosbag directory or file.
        joint_topic: Topic name for joint state messages.
        image_topic: Topic name for camera image messages.
        ros_distro: ROS distribution name for type resolution.

    Returns:
        BagContents with sorted joint and image samples.
    """
    typestore = _get_typestore(ros_distro)
    bag_path = Path(bag_path)

    joint_samples: list[JointSample] = []
    image_samples: list[ImageSample] = []
    topic_info: dict[str, str] = {}
    reorder_map: list[int] | None = None  # Lazy-built on first joint message.

    with AnyReader([bag_path], default_typestore=typestore) as reader:
        # Build topic -> msgtype mapping and filter connections.
        filtered_connections = []
        for conn in reader.connections:
            topic_info[conn.topic] = conn.msgtype
            if conn.topic in (joint_topic, image_topic):
                filtered_connections.append(conn)

        if not filtered_connections:
            logger.warning(
                "No connections matched topics %s or %s in %s",
                joint_topic,
                image_topic,
                bag_path.name,
            )

        msg_count = 0
        reorder_initialized = False
        for connection, timestamp, rawdata in reader.messages(
            connections=filtered_connections,
        ):
            msg = reader.deserialize(rawdata, connection.msgtype)
            msg_count += 1

            if msg_count % 1000 == 0:
                logger.info("Processed %d messages...", msg_count)

            if connection.topic == joint_topic:
                positions = np.array(msg.position, dtype=np.float64)
                if len(positions) != 6:
                    logger.warning(
                        "Skipping joint sample with %d joints (expected 6) at t=%d",
                        len(positions),
                        timestamp,
                    )
                    continue

                # Build reorder map once from the first message's joint names.
                if not reorder_initialized:
                    bag_names = list(msg.name)
                    reorder_map = _build_reorder_map(bag_names)
                    if reorder_map is not None:
                        logger.info(
                            "Bag joint order %s differs from standard — "
                            "reorder map: %s",
                            bag_names,
                            reorder_map,
                        )
                    else:
                        logger.info("Bag joint order matches standard UR10e order")
                    reorder_initialized = True

                # Reorder positions (and velocity) to standard UR10e order.
                if reorder_map is not None:
                    positions = positions[reorder_map]

                velocity: np.ndarray | None = None
                if hasattr(msg, "velocity") and len(msg.velocity) > 0:
                    velocity = np.array(msg.velocity, dtype=np.float64)
                    if reorder_map is not None:
                        velocity = velocity[reorder_map]

                joint_samples.append(
                    JointSample(
                        timestamp_ns=timestamp,
                        names=list(STANDARD_JOINT_ORDER),
                        position=positions,
                        velocity=velocity,
                    )
                )

            elif connection.topic == image_topic:
                image_array = _decode_image(msg, connection.msgtype)
                if image_array is not None:
                    h, w = image_array.shape[:2]
                    image_samples.append(
                        ImageSample(
                            timestamp_ns=timestamp,
                            image=image_array,
                            width=w,
                            height=h,
                        )
                    )

    # Sort by timestamp.
    joint_samples.sort(key=lambda s: s.timestamp_ns)
    image_samples.sort(key=lambda s: s.timestamp_ns)

    # Calculate duration from earliest to latest sample across both lists.
    all_timestamps = [s.timestamp_ns for s in joint_samples] + [
        s.timestamp_ns for s in image_samples
    ]
    if len(all_timestamps) >= 2:
        duration_s = (max(all_timestamps) - min(all_timestamps)) / 1e9
    elif all_timestamps:
        duration_s = 0.0
    else:
        duration_s = 0.0

    logger.info(
        "Extracted %d joint samples, %d image samples (%.1f s) from %s",
        len(joint_samples),
        len(image_samples),
        duration_s,
        bag_path.name,
    )

    return BagContents(
        joint_samples=joint_samples,
        image_samples=image_samples,
        duration_s=duration_s,
        topic_info=topic_info,
    )


def _decode_image(msg: object, msgtype: str) -> np.ndarray | None:
    """Decode a ROS image message into an RGB uint8 numpy array.

    Handles common encodings:
    - ``rgb8``, ``bgr8``: 8-bit 3-channel colour.
    - ``mono8``: 8-bit single-channel grayscale.
    - ``16UC1``: 16-bit unsigned depth, normalised to 8-bit grayscale.
    - ``32FC1``: 32-bit float depth, normalised to 8-bit grayscale.
    - CompressedImage: JPEG / PNG decoded via PIL.

    All outputs are returned as ``(H, W, 3)`` uint8 RGB.

    Args:
        msg: Deserialized ROS message.
        msgtype: Message type string (e.g. "sensor_msgs/msg/Image").

    Returns:
        np.ndarray of shape (H, W, 3) uint8 in RGB order, or None on failure.
    """
    try:
        if "CompressedImage" in msgtype:
            pil_img = Image.open(io.BytesIO(msg.data))
            return np.array(pil_img.convert("RGB"), dtype=np.uint8)

        # sensor_msgs/msg/Image
        encoding = getattr(msg, "encoding", "rgb8")

        if encoding in ("16UC1", "mono16"):
            depth = np.frombuffer(msg.data, dtype=np.uint16).reshape(msg.height, msg.width)
            # Normalise to 0-255 using the frame's own range.
            d_min, d_max = np.min(depth), np.max(depth)
            if d_max > d_min:
                norm = ((depth.astype(np.float32) - d_min) / (d_max - d_min) * 255).astype(
                    np.uint8
                )
            else:
                norm = np.zeros((msg.height, msg.width), dtype=np.uint8)
            return np.stack([norm, norm, norm], axis=-1)

        if encoding == "32FC1":
            depth = np.frombuffer(msg.data, dtype=np.float32).reshape(msg.height, msg.width)
            valid = np.isfinite(depth)
            if valid.any():
                d_min, d_max = np.nanmin(depth[valid]), np.nanmax(depth[valid])
                if d_max > d_min:
                    norm = np.clip((depth - d_min) / (d_max - d_min) * 255, 0, 255).astype(
                        np.uint8
                    )
                else:
                    norm = np.zeros((msg.height, msg.width), dtype=np.uint8)
                norm[~valid] = 0
            else:
                norm = np.zeros((msg.height, msg.width), dtype=np.uint8)
            return np.stack([norm, norm, norm], axis=-1)

        if encoding == "mono8":
            mono = np.frombuffer(msg.data, dtype=np.uint8).reshape(msg.height, msg.width)
            return np.stack([mono, mono, mono], axis=-1)

        # Default: rgb8 / bgr8 / other 8-bit multi-channel.
        image = np.frombuffer(msg.data, dtype=np.uint8).reshape(msg.height, msg.width, -1)
        if encoding == "bgr8":
            image = image[:, :, ::-1].copy()
        return image

    except Exception:
        logger.exception("Failed to decode image message (type=%s, encoding=%s)", msgtype, encoding)
        return None
