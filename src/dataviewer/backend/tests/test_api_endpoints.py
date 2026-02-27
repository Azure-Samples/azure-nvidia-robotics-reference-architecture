"""
Integration tests for dataset API endpoints against a LeRobot dataset.

Tests the full HTTP round-trip through FastAPI routes, verifying response
schemas, status codes, pagination, and data integrity.
"""


class TestHealthEndpoint:
    """Verify the health check still works with the real environment."""

    def test_health(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.json() == {"status": "healthy"}


class TestListDatasets:
    """GET /api/datasets"""

    def test_returns_dataset(self, client, dataset_id):
        resp = client.get("/api/datasets")
        assert resp.status_code == 200
        datasets = resp.json()
        ids = [d["id"] for d in datasets]
        assert dataset_id in ids

    def test_dataset_schema(self, client, dataset_id):
        resp = client.get("/api/datasets")
        ds = next(d for d in resp.json() if d["id"] == dataset_id)
        assert ds["total_episodes"] > 0
        assert ds["fps"] > 0
        assert "features" in ds


class TestGetDataset:
    """GET /api/datasets/{dataset_id}"""

    def test_found(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}")
        assert resp.status_code == 200
        data = resp.json()
        assert data["id"] == dataset_id
        assert data["total_episodes"] > 0

    def test_not_found(self, client):
        resp = client.get("/api/datasets/nonexistent")
        assert resp.status_code == 404


class TestCapabilities:
    """GET /api/datasets/{dataset_id}/capabilities"""

    def test_capabilities(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/capabilities")
        assert resp.status_code == 200
        caps = resp.json()
        assert caps["is_lerobot_dataset"] is True
        assert caps["lerobot_support"] is True
        assert caps["episode_count"] > 0


class TestListEpisodes:
    """GET /api/datasets/{dataset_id}/episodes"""

    def test_default(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes")
        assert resp.status_code == 200
        episodes = resp.json()
        assert len(episodes) > 0

    def test_pagination(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes?offset=0&limit=5")
        assert resp.status_code == 200
        episodes = resp.json()
        assert len(episodes) == 5
        assert episodes[0]["index"] == 0
        assert episodes[4]["index"] == 4

    def test_limit_1(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes?limit=1")
        assert resp.status_code == 200
        episodes = resp.json()
        assert len(episodes) == 1

    def test_offset_beyond_range(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes?offset=100000")
        assert resp.status_code == 200
        assert resp.json() == []

    def test_episode_meta_schema(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes?limit=1")
        ep = resp.json()[0]
        assert "index" in ep
        assert "length" in ep
        assert "task_index" in ep
        assert "has_annotations" in ep
        assert ep["length"] > 0

    def test_filter_task_index(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes?task_index=0")
        assert resp.status_code == 200
        assert len(resp.json()) > 0

    def test_dataset_not_found(self, client):
        resp = client.get("/api/datasets/nonexistent/episodes")
        assert resp.status_code == 200
        assert resp.json() == []


class TestGetEpisode:
    """GET /api/datasets/{dataset_id}/episodes/{episode_idx}"""

    def test_first_episode(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/0")
        assert resp.status_code == 200
        data = resp.json()
        assert data["meta"]["index"] == 0
        assert data["meta"]["length"] > 0
        assert len(data["trajectory_data"]) > 0

    def test_last_episode(self, client, dataset_id):
        # Get total episodes to find last index
        ds_resp = client.get(f"/api/datasets/{dataset_id}")
        total = ds_resp.json()["total_episodes"]
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/{total - 1}")
        assert resp.status_code == 200
        data = resp.json()
        assert data["meta"]["index"] == total - 1

    def test_trajectory_point_schema(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/0")
        pt = resp.json()["trajectory_data"][0]
        assert "timestamp" in pt
        assert "frame" in pt
        assert "joint_positions" in pt
        assert "joint_velocities" in pt
        assert len(pt["joint_positions"]) > 0
        assert len(pt["joint_velocities"]) > 0

    def test_video_urls_present(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/0")
        urls = resp.json()["video_urls"]
        assert len(urls) > 0

    def test_episode_out_of_range(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/9999")
        assert resp.status_code in (200, 404)
        if resp.status_code == 200:
            data = resp.json()
            assert data["trajectory_data"] == []


class TestGetTrajectory:
    """GET /api/datasets/{dataset_id}/episodes/{episode_idx}/trajectory"""

    def test_trajectory_data(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/0/trajectory")
        assert resp.status_code == 200
        traj = resp.json()
        assert len(traj) > 0

    def test_trajectory_timestamps_ordered(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/0/trajectory")
        traj = resp.json()
        timestamps = [pt["timestamp"] for pt in traj]
        for i in range(1, len(timestamps)):
            assert timestamps[i] >= timestamps[i - 1]


class TestGetCameras:
    """GET /api/datasets/{dataset_id}/episodes/{episode_idx}/cameras"""

    def test_cameras(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/0/cameras")
        assert resp.status_code == 200
        cameras = resp.json()
        assert len(cameras) > 0


class TestGetVideo:
    """GET /api/datasets/{dataset_id}/episodes/{episode_idx}/video/{camera}"""

    def test_video_stream(self, client, dataset_id):
        # Discover first camera dynamically
        cam_resp = client.get(f"/api/datasets/{dataset_id}/episodes/0/cameras")
        cameras = cam_resp.json()
        assert len(cameras) > 0
        camera = cameras[0]
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/0/video/{camera}")
        assert resp.status_code == 200
        assert "video" in resp.headers.get("content-type", "")

    def test_video_nonexistent_camera(self, client, dataset_id):
        resp = client.get(f"/api/datasets/{dataset_id}/episodes/0/video/fake_camera")
        assert resp.status_code == 404
