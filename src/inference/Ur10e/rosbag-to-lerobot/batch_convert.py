"""Batch-convert all rosbags from blob storage to individual LeRobot datasets.

Each bag is downloaded, converted, uploaded to houston_lerobot/<bag_name>/,
then cleaned up before moving to the next bag. Already-converted bags are
skipped automatically.

Usage::

    cd rosbag-to-lerobot
    .\.venv\Scripts\python.exe batch_convert.py
"""

from __future__ import annotations

import logging
import shutil
import sys
import time
from pathlib import Path

from rosbag_to_lerobot.blob_storage import BlobStorageClient
from rosbag_to_lerobot.config import load_config
from rosbag_to_lerobot.converter import run_conversion

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


def main() -> int:
    config_path = "config.yaml"
    output_base = Path("./batch_output")
    cfg = load_config(config_path)

    # Connect to blob storage and discover all bags.
    client = BlobStorageClient(
        account_url=cfg.blob_storage.account_url,
        container_name=cfg.blob_storage.container,
    )

    bag_prefixes = client.discover_bags(cfg.blob_storage.rosbag_prefix)
    logger.info("Found %d bag(s) in blob storage", len(bag_prefixes))

    # Check which bags are already converted.
    existing = client.list_blobs(cfg.blob_storage.lerobot_prefix)
    existing_dirs: set[str] = set()
    for blob in existing:
        # Extract the bag-name folder from e.g. "houston_lerobot/recording_xxx/meta/info.json"
        parts = blob.name.replace(cfg.blob_storage.lerobot_prefix, "").split("/")
        if parts:
            existing_dirs.add(parts[0])

    converted = 0
    skipped = 0
    failed = 0
    total = len(bag_prefixes)

    for i, bag_prefix in enumerate(bag_prefixes, 1):
        # Derive bag name from prefix, e.g. "houston_recordings/recording_xxx/" -> "recording_xxx"
        bag_name = bag_prefix.rstrip("/").rsplit("/", 1)[-1]

        # Skip if already converted.
        if bag_name in existing_dirs:
            logger.info("[%d/%d] SKIP %s (already converted)", i, total, bag_name)
            skipped += 1
            continue

        logger.info("[%d/%d] Processing %s ...", i, total, bag_name)
        t0 = time.time()

        # Prepare temp download directory.
        download_dir = output_base / "temp_download" / bag_name
        download_dir.mkdir(parents=True, exist_ok=True)

        dataset_dir = output_base / bag_name

        try:
            # Step 1: Download this bag.
            logger.info("  Downloading %s ...", bag_prefix)
            client.download_directory(bag_prefix, download_dir)

            # Step 2: Convert.
            logger.info("  Converting ...")
            run_conversion(
                cfg,
                output_dir=dataset_dir,
                local_bags=[download_dir],
                skip_upload=True,
            )

            # Step 3: Upload to houston_lerobot/<bag_name>/.
            upload_prefix = f"{cfg.blob_storage.lerobot_prefix.rstrip('/')}/{bag_name}"
            logger.info("  Uploading to %s ...", upload_prefix)
            uploaded = client.upload_directory(dataset_dir, upload_prefix)
            logger.info("  Uploaded %d file(s)", uploaded)

            converted += 1
            elapsed = time.time() - t0
            logger.info(
                "[%d/%d] DONE %s in %.0f s  (converted=%d, skipped=%d, failed=%d)",
                i, total, bag_name, elapsed, converted, skipped, failed,
            )

        except Exception:
            failed += 1
            logger.exception("[%d/%d] FAILED %s", i, total, bag_name)

        finally:
            # Step 4: Cleanup local files to save disk space.
            if download_dir.exists():
                shutil.rmtree(download_dir, ignore_errors=True)
            if dataset_dir.exists():
                shutil.rmtree(dataset_dir, ignore_errors=True)

    logger.info(
        "Batch complete: %d converted, %d skipped, %d failed out of %d total",
        converted, skipped, failed, total,
    )
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
