"""
Integration tests for LeRobotLoader against a LeRobot dataset.

Tests dataset info loading, episode listing, episode data loading,
video path resolution, and camera discovery.
"""

import os
from pathlib import Path

import numpy as np
import pytest

from src.api.services.lerobot_loader import (
    LeRobotLoader,
    LeRobotLoaderError,
    is_lerobot_dataset,
)


@pytest.fixture(scope="module")
def dataset_dir(dataset_base_path, dataset_id):
    """Path to the LeRobot dataset directory."""
    path = os.path.join(dataset_base_path, dataset_id)
    assert os.path.isdir(path), f"Dataset not found: {path}"
    return path


@pytest.fixture(scope="module")
def loader(dataset_dir):
    return LeRobotLoader(dataset_dir)


class TestIsLerobotDataset:
    """Validate the format detection helper."""

    def test_valid_dataset(self, dataset_dir):
        assert is_lerobot_dataset(dataset_dir) is True

    def test_invalid_path(self, tmp_path):
        assert is_lerobot_dataset(tmp_path / "nonexistent") is False

    def test_missing_info_json(self, tmp_path):
        (tmp_path / "data").mkdir()
        assert is_lerobot_dataset(tmp_path) is False

    def test_missing_data_dir(self, tmp_path):
        meta = tmp_path / "meta"
        meta.mkdir()
        (meta / "info.json").write_text("{}")
        assert is_lerobot_dataset(tmp_path) is False


class TestDatasetInfo:
    """Test metadata loading from info.json."""

    def test_load_info(self, loader):
        info = loader.get_dataset_info()
        assert info.codebase_version
        assert info.robot_type
        assert info.total_episodes > 0
        assert info.total_frames > 0
        assert info.fps > 0
        assert info.total_tasks >= 1
        assert info.total_chunks >= 1

    def test_features_contains_state(self, loader):
        info = loader.get_dataset_info()
        assert "observation.state" in info.features
        state = info.features["observation.state"]
        assert "dtype" in state
        assert "shape" in state

    def test_features_contains_action(self, loader):
        info = loader.get_dataset_info()
        assert "action" in info.features
        action = info.features["action"]
        assert "dtype" in action
        assert "shape" in action

    def test_features_contains_video(self, loader):
        info = loader.get_dataset_info()
        video_features = [
            k for k, v in info.features.items() if v.get("dtype") == "video"
        ]
        assert len(video_features) > 0

    def test_data_and_video_path_templates(self, loader):
        info = loader.get_dataset_info()
        assert "{chunk_index" in info.data_path
        assert "{video_key}" in info.video_path


class TestListEpisodes:
    """Test episode enumeration."""

    def test_returns_episodes(self, loader):
        episodes = loader.list_episodes()
        assert len(episodes) > 0

    def test_returns_sorted_list(self, loader):
        episodes = loader.list_episodes()
        assert episodes == sorted(episodes)


class TestLoadEpisode:
    """Test loading full episode data."""

    def test_load_first_episode(self, loader):
        ep = loader.load_episode(0)
        assert ep.episode_index == 0
        assert ep.length > 0

    def test_load_last_episode(self, loader):
        episodes = loader.list_episodes()
        last = episodes[-1]
        ep = loader.load_episode(last)
        assert ep.episode_index == last
        assert ep.length > 0

    def test_timestamps_are_monotonic(self, loader):
        ep = loader.load_episode(0)
        diffs = np.diff(ep.timestamps)
        assert np.all(diffs >= 0), "timestamps must be non-decreasing"

    def test_frame_indices_sequential(self, loader):
        ep = loader.load_episode(0)
        assert ep.frame_indices[0] == 0
        diffs = np.diff(ep.frame_indices)
        assert np.all(diffs == 1), "frame indices must increment by 1"

    def test_joint_positions_shape(self, loader):
        ep = loader.load_episode(0)
        assert ep.joint_positions.ndim == 2
        assert ep.joint_positions.shape[0] == ep.length
        assert ep.joint_positions.shape[1] > 0

    def test_actions_shape(self, loader):
        ep = loader.load_episode(0)
        assert ep.actions.ndim == 2
        assert ep.actions.shape[0] == ep.length
        assert ep.actions.shape[1] > 0

    def test_task_index_is_valid(self, loader):
        ep = loader.load_episode(0)
        assert ep.task_index >= 0

    def test_metadata_fields(self, loader):
        ep = loader.load_episode(0)
        assert isinstance(ep.metadata["robot_type"], str)
        assert ep.metadata["fps"] > 0

    def test_video_paths_resolved(self, loader):
        ep = loader.load_episode(0)
        assert len(ep.video_paths) > 0
        first_path = next(iter(ep.video_paths.values()))
        assert first_path.exists(), f"Video file not found: {first_path}"
        assert first_path.suffix == ".mp4"

    def test_invalid_episode_raises(self, loader):
        with pytest.raises(LeRobotLoaderError):
            loader.load_episode(9999)

    def test_multiple_episodes_consistent_shapes(self, loader):
        """All episodes should have 16-dim state and action."""
        for idx in [0, 10, 30, 63]:
            ep = loader.load_episode(idx)
            assert ep.joint_positions.shape[1] == 16
            assert ep.actions.shape[1] == 16


class TestGetEpisodeInfo:
    """Test lightweight episode info retrieval."""

    def test_returns_length(self, loader):
        info = loader.get_episode_info(0)
        assert info["length"] > 0
        assert info["episode_index"] == 0

    def test_returns_fps(self, loader):
        info = loader.get_episode_info(0)
        assert info["fps"] == 30.0

    def test_returns_cameras(self, loader):
        info = loader.get_episode_info(0)
        assert "observation.images.il-camera" in info["cameras"]

    def test_consistent_with_load_episode(self, loader):
        info = loader.get_episode_info(5)
        ep = loader.load_episode(5)
        assert info["length"] == ep.length


class TestVideoAndCameras:
    """Test video path and camera discovery."""

    def test_get_video_path_existing(self, loader):
        path = loader.get_video_path(0, "observation.images.il-camera")
        assert path is not None
        assert path.exists()

    def test_get_video_path_missing_camera(self, loader):
        path = loader.get_video_path(0, "nonexistent_camera")
        assert path is None

    def test_get_cameras(self, loader):
        cameras = loader.get_cameras()
        assert cameras == ["observation.images.il-camera"]
