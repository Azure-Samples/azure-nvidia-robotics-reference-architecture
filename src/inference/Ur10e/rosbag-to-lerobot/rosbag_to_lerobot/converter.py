"""Rosbag-to-LeRobot dataset conversion pipeline."""

from __future__ import annotations

import logging
import shutil
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image as PILImage

from .blob_storage import BlobStorageClient
from .config import ConvertConfig
from .conventions import convert_joint_positions, resize_image
from .rosbag_reader import BagContents, extract_from_bag
from .sync import SyncedEpisode, detect_episodes, split_by_episodes, synchronize

logger = logging.getLogger(__name__)

LEROBOT_FEATURES = {
    "observation.state": {
        "dtype": "float32",
        "shape": (6,),
        "names": ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"],
    },
    "action": {
        "dtype": "float32",
        "shape": (6,),
        "names": ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"],
    },
    "observation.images.color": {
        "dtype": "video",
        "shape": (480, 848, 3),
        "names": ["height", "width", "channels"],
    },
}


def compute_action_deltas(states: list[np.ndarray]) -> list[np.ndarray]:
    """Compute action deltas from consecutive states.

    action[t] = state[t+1] - state[t]
    action[last] = zeros(6)

    Args:
        states: List of state arrays, each shape (6,).

    Returns:
        List of action delta arrays, same length as states.
    """
    deltas: list[np.ndarray] = []
    for i in range(len(states) - 1):
        deltas.append(states[i + 1] - states[i])
    deltas.append(np.zeros(6, dtype=np.float32))
    return deltas


def convert_episode(
    episode: SyncedEpisode,
    dataset: LeRobotDataset,
    config: ConvertConfig,
) -> int:
    """Convert a single synced episode and add to the dataset.

    Pipeline:
        1. Apply convention conversion (sign flip + angle wrap) if configured.
        2. Resize images if target dimensions differ from source.
        3. Compute action deltas from convention-converted states.
        4. Add each frame to the dataset via ``dataset.add_frame()``.
        5. Save the episode via ``dataset.save_episode()``.

    Args:
        episode: A synchronized episode with aligned frames.
        dataset: Target LeRobotDataset to append to.
        config: Conversion configuration.

    Returns:
        Number of frames added.
    """
    conv = config.conventions

    # Step 1: convert joint positions per convention.
    sign_mask = conv.joint_sign if conv.apply_joint_sign else None
    states: list[np.ndarray] = []
    for frame in episode.frames:
        converted = convert_joint_positions(
            frame.joint_position,
            sign_mask=sign_mask,
            wrap=conv.wrap_angles,
        )
        states.append(converted)

    # Step 2: determine target image size.
    target_hw = tuple(conv.image_resize) if conv.image_resize else None

    # Step 3: compute action deltas.
    actions = compute_action_deltas(states)

    # Step 4: add each frame.
    for i, frame in enumerate(episode.frames):
        image = frame.image
        if target_hw and (image.shape[0], image.shape[1]) != target_hw:
            image = resize_image(image, target_hw)

        pil_image = PILImage.fromarray(image)

        dataset.add_frame(
            {
                "observation.state": np.float32(states[i]),
                "observation.images.color": pil_image,
                "action": np.float32(actions[i]),
                "task": config.dataset.task_description,
            }
        )

    # Step 5: save the episode.
    dataset.save_episode()

    logger.info("Converted episode: %d frames, %.1f s", len(episode.frames), episode.duration_s)
    return len(episode.frames)


def convert_bag(
    bag_path: Path,
    dataset: LeRobotDataset,
    config: ConvertConfig,
) -> int:
    """Convert a single rosbag to LeRobot episodes.

    Pipeline:
        1. Extract joint + image data from the bag.
        2. Optionally split into sub-episodes based on temporal gaps.
        3. Synchronize each (sub-)episode at the target FPS.
        4. Convert and append each synced episode to the dataset.

    Args:
        bag_path: Path to the rosbag directory or file.
        dataset: Target LeRobotDataset to append to.
        config: Conversion configuration.

    Returns:
        Number of episodes added from this bag.
    """
    logger.info("Processing bag: %s", bag_path)

    contents: BagContents = extract_from_bag(
        bag_path,
        config.topics.joint_states,
        config.topics.camera,
        config.ros.distro,
    )

    if not contents.joint_samples or not contents.image_samples:
        logger.warning("Bag %s has no joint or image data, skipping", bag_path.name)
        return 0

    sub_episodes: list[tuple[list, list]] = []

    if config.processing.split_episodes:
        boundaries = detect_episodes(
            contents.joint_samples,
            config.processing.episode_gap_threshold_s,
        )
        sub_episodes = split_by_episodes(
            contents.joint_samples,
            contents.image_samples,
            boundaries,
        )
        logger.info(
            "Split bag %s into %d sub-episode(s) (gap threshold %.1f s)",
            bag_path.name,
            len(sub_episodes),
            config.processing.episode_gap_threshold_s,
        )
    else:
        sub_episodes = [(contents.joint_samples, contents.image_samples)]

    total_episodes = 0
    total_frames = 0

    for joints, images in sub_episodes:
        if len(joints) < 2 or not images:
            logger.warning(
                "Skipping sub-episode with %d joints, %d images", len(joints), len(images)
            )
            continue

        synced = synchronize(joints, images, fps=config.dataset.fps)
        if synced.frame_count == 0:
            logger.warning("Synchronization produced 0 frames, skipping sub-episode")
            continue

        frames_added = convert_episode(synced, dataset, config)
        total_episodes += 1
        total_frames += frames_added

    logger.info(
        "Bag %s: %d episode(s), %d total frames",
        bag_path.name,
        total_episodes,
        total_frames,
    )
    return total_episodes


def _discover_local_bags(directory: Path) -> list[Path]:
    """Find rosbag files or directories within a local directory.

    Looks for .db3, .mcap, and .bag files.

    Args:
        directory: Directory to scan.

    Returns:
        Sorted list of bag paths found.
    """
    extensions = {".db3", ".mcap", ".bag"}
    bags: list[Path] = []
    for ext in extensions:
        bags.extend(directory.rglob(f"*{ext}"))

    # For .db3 files return the parent directory (ROS2 bag structure).
    resolved: list[Path] = []
    seen: set[Path] = set()
    for bag in bags:
        target = bag.parent if bag.suffix == ".db3" else bag
        if target not in seen:
            seen.add(target)
            resolved.append(target)

    resolved.sort()
    return resolved


def run_conversion(
    config: ConvertConfig,
    output_dir: Path,
    local_bags: list[Path] | None = None,
    skip_upload: bool = False,
) -> Path:
    """Run the full conversion pipeline.

    Pipeline:
        1. Create a new LeRobotDataset.
        2. Determine bag sources (local paths or blob-storage download).
        3. Convert each bag into the dataset.
        4. Finalize the dataset.
        5. Optionally upload the result to blob storage.

    Args:
        config: Full conversion configuration.
        output_dir: Directory where the LeRobot dataset will be written.
        local_bags: Optional list of local bag paths. When provided, bags are
            read directly instead of downloading from blob storage.
        skip_upload: When ``False``, upload the finished dataset to blob
            storage at ``config.blob_storage.lerobot_prefix``.

    Returns:
        Path to the output dataset directory.
    """
    output_dir = Path(output_dir)

    # LeRobotDataset.create() requires root to not exist, so ensure it is clean.
    if output_dir.exists():
        shutil.rmtree(output_dir)

    # Step 1: create dataset.
    from lerobot.datasets.lerobot_dataset import LeRobotDataset

    dataset = LeRobotDataset.create(
        repo_id=config.dataset.repo_id,
        fps=config.dataset.fps,
        features=LEROBOT_FEATURES,
        root=output_dir,
        robot_type=config.dataset.robot_type,
    )

    # Step 2: determine bag sources.
    temp_dir: Path | None = None
    try:
        if local_bags:
            bag_paths = list(local_bags)
            logger.info("Using %d local bag(s)", len(bag_paths))
        else:
            # Check if output_dir already contains bag files.
            bag_paths = _discover_local_bags(output_dir)
            if bag_paths:
                logger.info("Found %d bag(s) in output directory", len(bag_paths))
            else:
                # Download from blob storage.
                temp_dir = Path(tempfile.mkdtemp(prefix="rosbag_download_"))
                logger.info("Downloading bags from blob storage to %s", temp_dir)

                client = BlobStorageClient(
                    account_url=config.blob_storage.account_url,
                    container_name=config.blob_storage.container,
                )
                bag_prefixes = client.discover_bags(config.blob_storage.rosbag_prefix)

                if not bag_prefixes:
                    logger.error(
                        "No bags found in blob storage under '%s'",
                        config.blob_storage.rosbag_prefix,
                    )
                    return output_dir

                for prefix in bag_prefixes:
                    client.download_directory(prefix, temp_dir)

                bag_paths = _discover_local_bags(temp_dir)
                logger.info("Downloaded %d bag(s)", len(bag_paths))

        # Step 3: convert each bag.
        total_bags = 0
        total_episodes = 0

        for bag_path in bag_paths:
            episodes = convert_bag(bag_path, dataset, config)
            total_bags += 1
            total_episodes += episodes

        # Step 4: finalize.
        dataset.finalize()

        # Step 5: log summary.
        logger.info(
            "Conversion complete: %d bag(s), %d episode(s), output at %s",
            total_bags,
            total_episodes,
            output_dir,
        )

        # Step 6: optionally upload.
        if not skip_upload and config.blob_storage.account_url:
            # Derive upload prefix from bag name(s) so each bag gets its own folder.
            base_prefix = config.blob_storage.lerobot_prefix.rstrip("/")
            if bag_paths:
                bag_name = bag_paths[0].name or bag_paths[0].stem
                upload_prefix = f"{base_prefix}/{bag_name}"
            else:
                upload_prefix = base_prefix

            logger.info("Uploading dataset to blob storage at '%s' ...", upload_prefix)
            client = BlobStorageClient(
                account_url=config.blob_storage.account_url,
                container_name=config.blob_storage.container,
            )
            uploaded = client.upload_directory(output_dir, upload_prefix)
            logger.info("Uploaded %d file(s) to '%s'", uploaded, upload_prefix)

    finally:
        if temp_dir and config.processing.cleanup_temp:
            logger.info("Cleaning up temp directory %s", temp_dir)
            shutil.rmtree(temp_dir, ignore_errors=True)

    return output_dir
