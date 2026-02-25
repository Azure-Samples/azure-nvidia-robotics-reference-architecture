"""
Integration tests for DatasetService against a LeRobot dataset.

Tests dataset discovery, episode listing with pagination and filtering,
episode data retrieval, trajectory extraction, and capability reporting.
"""

import os

import pytest

from src.api.services.dataset_service import DatasetService


@pytest.fixture
def service(dataset_base_path):
    """DatasetService pointing to the real datasets directory."""
    return DatasetService(base_path=dataset_base_path)


class TestDatasetDiscovery:
    """Test automatic dataset discovery from the filesystem."""

    @pytest.mark.asyncio
    async def test_list_datasets_finds_dataset(self, service, dataset_id):
        datasets = await service.list_datasets()
        ids = [d.id for d in datasets]
        assert dataset_id in ids

    @pytest.mark.asyncio
    async def test_get_dataset_returns_info(self, service, dataset_id):
        ds = await service.get_dataset(dataset_id)
        assert ds is not None
        assert ds.id == dataset_id
        assert ds.total_episodes > 0
        assert ds.fps > 0

    @pytest.mark.asyncio
    async def test_get_dataset_features(self, service, dataset_id):
        ds = await service.get_dataset(dataset_id)
        assert len(ds.features) > 0

    @pytest.mark.asyncio
    async def test_get_nonexistent_dataset(self, service):
        ds = await service.get_dataset("nonexistent_dataset")
        assert ds is None

    def test_dataset_is_lerobot(self, service, dataset_id):
        service._discover_dataset(dataset_id)
        assert service.dataset_is_lerobot(dataset_id) is True

    def test_dataset_has_no_hdf5(self, service, dataset_id):
        service._discover_dataset(dataset_id)
        assert service.dataset_has_hdf5(dataset_id) is False

    def test_has_lerobot_support(self, service):
        assert service.has_lerobot_support() is True


class TestListEpisodes:
    """Test episode listing with pagination and filtering."""

    @pytest.mark.asyncio
    async def test_default_list(self, service, dataset_id):
        episodes = await service.list_episodes(dataset_id)
        assert len(episodes) > 0

    @pytest.mark.asyncio
    async def test_pagination_offset(self, service, dataset_id):
        all_eps = await service.list_episodes(dataset_id)
        offset = max(len(all_eps) - 4, 0)
        episodes = await service.list_episodes(dataset_id, offset=offset, limit=10)
        assert len(episodes) <= 10
        assert episodes[0].index == offset

    @pytest.mark.asyncio
    async def test_pagination_limit(self, service, dataset_id):
        episodes = await service.list_episodes(dataset_id, offset=0, limit=5)
        assert len(episodes) == 5
        assert episodes[0].index == 0
        assert episodes[4].index == 4

    @pytest.mark.asyncio
    async def test_episode_meta_fields(self, service, dataset_id):
        episodes = await service.list_episodes(dataset_id, limit=1)
        ep = episodes[0]
        assert ep.index == 0
        assert ep.length > 0
        assert ep.task_index >= 0
        assert isinstance(ep.has_annotations, bool)

    @pytest.mark.asyncio
    async def test_filter_has_annotations_false(self, service, dataset_id):
        """With no annotations saved, all episodes should appear."""
        all_eps = await service.list_episodes(dataset_id)
        episodes = await service.list_episodes(dataset_id, has_annotations=False)
        assert len(episodes) == len(all_eps)

    @pytest.mark.asyncio
    async def test_filter_task_index(self, service, dataset_id):
        episodes = await service.list_episodes(dataset_id, task_index=0)
        assert len(episodes) > 0

    @pytest.mark.asyncio
    async def test_filter_task_index_no_match(self, service, dataset_id):
        episodes = await service.list_episodes(dataset_id, task_index=99)
        assert len(episodes) == 0


class TestGetEpisode:
    """Test full episode data retrieval."""

    @pytest.mark.asyncio
    async def test_get_episode_returns_data(self, service, dataset_id):
        ep = await service.get_episode(dataset_id, 0)
        assert ep is not None
        assert ep.meta.index == 0
        assert ep.meta.length > 0

    @pytest.mark.asyncio
    async def test_episode_has_trajectory(self, service, dataset_id):
        ep = await service.get_episode(dataset_id, 0)
        assert len(ep.trajectory_data) > 0

    @pytest.mark.asyncio
    async def test_trajectory_point_fields(self, service, dataset_id):
        ep = await service.get_episode(dataset_id, 0)
        pt = ep.trajectory_data[0]
        assert pt.timestamp >= 0
        assert pt.frame >= 0
        assert len(pt.joint_positions) > 0
        assert len(pt.joint_velocities) > 0

    @pytest.mark.asyncio
    async def test_episode_has_video_urls(self, service, dataset_id):
        ep = await service.get_episode(dataset_id, 0)
        assert len(ep.video_urls) > 0
        first_url = next(iter(ep.video_urls.values()))
        assert f"/api/datasets/{dataset_id}/episodes/0/video/" in first_url

    @pytest.mark.asyncio
    async def test_trajectory_length_matches_meta(self, service, dataset_id):
        ep = await service.get_episode(dataset_id, 0)
        assert ep.meta.length == len(ep.trajectory_data)


class TestTrajectory:
    """Test trajectory-only extraction."""

    @pytest.mark.asyncio
    async def test_get_trajectory(self, service, dataset_id):
        traj = await service.get_episode_trajectory(dataset_id, 0)
        assert len(traj) > 0

    @pytest.mark.asyncio
    async def test_trajectory_timestamps_increase(self, service, dataset_id):
        traj = await service.get_episode_trajectory(dataset_id, 0)
        timestamps = [pt.timestamp for pt in traj]
        for i in range(1, len(timestamps)):
            assert timestamps[i] >= timestamps[i - 1]


class TestCameras:
    """Test camera discovery."""

    @pytest.mark.asyncio
    async def test_get_cameras(self, service, dataset_id):
        cameras = await service.get_episode_cameras(dataset_id, 0)
        assert len(cameras) > 0


class TestVideoFilePath:
    """Test video file serving path resolution."""

    def test_get_video_file_path(self, service, dataset_id):
        service._discover_dataset(dataset_id)
        cameras = list(service._lerobot_loaders[dataset_id].get_cameras(0))
        assert len(cameras) > 0
        path = service.get_video_file_path(dataset_id, 0, cameras[0])
        assert path is not None
        assert os.path.isfile(path)
        assert path.endswith(".mp4")

    def test_get_video_file_path_missing_camera(self, service, dataset_id):
        service._discover_dataset(dataset_id)
        path = service.get_video_file_path(dataset_id, 0, "fake_camera")
        assert path is None
