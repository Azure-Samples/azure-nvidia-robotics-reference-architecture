#!/usr/bin/env python3
"""Comprehensive validation of the houston_lerobot dataset in blob storage.

Downloads meta files and samples data/video blobs to verify:
  1. info.json schema matches template
  2. stats.json has correct keys and shapes
  3. tasks.parquet structure
  4. episodes parquet: all 174 episodes, correct global indexing
  5. Sample data parquets: schema, dtypes, frame_index reset, global index continuity
  6. Sample videos: readable, correct frame counts
  7. Cross-consistency between meta and data
"""

from __future__ import annotations

import io
import json
import struct
import sys
import tempfile
from pathlib import Path
from typing import Any

import numpy as np
import pyarrow.parquet as pq

# ---------------------------------------------------------------------------
# Blob client
# ---------------------------------------------------------------------------

from rosbag_to_lerobot.blob_storage import BlobStorageClient

ACCOUNT_URL = "https://stosmorbt3dev001.blob.core.windows.net"
CONTAINER = "datasets"
PREFIX = "houston_lerobot"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

passed = 0
failed = 0
warnings = 0


def ok(msg: str) -> None:
    global passed
    passed += 1
    print(f"  ✅ {msg}")


def fail(msg: str) -> None:
    global failed
    failed += 1
    print(f"  ❌ {msg}")


def warn(msg: str) -> None:
    global warnings
    warnings += 1
    print(f"  ⚠️  {msg}")


def read_blob_json(client: BlobStorageClient, rel: str) -> dict:
    blob = client._container.get_blob_client(f"{PREFIX}/{rel}")
    return json.loads(blob.download_blob().readall())


def read_blob_parquet(client: BlobStorageClient, rel: str):
    blob = client._container.get_blob_client(f"{PREFIX}/{rel}")
    data = blob.download_blob().readall()
    return pq.read_table(io.BytesIO(data))


def download_blob_bytes(client: BlobStorageClient, rel: str) -> bytes:
    blob = client._container.get_blob_client(f"{PREFIX}/{rel}")
    return blob.download_blob().readall()


# ---------------------------------------------------------------------------
# 1. info.json
# ---------------------------------------------------------------------------

EXPECTED_FEATURES = {
    "timestamp": {"dtype": "float64", "shape": [1]},
    "frame_index": {"dtype": "int64", "shape": [1]},
    "episode_index": {"dtype": "int64", "shape": [1]},
    "index": {"dtype": "int64", "shape": [1]},
    "task_index": {"dtype": "int64", "shape": [1]},
    "observation.state": {
        "dtype": "float32",
        "shape": [6],
        "names": ["joint_0", "joint_1", "joint_2", "joint_3", "joint_4", "joint_5"],
    },
    "action": {
        "dtype": "float32",
        "shape": [6],
        "names": ["joint_0", "joint_1", "joint_2", "joint_3", "joint_4", "joint_5"],
    },
    "observation.images.color": {
        "dtype": "video",
        "shape": [480, 848, 3],
        "names": ["height", "width", "channels"],
    },
}


def validate_info(info: dict) -> None:
    print("\n── 1. info.json ──")

    # Version
    if info.get("codebase_version") == "v3.0":
        ok("codebase_version = v3.0")
    else:
        fail(f"codebase_version = {info.get('codebase_version')} (expected v3.0)")

    # Robot type
    if info.get("robot_type") == "ur10e":
        ok("robot_type = ur10e")
    else:
        fail(f"robot_type = {info.get('robot_type')}")

    # Counts
    te = info.get("total_episodes", 0)
    tf = info.get("total_frames", 0)
    if te == 174:
        ok(f"total_episodes = {te}")
    else:
        fail(f"total_episodes = {te} (expected 174)")

    if tf > 0:
        ok(f"total_frames = {tf}")
    else:
        fail(f"total_frames = {tf}")

    if info.get("total_tasks") == 1:
        ok("total_tasks = 1")
    else:
        fail(f"total_tasks = {info.get('total_tasks')}")

    if info.get("total_chunks") == 174:
        ok(f"total_chunks = {info.get('total_chunks')}")
    else:
        fail(f"total_chunks = {info.get('total_chunks')} (expected 174)")

    if info.get("fps") == 30:
        ok("fps = 30")
    else:
        fail(f"fps = {info.get('fps')}")

    # Splits
    expected_split = f"0:{te}"
    actual_split = info.get("splits", {}).get("train")
    if actual_split == expected_split:
        ok(f"splits.train = {actual_split}")
    else:
        fail(f"splits.train = {actual_split} (expected {expected_split})")

    # Paths
    if info.get("data_path") == "data/chunk-{chunk_index:03d}/file-{file_index:03d}.parquet":
        ok("data_path template correct")
    else:
        fail(f"data_path = {info.get('data_path')}")

    if info.get("video_path") == "videos/{video_key}/chunk-{chunk_index:03d}/file-{file_index:03d}.mp4":
        ok("video_path template correct")
    else:
        fail(f"video_path = {info.get('video_path')}")

    # Features
    feats = info.get("features", {})
    for name, expected in EXPECTED_FEATURES.items():
        if name not in feats:
            fail(f"Missing feature: {name}")
            continue
        actual = feats[name]
        if actual.get("dtype") != expected["dtype"]:
            fail(f"Feature {name} dtype: {actual.get('dtype')} (expected {expected['dtype']})")
        elif actual.get("shape") != expected["shape"]:
            fail(f"Feature {name} shape: {actual.get('shape')} (expected {expected['shape']})")
        elif "names" in expected and actual.get("names") != expected["names"]:
            fail(f"Feature {name} names: {actual.get('names')} (expected {expected['names']})")
        else:
            ok(f"Feature '{name}' matches template")

    # Video codec info
    vid_info = feats.get("observation.images.color", {}).get("info", {})
    if vid_info.get("video.codec") == "h264":
        ok("video.codec = h264")
    else:
        fail(f"video.codec = {vid_info.get('video.codec')}")

    if vid_info.get("video.pix_fmt") == "yuv420p":
        ok("video.pix_fmt = yuv420p")
    else:
        fail(f"video.pix_fmt = {vid_info.get('video.pix_fmt')}")


# ---------------------------------------------------------------------------
# 2. stats.json
# ---------------------------------------------------------------------------

def validate_stats(stats: dict) -> None:
    print("\n── 2. stats.json ──")

    expected_keys = {"observation.state", "action"}
    actual_keys = set(stats.keys())
    if actual_keys == expected_keys:
        ok(f"Stats keys: {sorted(actual_keys)}")
    else:
        extra = actual_keys - expected_keys
        missing = expected_keys - actual_keys
        if missing:
            fail(f"Missing stats keys: {missing}")
        if extra:
            warn(f"Extra stats keys: {extra}")

    for feat in ["observation.state", "action"]:
        if feat not in stats:
            continue
        s = stats[feat]
        for metric in ["mean", "std", "min", "max"]:
            if metric not in s:
                fail(f"stats[{feat}] missing '{metric}'")
            elif len(s[metric]) != 6:
                fail(f"stats[{feat}][{metric}] length {len(s[metric])} (expected 6)")
            else:
                ok(f"stats[{feat}][{metric}]: length 6")

    # Sanity: std should be positive
    for feat in ["observation.state", "action"]:
        if feat not in stats:
            continue
        std = stats[feat].get("std", [])
        if all(v > 0 for v in std):
            ok(f"stats[{feat}].std all positive")
        else:
            fail(f"stats[{feat}].std has non-positive values: {std}")

    # Sanity: min <= mean <= max
    for feat in ["observation.state", "action"]:
        if feat not in stats:
            continue
        s = stats[feat]
        mn, mean, mx = s["min"], s["mean"], s["max"]
        if all(mn[i] <= mean[i] <= mx[i] for i in range(6)):
            ok(f"stats[{feat}]: min <= mean <= max")
        else:
            fail(f"stats[{feat}]: min/mean/max ordering violated")

    # Action should be delta-style (small values near zero)
    if "action" in stats:
        a_mean = stats["action"]["mean"]
        if all(abs(v) < 0.1 for v in a_mean):
            ok(f"Action means are small (delta-style): max|mean| = {max(abs(v) for v in a_mean):.6f}")
        else:
            warn(f"Action means seem large for deltas: {a_mean}")


# ---------------------------------------------------------------------------
# 3. tasks.parquet
# ---------------------------------------------------------------------------

def validate_tasks(client: BlobStorageClient) -> None:
    print("\n── 3. tasks.parquet ──")
    table = read_blob_parquet(client, "meta/tasks.parquet")
    df = table.to_pandas()

    if set(df.columns) >= {"task_index", "task"}:
        ok(f"Columns: {list(df.columns)}")
    else:
        fail(f"Missing columns. Got: {list(df.columns)}")

    if len(df) == 1:
        ok("1 task row")
    else:
        fail(f"{len(df)} task rows (expected 1)")

    if len(df) > 0 and df["task_index"].iloc[0] == 0:
        ok(f"task_index = 0, task = '{df['task'].iloc[0]}'")
    elif len(df) > 0:
        fail(f"task_index = {df['task_index'].iloc[0]} (expected 0)")


# ---------------------------------------------------------------------------
# 4. episodes parquet
# ---------------------------------------------------------------------------

def validate_episodes(client: BlobStorageClient, info: dict) -> dict[int, dict]:
    print("\n── 4. episodes parquet ──")
    table = read_blob_parquet(client, "meta/episodes/chunk-000/file-000.parquet")
    df = table.to_pandas()

    expected_cols = {
        "episode_index", "task_index", "length",
        "dataset_from_index", "dataset_to_index",
        "data/chunk_index", "data/file_index",
        "videos/observation.images.color/chunk_index",
        "videos/observation.images.color/file_index",
        "videos/observation.images.color/from_timestamp",
        "videos/observation.images.color/to_timestamp",
    }
    actual_cols = set(df.columns)
    if expected_cols.issubset(actual_cols):
        ok(f"All {len(expected_cols)} expected columns present")
    else:
        missing = expected_cols - actual_cols
        fail(f"Missing columns: {missing}")

    if len(df) == info["total_episodes"]:
        ok(f"Row count = {len(df)} (matches total_episodes)")
    else:
        fail(f"Row count = {len(df)} (expected {info['total_episodes']})")

    # Episode indices 0..N-1
    ep_indices = df["episode_index"].tolist()
    if ep_indices == list(range(len(df))):
        ok("episode_index: 0..173 continuous")
    else:
        fail(f"episode_index not continuous: first={ep_indices[0]}, last={ep_indices[-1]}")

    # Global index continuity
    global_ok = True
    total_from_lengths = 0
    ep_map: dict[int, dict] = {}
    for _, row in df.iterrows():
        ei = int(row["episode_index"])
        from_idx = int(row["dataset_from_index"])
        to_idx = int(row["dataset_to_index"])
        length = int(row["length"])
        ep_map[ei] = {
            "from": from_idx,
            "to": to_idx,
            "length": length,
        }
        if to_idx - from_idx != length:
            fail(f"Episode {ei}: to-from ({to_idx - from_idx}) != length ({length})")
            global_ok = False
        total_from_lengths += length

    if global_ok:
        ok("dataset_from/to_index consistent with lengths")

    if total_from_lengths == info["total_frames"]:
        ok(f"Sum of episode lengths ({total_from_lengths}) == total_frames ({info['total_frames']})")
    else:
        fail(f"Sum of lengths ({total_from_lengths}) != total_frames ({info['total_frames']})")

    # Check from/to continuity
    prev_to = 0
    continuous = True
    for ei in sorted(ep_map.keys()):
        if ep_map[ei]["from"] != prev_to:
            fail(f"Episode {ei}: from_index {ep_map[ei]['from']} != prev to_index {prev_to}")
            continuous = False
            break
        prev_to = ep_map[ei]["to"]
    if continuous:
        ok("Global index is continuous across episodes (no gaps)")

    # Chunk/file index == episode_index
    chunk_match = all(
        int(df.loc[df["episode_index"] == i, "data/chunk_index"].iloc[0]) == i
        for i in range(len(df))
    )
    if chunk_match:
        ok("data/chunk_index == episode_index for all episodes")
    else:
        fail("data/chunk_index doesn't match episode_index")

    # Timestamps positive and ordered
    ts_ok = True
    for _, row in df.iterrows():
        ft = row.get("videos/observation.images.color/from_timestamp", 0)
        tt = row.get("videos/observation.images.color/to_timestamp", 0)
        if tt <= ft:
            ts_ok = False
            break
    if ts_ok:
        ok("Video timestamps: to > from for all episodes")
    else:
        fail("Some episodes have to_timestamp <= from_timestamp")

    return ep_map


# ---------------------------------------------------------------------------
# 5. Data parquet samples
# ---------------------------------------------------------------------------

def validate_data_parquets(
    client: BlobStorageClient,
    ep_map: dict[int, dict],
    sample_indices: list[int],
) -> None:
    print("\n── 5. Data parquets (sampling) ──")

    expected_columns = [
        "timestamp", "frame_index", "episode_index",
        "index", "task_index", "observation.state", "action",
    ]

    for ei in sample_indices:
        rel = f"data/chunk-{ei:03d}/file-{ei:03d}.parquet"
        print(f"    Checking episode {ei} ({rel})...")

        try:
            table = read_blob_parquet(client, rel)
        except Exception as e:
            fail(f"Episode {ei}: cannot read parquet: {e}")
            continue

        df = table.to_pandas()
        n = len(df)

        # Column set
        if set(expected_columns).issubset(set(df.columns)):
            ok(f"Ep {ei}: all 7 columns present")
        else:
            fail(f"Ep {ei}: missing columns {set(expected_columns) - set(df.columns)}")
            continue

        # Row count matches episodes parquet
        expected_len = ep_map[ei]["length"]
        if n == expected_len:
            ok(f"Ep {ei}: {n} rows (matches episodes parquet)")
        else:
            fail(f"Ep {ei}: {n} rows (expected {expected_len})")

        # episode_index constant
        if (df["episode_index"] == ei).all():
            ok(f"Ep {ei}: episode_index all = {ei}")
        else:
            fail(f"Ep {ei}: episode_index not constant")

        # frame_index: 0..N-1
        fi = df["frame_index"].tolist()
        if fi == list(range(n)):
            ok(f"Ep {ei}: frame_index 0..{n-1}")
        else:
            fail(f"Ep {ei}: frame_index not 0..{n-1} (first={fi[0]}, last={fi[-1]})")

        # Global index range
        expected_from = ep_map[ei]["from"]
        expected_to = ep_map[ei]["to"]
        actual_from = int(df["index"].iloc[0])
        actual_to = int(df["index"].iloc[-1]) + 1
        if actual_from == expected_from and actual_to == expected_to:
            ok(f"Ep {ei}: global index {actual_from}..{actual_to-1}")
        else:
            fail(f"Ep {ei}: global index {actual_from}..{actual_to-1} (expected {expected_from}..{expected_to-1})")

        # task_index all 0
        if (df["task_index"] == 0).all():
            ok(f"Ep {ei}: task_index all = 0")
        else:
            fail(f"Ep {ei}: task_index not all 0")

        # observation.state and action shapes
        state_first = df["observation.state"].iloc[0]
        action_first = df["action"].iloc[0]
        state_arr = np.array(state_first)
        action_arr = np.array(action_first)
        if state_arr.shape == (6,) and state_arr.dtype in (np.float32, np.float64):
            ok(f"Ep {ei}: observation.state shape=(6,) dtype={state_arr.dtype}")
        else:
            fail(f"Ep {ei}: observation.state shape={state_arr.shape} dtype={state_arr.dtype}")

        if action_arr.shape == (6,) and action_arr.dtype in (np.float32, np.float64):
            ok(f"Ep {ei}: action shape=(6,) dtype={action_arr.dtype}")
        else:
            fail(f"Ep {ei}: action shape={action_arr.shape} dtype={action_arr.dtype}")

        # Timestamp monotonic
        ts = df["timestamp"].values
        if np.all(np.diff(ts) > 0):
            ok(f"Ep {ei}: timestamps strictly increasing")
        elif np.all(np.diff(ts) >= 0):
            warn(f"Ep {ei}: timestamps non-decreasing (some duplicates)")
        else:
            fail(f"Ep {ei}: timestamps not monotonic")

        # Action sanity: should be deltas (small)
        all_actions = np.stack(df["action"].values)
        max_action = np.max(np.abs(all_actions))
        if max_action < 1.0:
            ok(f"Ep {ei}: actions are small (max|a|={max_action:.4f}) - delta-style")
        else:
            warn(f"Ep {ei}: max|action|={max_action:.4f} seems large for deltas")


# ---------------------------------------------------------------------------
# 6. Video samples
# ---------------------------------------------------------------------------

def _mp4_frame_count_from_mdat(data: bytes) -> int | None:
    """Parse MP4 moov/trak to get sample count (rough heuristic via stsz box)."""
    # Search for 'stsz' box which contains sample_count
    idx = data.find(b"stsz")
    if idx < 0:
        return None
    # stsz format: [version(1) flags(3) sample_size(4) sample_count(4)]
    offset = idx + 4  # after 'stsz'
    if offset + 12 > len(data):
        return None
    _version_flags = data[offset : offset + 4]
    _sample_size = struct.unpack(">I", data[offset + 4 : offset + 8])[0]
    sample_count = struct.unpack(">I", data[offset + 8 : offset + 12])[0]
    return sample_count


def validate_videos(
    client: BlobStorageClient, ep_map: dict[int, dict], sample_indices: list[int]
) -> None:
    print("\n── 6. Video samples ──")

    for ei in sample_indices:
        rel = f"videos/observation.images.color/chunk-{ei:03d}/file-{ei:03d}.mp4"
        print(f"    Checking episode {ei} ({rel})...")

        try:
            data = download_blob_bytes(client, rel)
        except Exception as e:
            fail(f"Ep {ei}: cannot download video: {e}")
            continue

        if len(data) < 1000:
            fail(f"Ep {ei}: video too small ({len(data)} bytes)")
            continue

        ok(f"Ep {ei}: video size = {len(data):,} bytes")

        # Check it's an MP4 (ftyp box)
        if data[4:8] == b"ftyp":
            ok(f"Ep {ei}: valid MP4 header (ftyp)")
        else:
            fail(f"Ep {ei}: not a valid MP4 (no ftyp box)")

        # Try to get frame count from stsz
        fc = _mp4_frame_count_from_mdat(data)
        expected_frames = ep_map[ei]["length"]
        if fc is not None:
            if fc == expected_frames:
                ok(f"Ep {ei}: video frame count = {fc} (matches parquet)")
            else:
                warn(f"Ep {ei}: video stsz count = {fc}, parquet length = {expected_frames}")
        else:
            warn(f"Ep {ei}: could not parse stsz for frame count")


# ---------------------------------------------------------------------------
# 7. Blob completeness
# ---------------------------------------------------------------------------

def validate_blob_completeness(client: BlobStorageClient, info: dict) -> None:
    print("\n── 7. Blob completeness ──")

    blobs = list(client._container.list_blobs(name_starts_with=f"{PREFIX}/"))
    blob_names = {b.name.removeprefix(f"{PREFIX}/") for b in blobs}

    total_size = sum(b.size for b in blobs)
    ok(f"Total blobs: {len(blobs)}, total size: {total_size / 1024 / 1024:.1f} MB")

    # Check all meta files exist
    meta_files = [
        "meta/info.json",
        "meta/stats.json",
        "meta/tasks.parquet",
        "meta/episodes/chunk-000/file-000.parquet",
    ]
    for mf in meta_files:
        if mf in blob_names:
            ok(f"Meta: {mf} exists")
        else:
            fail(f"Meta: {mf} MISSING")

    # Check all data parquets exist
    n_ep = info["total_episodes"]
    missing_data = []
    for i in range(n_ep):
        rel = f"data/chunk-{i:03d}/file-{i:03d}.parquet"
        if rel not in blob_names:
            missing_data.append(i)
    if not missing_data:
        ok(f"All {n_ep} data parquets present")
    else:
        fail(f"{len(missing_data)} data parquets missing: {missing_data[:10]}...")

    # Check all videos exist
    missing_vid = []
    for i in range(n_ep):
        rel = f"videos/observation.images.color/chunk-{i:03d}/file-{i:03d}.mp4"
        if rel not in blob_names:
            missing_vid.append(i)
    if not missing_vid:
        ok(f"All {n_ep} video files present")
    else:
        fail(f"{len(missing_vid)} videos missing: {missing_vid[:10]}...")

    expected_total = 4 + n_ep + n_ep  # meta + data + videos
    if len(blobs) == expected_total:
        ok(f"Blob count {len(blobs)} == expected {expected_total}")
    else:
        warn(f"Blob count {len(blobs)} != expected {expected_total}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    global passed, failed, warnings

    print("=" * 60)
    print("Houston LeRobot Dataset Validation")
    print(f"Blob: {ACCOUNT_URL} / {CONTAINER} / {PREFIX}")
    print("=" * 60)

    client = BlobStorageClient(ACCOUNT_URL, CONTAINER)

    # 1. info.json
    info = read_blob_json(client, "meta/info.json")
    validate_info(info)

    # 2. stats.json
    stats = read_blob_json(client, "meta/stats.json")
    validate_stats(stats)

    # 3. tasks.parquet
    validate_tasks(client)

    # 4. episodes parquet
    ep_map = validate_episodes(client, info)

    # 5. Sample data parquets — first, last, middle, and a few random
    n_ep = info["total_episodes"]
    sample_indices = sorted(set([0, 1, n_ep // 4, n_ep // 2, 3 * n_ep // 4, n_ep - 2, n_ep - 1]))
    validate_data_parquets(client, ep_map, sample_indices)

    # 6. Video samples — same indices
    validate_videos(client, ep_map, sample_indices)

    # 7. Blob completeness
    validate_blob_completeness(client, info)

    # Summary
    print("\n" + "=" * 60)
    print(f"RESULTS:  ✅ {passed} passed  |  ❌ {failed} failed  |  ⚠️  {warnings} warnings")
    if failed == 0:
        print("🎉 Dataset validation PASSED")
    else:
        print("💥 Dataset validation FAILED")
    print("=" * 60)

    sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    main()
