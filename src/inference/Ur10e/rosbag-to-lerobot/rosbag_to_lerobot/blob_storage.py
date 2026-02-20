"""Azure Blob Storage client for rosbag download and dataset upload."""

from __future__ import annotations

import logging
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Callable

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from tqdm import tqdm

logger = logging.getLogger(__name__)


@dataclass
class BlobInfo:
    """Metadata for a single blob."""

    name: str
    size: int
    last_modified: datetime


class BlobStorageClient:
    """Azure Blob Storage client for rosbag download and dataset upload."""

    def __init__(
        self,
        account_url: str,
        container_name: str,
        credential: object | None = None,
    ) -> None:
        """Initialize client with DefaultAzureCredential fallback.

        If credential is None, uses DefaultAzureCredential().
        Creates BlobServiceClient and gets container_client.
        """
        if credential is None:
            credential = DefaultAzureCredential()
        self._service: BlobServiceClient = BlobServiceClient(
            account_url=account_url, credential=credential
        )
        self._container = self._service.get_container_client(container_name)
        logger.info("Connected to %s / %s", account_url, container_name)

    def list_blobs(self, prefix: str) -> list[BlobInfo]:
        """List blobs under a prefix. Returns BlobInfo with name, size, last_modified."""
        blobs: list[BlobInfo] = []
        for blob in self._container.list_blobs(name_starts_with=prefix):
            blobs.append(
                BlobInfo(
                    name=blob.name,
                    size=blob.size,
                    last_modified=blob.last_modified,
                )
            )
        logger.debug("Listed %d blobs under prefix '%s'", len(blobs), prefix)
        return blobs

    def discover_bags(self, prefix: str) -> list[str]:
        """Discover rosbag directories by finding metadata.yaml files.

        Returns list of bag directory prefixes for ROS2 bags.
        For ROS1 .bag files, returns the blob paths directly.
        """
        blobs = self.list_blobs(prefix)
        bag_dirs: list[str] = []
        ros1_bags: list[str] = []

        for blob in blobs:
            name = blob.name
            if name.endswith("metadata.yaml"):
                # ROS2 bag: directory is the parent of metadata.yaml
                bag_dir = name.rsplit("/", 1)[0] + "/" if "/" in name else ""
                if bag_dir and bag_dir not in bag_dirs:
                    bag_dirs.append(bag_dir)
            elif name.endswith(".bag"):
                ros1_bags.append(name)

        discovered = bag_dirs + ros1_bags
        logger.info("Discovered %d bag(s) under '%s'", len(discovered), prefix)
        return discovered

    def download_blob(
        self,
        blob_name: str,
        local_path: Path,
        progress_hook: Callable[[int, int], None] | None = None,
    ) -> Path:
        """Download a single blob with optional progress callback.

        Creates parent directories. Uses max_concurrency=4.
        Uses tqdm progress bar if no progress_hook and stdout is TTY.
        """
        local_path.parent.mkdir(parents=True, exist_ok=True)
        blob_client = self._container.get_blob_client(blob_name)

        try:
            props = blob_client.get_blob_properties()
            total_size = props.size
            stream = blob_client.download_blob(max_concurrency=4)

            use_tqdm = progress_hook is None and sys.stdout.isatty()

            with open(local_path, "wb") as f:
                if use_tqdm:
                    with tqdm(
                        total=total_size,
                        unit="B",
                        unit_scale=True,
                        desc=Path(blob_name).name,
                    ) as pbar:
                        stream.readinto(f)
                        pbar.update(total_size)
                elif progress_hook is not None:
                    stream.readinto(f)
                    progress_hook(total_size, total_size)
                else:
                    stream.readinto(f)

            logger.debug("Downloaded %s -> %s (%d bytes)", blob_name, local_path, total_size)
        except Exception:
            logger.exception("Failed to download blob '%s'", blob_name)
            raise

        return local_path

    def download_directory(
        self,
        blob_prefix: str,
        local_dest: Path,
        progress_hook: Callable[[int, int, str], None] | None = None,
    ) -> Path:
        """Download all blobs under a prefix to a local directory.

        Preserves relative path structure under local_dest.
        Shows tqdm progress for files if no progress_hook.
        """
        blobs = self.list_blobs(blob_prefix)
        if not blobs:
            logger.warning("No blobs found under prefix '%s'", blob_prefix)
            return local_dest

        use_tqdm = progress_hook is None and sys.stdout.isatty()
        iterator = tqdm(blobs, desc="Downloading", unit="file") if use_tqdm else blobs

        for i, blob in enumerate(iterator):
            relative = blob.name
            if blob_prefix and blob.name.startswith(blob_prefix):
                relative = blob.name[len(blob_prefix) :].lstrip("/")
            local_path = local_dest / relative

            try:
                self.download_blob(blob.name, local_path)
                if progress_hook is not None:
                    progress_hook(i + 1, len(blobs), blob.name)
            except Exception:
                logger.error("Skipping failed download: %s", blob.name)

        logger.info("Downloaded %d file(s) from '%s' -> %s", len(blobs), blob_prefix, local_dest)
        return local_dest

    def upload_directory(
        self,
        local_dir: Path,
        blob_prefix: str,
        progress_hook: Callable[[int, int, str], None] | None = None,
    ) -> int:
        """Upload a local directory to blob storage.

        Walks local_dir recursively, uploads each file with relative path
        appended to blob_prefix. Uses max_concurrency=4.
        Returns number of files uploaded.
        """
        files = [p for p in local_dir.rglob("*") if p.is_file()]
        if not files:
            logger.warning("No files found in %s", local_dir)
            return 0

        use_tqdm = progress_hook is None and sys.stdout.isatty()
        iterator = tqdm(files, desc="Uploading", unit="file") if use_tqdm else files

        uploaded = 0
        for i, file_path in enumerate(iterator):
            relative = file_path.relative_to(local_dir).as_posix()
            blob_name = f"{blob_prefix.rstrip('/')}/{relative}"

            try:
                blob_client = self._container.get_blob_client(blob_name)
                with open(file_path, "rb") as data:
                    blob_client.upload_blob(data, overwrite=True, max_concurrency=4)
                uploaded += 1
                if progress_hook is not None:
                    progress_hook(i + 1, len(files), blob_name)
                logger.debug("Uploaded %s -> %s", file_path, blob_name)
            except Exception:
                logger.error("Failed to upload %s", file_path)

        logger.info("Uploaded %d / %d file(s) to '%s'", uploaded, len(files), blob_prefix)
        return uploaded
