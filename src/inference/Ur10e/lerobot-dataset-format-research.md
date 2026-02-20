# LeRobot Dataset Format Research (v3.0)

> Source: [huggingface/lerobot](https://github.com/huggingface/lerobot) — `CODEBASE_VERSION = "v3.0"`

---

## 1. Complete Directory Structure

```
<dataset_root>/
├── meta/
│   ├── info.json                           # Canonical schema, FPS, version, path templates
│   ├── stats.json                          # Global feature statistics (mean/std/min/max/quantiles)
│   ├── tasks.parquet                       # Task descriptions → integer IDs
│   └── episodes/
│       └── chunk-{chunk_index:03d}/
│           └── file-{file_index:03d}.parquet  # Per-episode metadata (lengths, tasks, offsets, stats)
├── data/
│   └── chunk-{chunk_index:03d}/
│       └── file-{file_index:03d}.parquet      # Frame-by-frame tabular data (many episodes per file)
└── videos/
    └── {video_key}/                           # e.g. observation.images.wrist
        └── chunk-{chunk_index:03d}/
            └── file-{file_index:03d}.mp4      # MP4 video shards (many episodes per file)
```

### Path Template Constants (from `utils.py`)

```python
CHUNK_FILE_PATTERN = "chunk-{chunk_index:03d}/file-{file_index:03d}"
DEFAULT_TASKS_PATH = "meta/tasks.parquet"
DEFAULT_EPISODES_PATH = "meta/episodes/" + CHUNK_FILE_PATTERN + ".parquet"
DEFAULT_DATA_PATH = "data/" + CHUNK_FILE_PATTERN + ".parquet"
DEFAULT_VIDEO_PATH = "videos/{video_key}/" + CHUNK_FILE_PATTERN + ".mp4"
DEFAULT_IMAGE_PATH = "images/{image_key}/episode-{episode_index:06d}/frame-{frame_index:06d}.png"
```

### Chunking Defaults

| Setting | Default | Purpose |
|---|---|---|
| `DEFAULT_CHUNK_SIZE` | 1000 | Max files per chunk directory |
| `DEFAULT_DATA_FILE_SIZE_IN_MB` | 100 MB | Max parquet file size before splitting |
| `DEFAULT_VIDEO_FILE_SIZE_IN_MB` | 200 MB | Max MP4 file size before splitting |

---

## 2. Required Parquet Columns and Types

### Auto-Generated Columns (`DEFAULT_FEATURES`)

These are **automatically added** by `LeRobotDatasetMetadata.create()` — do NOT include them in your `features` dict:

| Column | dtype | shape | Description |
|---|---|---|---|
| `timestamp` | `float32` | `(1,)` | Frame timestamp in seconds (relative to episode start) |
| `frame_index` | `int64` | `(1,)` | 0-based index within the episode |
| `episode_index` | `int64` | `(1,)` | Episode number |
| `index` | `int64` | `(1,)` | Global frame index across all episodes |
| `task_index` | `int64` | `(1,)` | Index into the tasks table |

### User-Defined Features (examples for UR10e)

```python
FEATURES = {
    # Robot state — joint positions
    "observation.state": {
        "dtype": "float32",
        "shape": (6,),
        "names": ["shoulder_pan", "shoulder_lift", "elbow", "wrist_1", "wrist_2", "wrist_3"],
    },
    # Robot action — joint velocity commands or position targets
    "action": {
        "dtype": "float32",
        "shape": (6,),
        "names": ["shoulder_pan", "shoulder_lift", "elbow", "wrist_1", "wrist_2", "wrist_3"],
    },
    # Camera images (stored as video)
    "observation.images.wrist": {
        "dtype": "video",
        "shape": (480, 640, 3),
        "names": ["height", "width", "channels"],
    },
    # Gripper state (optional)
    "observation.state.gripper_position": {
        "dtype": "float32",
        "shape": (1,),
        "names": None,
    },
}
```

### Feature dtype Options

| dtype | Parquet representation | Notes |
|---|---|---|
| `float32` | float column or `Sequence` | Scalar if shape `(1,)`, array if shape `(N,)` |
| `float64` | float column or `Sequence` | Same mapping |
| `int64` | int column or `Sequence` | Same mapping |
| `bool` | bool column | For flags like `is_first`, `is_last` |
| `string` | string column | For language instructions |
| `image` | `datasets.Image()` | PNG stored on disk, loaded as PIL |
| `video` | `VideoFrame` (path + timestamp) | MP4 on disk, decoded on demand |

### HuggingFace Features Mapping (`get_hf_features_from_features`)

```python
# shape (1,) → scalar Value
# shape (N,) → Sequence(length=N)
# shape (H, W) → Array2D
# shape (H, W, C) → Array3D
# "image" → datasets.Image()
# "video" → skipped in parquet (stored as separate MP4)
```

---

## 3. Video File Requirements

### Encoding Parameters (Recommended Defaults)

| Parameter | Default Value | Description |
|---|---|---|
| `vcodec` | `libsvtav1` (AV1) | Video codec |
| `pix_fmt` | `yuv420p` | Pixel format |
| `g` (GOP size) | `2` | Keyframe interval |
| `crf` | `30` | Constant rate factor (quality) |
| `fast_decode` | `0` | Fast decode tuning |

### Valid Codecs

```python
VALID_VIDEO_CODECS = {"h264", "hevc", "libsvtav1"}
```

### Encoding Function Signature

```python
encode_video_frames(
    imgs_dir: Path,          # Directory containing frame-NNNNNN.png files
    video_path: Path,        # Output .mp4 path
    fps: int,                # Frames per second
    vcodec: str = "libsvtav1",
    pix_fmt: str = "yuv420p",
    g: int = 2,
    crf: int = 30,
    fast_decode: int = 0,
    overwrite: bool = False,
)
```

### Codec Compatibility Notes

- `libsvtav1` and `hevc` do NOT support `yuv444p` — auto-falls back to `yuv420p`
- `h264` supports both `yuv444p` and `yuv420p`
- Input frames must be named `frame-NNNNNN.png` (6-digit zero-padded)

### Video Metadata Stored Per Episode

Each episode's video metadata (in `meta/episodes/`) includes:

```
videos/{video_key}/chunk_index     — which chunk the video is in
videos/{video_key}/file_index      — which file within the chunk
videos/{video_key}/from_timestamp  — start timestamp in the MP4
videos/{video_key}/to_timestamp    — end timestamp in the MP4
```

---

## 4. Metadata Format (`info.json`)

```json
{
    "codebase_version": "v3.0",
    "robot_type": "ur10e",
    "total_episodes": 0,
    "total_frames": 0,
    "total_tasks": 0,
    "chunks_size": 1000,
    "data_files_size_in_mb": 100,
    "video_files_size_in_mb": 200,
    "fps": 30,
    "splits": {},
    "data_path": "data/chunk-{chunk_index:03d}/file-{file_index:03d}.parquet",
    "video_path": "videos/{video_key}/chunk-{chunk_index:03d}/file-{file_index:03d}.mp4",
    "features": {
        "observation.state": {
            "dtype": "float32",
            "shape": [6],
            "names": ["shoulder_pan", "shoulder_lift", "elbow", "wrist_1", "wrist_2", "wrist_3"]
        },
        "action": {
            "dtype": "float32",
            "shape": [6],
            "names": ["shoulder_pan", "shoulder_lift", "elbow", "wrist_1", "wrist_2", "wrist_3"]
        },
        "observation.images.wrist": {
            "dtype": "video",
            "shape": [480, 640, 3],
            "names": ["height", "width", "channels"]
        },
        "timestamp": {
            "dtype": "float32",
            "shape": [1],
            "names": null
        },
        "frame_index": {
            "dtype": "int64",
            "shape": [1],
            "names": null
        },
        "episode_index": {
            "dtype": "int64",
            "shape": [1],
            "names": null
        },
        "index": {
            "dtype": "int64",
            "shape": [1],
            "names": null
        },
        "task_index": {
            "dtype": "int64",
            "shape": [1],
            "names": null
        }
    }
}
```

### Other Metadata Files

| File | Format | Content |
|---|---|---|
| `meta/stats.json` | JSON | Global statistics: `min`, `max`, `mean`, `std`, `count`, `q01`–`q99` per feature |
| `meta/tasks.parquet` | Parquet | Task descriptions mapped to integer IDs |
| `meta/episodes/chunk-NNN/file-NNN.parquet` | Parquet | Per-episode: `episode_index`, `tasks`, `length`, `data/chunk_index`, `data/file_index`, `dataset_from_index`, `dataset_to_index`, per-feature stats, video timestamps |

---

## 5. Python API for Creating Datasets Programmatically

### Core Workflow

```python
from lerobot.datasets.lerobot_dataset import LeRobotDataset
import numpy as np

# 1. Define features (DON'T include DEFAULT_FEATURES — they're auto-added)
features = {
    "observation.state": {"dtype": "float32", "shape": (6,), "names": None},
    "action": {"dtype": "float32", "shape": (6,), "names": None},
    "observation.images.wrist": {
        "dtype": "video",
        "shape": (480, 640, 3),
        "names": ["height", "width", "channels"],
    },
}

# 2. Create the dataset
dataset = LeRobotDataset.create(
    repo_id="my_org/ur10e_pick_place",
    fps=30,
    features=features,
    robot_type="ur10e",
    root="/path/to/dataset",        # Optional, defaults to ~/.cache/huggingface/lerobot/
    use_videos=True,                # True for video, False for images
    vcodec="libsvtav1",             # Video codec
)

# 3. Record episodes
for episode_data in all_episodes:
    for frame in episode_data:
        dataset.add_frame({
            "observation.state": np.array([...], dtype=np.float32),  # shape (6,)
            "action": np.array([...], dtype=np.float32),             # shape (6,)
            "observation.images.wrist": image_array,                 # numpy uint8 (H, W, 3)
            "task": "Pick up the red block",                         # Required string
            # "timestamp": 0.033,  # Optional — auto-computed as frame_index / fps if omitted
        })
    dataset.save_episode()

# 4. MUST call finalize() to close parquet writers
dataset.finalize()

# 5. Optionally push to HuggingFace Hub
dataset.push_to_hub(tags=["ur10e"], private=True)
```

### Key API Methods

| Method | Purpose |
|---|---|
| `LeRobotDataset.create(repo_id, fps, features, ...)` | Create new empty dataset |
| `dataset.add_frame(frame_dict)` | Buffer a single frame (writes images to temp dir) |
| `dataset.save_episode()` | Flush buffered frames → parquet, encode video, update metadata |
| `dataset.clear_episode_buffer()` | Discard current episode (re-record) |
| `dataset.finalize()` | **MUST call** — closes parquet writers, flushes metadata |
| `dataset.push_to_hub()` | Upload to HuggingFace Hub |

### `add_frame()` Details

- Accepts a dict with keys matching your defined features + `"task"` (required string)
- `frame_index` and `timestamp` are auto-generated (timestamp = frame_index / fps unless you provide it)
- `index`, `episode_index`, `task_index` are auto-managed
- Images/video frames: accepts `np.ndarray` (uint8, HWC), `torch.Tensor`, or `PIL.Image`
- Torch tensors are auto-converted to numpy
- Validation: wrong shape, missing keys, or extra keys raise `ValueError`

### `save_episode()` Details

- Validates the episode buffer
- Computes episode statistics (min/max/mean/std/quantiles)
- Writes frame data to parquet (appends to existing file or creates new file based on size limits)
- Encodes video from temp PNG frames → MP4
- Updates `meta/info.json` (total_episodes, total_frames, splits)
- Updates `meta/stats.json` (aggregated statistics)
- Saves episode metadata to `meta/episodes/` parquet

---

## 6. ROS Bag Conversion Utilities

**No existing rosbag-to-LeRobot conversion tools exist** in the lerobot repository. The search for `rosbag`, `ros`, `from_rosbag` returned no relevant results.

### Recommended Approach: Custom Conversion Script

Use the DROID porting example (`examples/port_datasets/port_droid.py`) as a template:

```python
"""
ROS Bag → LeRobot Dataset Conversion (Template)

Dependencies:
    pip install rosbags  # or rosbag for ROS1
    pip install lerobot
"""
from pathlib import Path
import numpy as np
from lerobot.datasets.lerobot_dataset import LeRobotDataset

# Adjust these for your UR10e setup
FPS = 30
ROBOT_TYPE = "ur10e"

FEATURES = {
    "observation.state": {
        "dtype": "float32",
        "shape": (6,),  # 6 joint positions
        "names": ["shoulder_pan", "shoulder_lift", "elbow", "wrist_1", "wrist_2", "wrist_3"],
    },
    "action": {
        "dtype": "float32",
        "shape": (6,),  # 6 joint velocity/position commands
        "names": ["shoulder_pan", "shoulder_lift", "elbow", "wrist_1", "wrist_2", "wrist_3"],
    },
    "observation.images.wrist": {
        "dtype": "video",
        "shape": (480, 640, 3),
        "names": ["height", "width", "channels"],
    },
}


def extract_frames_from_rosbag(bag_path: Path):
    """
    Generator yielding synchronized frames from a ROS bag.

    Yields:
        dict with keys: "observation.state", "action", "observation.images.wrist", "task"
    """
    # === ROS2 with rosbags ===
    from rosbags.rosbag2 import Reader
    from rosbags.serde import deserialize_cdr

    with Reader(bag_path) as reader:
        # Build time-synchronized frames from your topics
        # Topics might be:
        #   /joint_states (sensor_msgs/JointState)
        #   /camera/color/image_raw (sensor_msgs/Image)
        #   /ur_controller/command (your action topic)

        for frame in synchronized_frames(reader):
            yield {
                "observation.state": np.array(frame["joint_positions"], dtype=np.float32),
                "action": np.array(frame["joint_commands"], dtype=np.float32),
                "observation.images.wrist": frame["image"],  # np.ndarray uint8, shape (H, W, 3)
                "task": "Pick up object",  # Natural language task description
                # Optionally provide timestamp:
                # "timestamp": frame["timestamp_seconds"],
            }


def convert_rosbags_to_lerobot(
    bag_paths: list[Path],
    repo_id: str,
    output_dir: Path,
):
    dataset = LeRobotDataset.create(
        repo_id=repo_id,
        fps=FPS,
        features=FEATURES,
        robot_type=ROBOT_TYPE,
        root=output_dir,
        use_videos=True,
        vcodec="libsvtav1",  # or "h264" for wider compatibility
    )

    for bag_path in bag_paths:
        print(f"Processing: {bag_path}")

        for frame in extract_frames_from_rosbag(bag_path):
            dataset.add_frame(frame)

        dataset.save_episode()

    # CRITICAL: must call finalize() before push_to_hub()
    dataset.finalize()

    # Optional: push to HuggingFace Hub
    # dataset.push_to_hub(tags=["ur10e", "ros"], private=True)

    return dataset


if __name__ == "__main__":
    bag_paths = sorted(Path("/path/to/rosbags").glob("*.db3"))
    convert_rosbags_to_lerobot(
        bag_paths=bag_paths,
        repo_id="my_org/ur10e_pick_place",
        output_dir=Path("/path/to/output/dataset"),
    )
```

### Key Conversion Considerations

1. **Time synchronization**: ROS topics arrive at different rates. You need to synchronize joint state, camera images, and actions to a common timeline at the target FPS
2. **Resampling**: If your ROS bag records at a different rate than the target FPS, resample using interpolation (for states/actions) or nearest-frame (for images)
3. **Action alignment**: Decide if actions represent the command at time `t` or the command that was applied between `t` and `t+1`
4. **Image format**: Convert ROS Image messages to numpy arrays `(H, W, 3)` in RGB uint8 format
5. **Timestamp handling**: Either provide timestamps explicitly in `add_frame()` or let LeRobot auto-compute them as `frame_index / fps`

---

## 7. Loading an Existing Dataset

```python
from lerobot.datasets.lerobot_dataset import LeRobotDataset, LeRobotDatasetMetadata

# Load just metadata (lightweight)
meta = LeRobotDatasetMetadata("lerobot/pusht")
print(meta.total_episodes, meta.total_frames, meta.fps)
print(meta.features)

# Load full dataset
dataset = LeRobotDataset("lerobot/pusht")

# Load specific episodes only
dataset = LeRobotDataset("lerobot/pusht", episodes=[0, 10, 11, 23])

# Access a frame
frame = dataset[0]
print(frame.keys())  # observation.state, action, timestamp, frame_index, ...
```

---

## 8. Dataset Tools (Post-Processing)

Available via `lerobot.datasets.dataset_tools`:

| Tool | Function |
|---|---|
| Delete episodes | `delete_episodes(dataset, episode_indices=[0, 2, 5])` |
| Split dataset | `split_dataset(dataset, splits={"train": 0.8, "val": 0.2})` |
| Merge datasets | `merge_datasets([ds1, ds2], output_repo_id="merged")` |
| Add features | `add_features(dataset, features={"reward": (values, info)})` |
| Remove features | `remove_feature(dataset, feature_names="observation.images.top")` |
| Convert image→video | `convert_image_to_video_dataset(dataset, output_dir, vcodec="libsvtav1")` |

CLI:

```bash
python -m lerobot.scripts.lerobot_edit_dataset \
    --repo_id my/dataset \
    --operation.type delete_episodes \
    --operation.episode_indices "[0, 2, 5]"
```

---

## 9. Version History

| Version | Key Differences |
|---|---|
| **v2.1** | One parquet file per episode (`data/chunk-000/episode_000000.parquet`), one video file per episode |
| **v3.0** | Many episodes per parquet/MP4 file, chunked storage, relational metadata, incremental parquet writing |

Migration: `lerobot/datasets/v30/convert_dataset_v21_to_v30.py`

---

## 10. Key Dependencies

```
lerobot          # Core library
torch            # Tensor operations
numpy            # Array operations
datasets         # HuggingFace datasets library
pyarrow          # Parquet I/O
av               # Video encoding/decoding (PyAV wraps FFmpeg)
Pillow           # Image I/O
huggingface_hub  # Hub upload/download
rosbags          # ROS2 bag reading (for conversion — install separately)
```
