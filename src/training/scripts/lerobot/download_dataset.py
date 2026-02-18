"""Download LeRobot dataset from Azure Blob Storage and prepare for training.

Handles blob download, dataset verification, stats patching for image/video
features, and video timestamp realignment.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

EXIT_SUCCESS = 0
EXIT_FAILURE = 1


def download_dataset(
    *,
    storage_account: str,
    storage_container: str,
    blob_prefix: str,
    dataset_root: str,
    dataset_repo_id: str,
) -> Path:
    """Download dataset files from Azure Blob Storage.

    Args:
        storage_account: Azure Storage account name.
        storage_container: Blob container name.
        blob_prefix: Blob path prefix for dataset files.
        dataset_root: Local root directory for datasets.
        dataset_repo_id: Dataset repository identifier (e.g., user/dataset).

    Returns:
        Path to the downloaded dataset directory.
    """
    from azure.identity import DefaultAzureCredential
    from azure.storage.blob import BlobServiceClient

    dest_dir = Path(dataset_root) / dataset_repo_id
    dest_dir.mkdir(parents=True, exist_ok=True)

    prefix = blob_prefix.rstrip("/") + "/"

    credential = DefaultAzureCredential(
        managed_identity_client_id=os.environ.get("AZURE_CLIENT_ID"),
        authority=os.environ.get("AZURE_AUTHORITY_HOST"),
    )
    client = BlobServiceClient(
        account_url=f"https://{storage_account}.blob.core.windows.net",
        credential=credential,
    )
    container_client = client.get_container_client(storage_container)

    downloaded = 0
    for blob in container_client.list_blobs(name_starts_with=prefix):
        rel = blob.name[len(prefix) :]
        if ".cache/" in rel or rel.endswith(".lock") or rel.endswith(".metadata"):
            continue

        local_path = dest_dir / rel
        local_path.parent.mkdir(parents=True, exist_ok=True)

        with open(local_path, "wb") as f:
            stream = container_client.download_blob(blob.name)
            f.write(stream.readall())
        downloaded += 1

    print(f"Downloaded {downloaded} files to {dest_dir}")
    return dest_dir


def verify_dataset(dataset_dir: Path) -> dict | None:
    """Verify dataset structure and return info.json contents.

    Args:
        dataset_dir: Path to dataset directory.

    Returns:
        Parsed info.json dict, or None if not found.
    """
    info_path = dataset_dir / "meta" / "info.json"
    if not info_path.exists():
        print("Warning: meta/info.json not found")
        return None

    with open(info_path) as f:
        info = json.load(f)

    print(
        f"Dataset: {info.get('robot_type', 'unknown')} robot, "
        f"{info.get('total_episodes', '?')} episodes, "
        f"{info.get('total_frames', '?')} frames"
    )
    return info


def patch_image_stats(dataset_dir: Path, info: dict) -> None:
    """Patch stats.json with ImageNet normalization stats for video/image features.

    LeRobot's factory.py expects camera keys to exist in stats.json.

    Args:
        dataset_dir: Path to dataset directory.
        info: Parsed info.json contents.
    """
    stats_path = dataset_dir / "meta" / "stats.json"
    if not stats_path.exists():
        return

    with open(stats_path) as f:
        stats = json.load(f)

    features = info.get("features", {})
    updated = False
    for key, feat in features.items():
        if feat.get("dtype") in ("video", "image") and key not in stats:
            stats[key] = {
                "mean": [[[0.485]], [[0.456]], [[0.406]]],
                "std": [[[0.229]], [[0.224]], [[0.225]]],
                "min": [[[0.0]], [[0.0]], [[0.0]]],
                "max": [[[1.0]], [[1.0]], [[1.0]]],
            }
            updated = True
            print(f"Added ImageNet stats for feature: {key}")

    if updated:
        with open(stats_path, "w") as f:
            json.dump(stats, f, indent=4)


def fix_video_timestamps(dataset_dir: Path, info: dict) -> None:
    """Fix video timestamps in episode metadata and realign parquet data.

    Some datasets have cumulative from/to timestamps in episode metadata
    but per-episode timestamps in the actual video files (each starting at 0).
    This resets from_timestamp to 0 and to_timestamp to length/fps.
    Also realigns parquet frame timestamps to match the video's exact PTS grid.

    Args:
        dataset_dir: Path to dataset directory.
        info: Parsed info.json contents.
    """
    import pyarrow as pa
    import pyarrow.parquet as pq

    fps = info["fps"]
    video_keys = [k for k, v in info.get("features", {}).items() if v.get("dtype") in ("video", "image")]

    if not video_keys:
        print("No video features, skipping timestamp fix")
        return

    # Fix episode metadata: reset from/to timestamps to per-episode
    episodes_dir = dataset_dir / "meta" / "episodes"
    for fpath in episodes_dir.rglob("*.parquet"):
        table = pq.read_table(fpath)
        columns = {c: table[c].to_pylist() for c in table.column_names}
        modified = False

        for vk in video_keys:
            from_col = f"videos/{vk}/from_timestamp"
            to_col = f"videos/{vk}/to_timestamp"
            if from_col not in columns or to_col not in columns:
                continue

            lengths = columns["length"]
            for i in range(len(lengths)):
                new_from = 0.0
                new_to = lengths[i] / fps
                if abs(columns[from_col][i] - new_from) > 0.01 or abs(columns[to_col][i] - new_to) > 0.01:
                    columns[from_col][i] = new_from
                    columns[to_col][i] = new_to
                    modified = True

        if modified:
            new_table = pa.table({c: columns[c] for c in table.column_names})
            pq.write_table(new_table, fpath)
            print(f"Fixed cumulative video timestamps in {fpath.name}")
        else:
            print("Video timestamps already per-episode, no fix needed")

    # Realign parquet data timestamps to the 1/fps grid
    data_dir = dataset_dir / "data"
    fixed_data = 0
    for fpath in data_dir.rglob("*.parquet"):
        table = pq.read_table(fpath)
        ts = table["timestamp"].to_pylist()
        if not ts:
            continue

        aligned_ts = [i / fps for i in range(len(ts))]
        max_drift = max(abs(a - b) for a, b in zip(ts, aligned_ts, strict=False))

        if max_drift > 0.02:
            col_idx = table.column_names.index("timestamp")
            new_col = pa.array(aligned_ts, type=pa.float64())
            table = table.set_column(col_idx, "timestamp", new_col)
            pq.write_table(table, fpath)
            fixed_data += 1
            rel = fpath.relative_to(dataset_dir)
            print(f"Realigned timestamps in {rel} (drift was {max_drift * 1000:.0f}ms)")

    if fixed_data:
        print(f"Realigned timestamps in {fixed_data} data files")
    else:
        print("Data timestamps already aligned, no fix needed")


def prepare_dataset() -> Path:
    """Download and prepare dataset from Azure Blob Storage using environment variables.

    Environment variables:
        STORAGE_ACCOUNT: Azure Storage account name.
        STORAGE_CONTAINER: Blob container name (default: datasets).
        BLOB_PREFIX: Blob path prefix for dataset.
        DATASET_ROOT: Local root directory (default: /workspace/data).
        DATASET_REPO_ID: Dataset repository identifier.

    Returns:
        Path to prepared dataset directory.
    """
    storage_account = os.environ.get("STORAGE_ACCOUNT", "")
    storage_container = os.environ.get("STORAGE_CONTAINER", "datasets")
    blob_prefix = os.environ.get("BLOB_PREFIX", "")
    dataset_root = os.environ.get("DATASET_ROOT", "/workspace/data")
    dataset_repo_id = os.environ.get("DATASET_REPO_ID", "")

    if not storage_account or not blob_prefix or not dataset_repo_id:
        print(
            "[ERROR] STORAGE_ACCOUNT, BLOB_PREFIX, and DATASET_REPO_ID are required",
            file=sys.stderr,
        )
        sys.exit(EXIT_FAILURE)

    print("=== Downloading dataset from Azure Blob Storage ===")
    dataset_dir = download_dataset(
        storage_account=storage_account,
        storage_container=storage_container,
        blob_prefix=blob_prefix,
        dataset_root=dataset_root,
        dataset_repo_id=dataset_repo_id,
    )

    info = verify_dataset(dataset_dir)
    if info:
        patch_image_stats(dataset_dir, info)
        fix_video_timestamps(dataset_dir, info)

    return dataset_dir


if __name__ == "__main__":
    sys.exit(EXIT_SUCCESS if prepare_dataset() else EXIT_FAILURE)
