"""
Unit tests for HDF5FormatHandler.

Tests handler detection and capability checks. Full episode loading
tests are skipped when no HDF5 dataset is available since the test
fixture datasets are LeRobot format.
"""

import numpy as np
import pytest

from src.api.services.dataset_service.hdf5_handler import HDF5FormatHandler


class TestHandlerDetection:
    """Test format detection and capability."""

    def test_available_matches_import(self):
        from src.api.services.dataset_service.hdf5_handler import HDF5_AVAILABLE

        h = HDF5FormatHandler()
        assert h.available is HDF5_AVAILABLE

    def test_cannot_handle_empty_dir(self, tmp_path):
        h = HDF5FormatHandler()
        assert h.can_handle(tmp_path) is False

    def test_cannot_handle_nonexistent(self, tmp_path):
        h = HDF5FormatHandler()
        assert h.can_handle(tmp_path / "nonexistent") is False

    def test_cannot_handle_lerobot_dataset(self, tmp_path):
        """A LeRobot dataset without .hdf5 files should not match."""
        (tmp_path / "meta").mkdir()
        (tmp_path / "meta" / "info.json").write_text("{}")
        (tmp_path / "data").mkdir()
        h = HDF5FormatHandler()
        assert h.can_handle(tmp_path) is False

    def test_get_loader_nonexistent(self, tmp_path):
        h = HDF5FormatHandler()
        assert h.get_loader("fake", tmp_path / "nonexistent") is False


class TestListEpisodesNoData:
    """Test list_episodes when no loader is initialized."""

    def test_returns_empty(self):
        h = HDF5FormatHandler()
        indices, meta = h.list_episodes("unknown_dataset")
        assert indices == []
        assert meta == {}


class TestLoadEpisodeNoData:
    """Test load_episode when no loader is initialized."""

    def test_returns_none(self):
        h = HDF5FormatHandler()
        assert h.load_episode("unknown", 0) is None


class TestTrajectoryNoData:
    """Test get_trajectory when no loader is initialized."""

    def test_returns_empty(self):
        h = HDF5FormatHandler()
        assert h.get_trajectory("unknown", 0) == []


class TestCamerasNoData:
    """Test cameras when no loader is initialized."""

    def test_returns_empty(self):
        h = HDF5FormatHandler()
        assert h.get_cameras("unknown", 0) == []

    def test_video_path_returns_none(self):
        h = HDF5FormatHandler()
        assert h.get_video_path("unknown", 0, "cam") is None


class TestBuildTrajectory:
    """Test the shared build_trajectory utility used by both handlers."""

    def test_basic_conversion(self):
        from src.api.services.dataset_service.base import build_trajectory

        length = 3
        timestamps = np.array([0.0, 0.033, 0.066])
        joint_positions = np.zeros((3, 6))
        joint_positions[1, 0] = 1.5

        points = build_trajectory(
            length=length,
            timestamps=timestamps,
            joint_positions=joint_positions,
        )

        assert len(points) == 3
        assert points[0].timestamp == 0.0
        assert points[1].joint_positions[0] == 1.5
        assert points[0].frame == 0
        assert points[2].frame == 2

    def test_with_frame_indices(self):
        from src.api.services.dataset_service.base import build_trajectory

        points = build_trajectory(
            length=2,
            timestamps=np.array([0.0, 0.5]),
            frame_indices=np.array([10, 20]),
            joint_positions=np.zeros((2, 6)),
        )

        assert points[0].frame == 10
        assert points[1].frame == 20

    def test_optional_arrays(self):
        from src.api.services.dataset_service.base import build_trajectory

        points = build_trajectory(
            length=1,
            timestamps=np.array([0.0]),
            joint_positions=np.ones((1, 4)),
            joint_velocities=np.full((1, 4), 2.0),
            end_effector_poses=np.full((1, 6), 0.5),
            gripper_states=np.array([0.7]),
        )

        assert points[0].joint_velocities == [2.0, 2.0, 2.0, 2.0]
        assert points[0].end_effector_pose == [0.5] * 6
        assert points[0].gripper_state == pytest.approx(0.7)

    def test_clamp_gripper(self):
        from src.api.services.dataset_service.base import build_trajectory

        points = build_trajectory(
            length=2,
            timestamps=np.array([0.0, 1.0]),
            joint_positions=np.zeros((2, 6)),
            gripper_states=np.array([-0.5, 1.5]),
            clamp_gripper=True,
        )

        assert points[0].gripper_state == 0.0
        assert points[1].gripper_state == 1.0

    def test_defaults_for_missing_arrays(self):
        from src.api.services.dataset_service.base import build_trajectory

        points = build_trajectory(
            length=1,
            timestamps=np.array([0.0]),
            joint_positions=np.ones((1, 6)),
        )

        assert points[0].joint_velocities == [0.0] * 6
        assert points[0].end_effector_pose == [0.0] * 6
        assert points[0].gripper_state == 0.0
