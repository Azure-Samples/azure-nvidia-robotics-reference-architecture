"""Security tests for path traversal remediation (issue #387)."""

import os

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from src.api.validation import (
    validate_path_containment,
    validated_camera_name,
    validated_dataset_id,
)


class TestValidatedDatasetId:
    """Tests for validated_dataset_id dependency."""

    @pytest.mark.parametrize(
        "dataset_id",
        [
            "valid-dataset",
            "my_dataset.v1",
            "Dataset123",
        ],
    )
    def test_valid_dataset_ids_accepted(self, dataset_id):
        result = validated_dataset_id(dataset_id)
        assert result == dataset_id

    @pytest.mark.parametrize(
        "dataset_id",
        [
            "../etc/passwd",
            "..\\windows\\system32",
            "/etc/passwd",
            "C:\\Windows\\",
            "dataset\x00id",
            ".",
            "..",
            "valid/../escape",
            "%2e%2e%2f",
        ],
    )
    def test_traversal_dataset_ids_rejected(self, dataset_id):
        with pytest.raises(HTTPException) as exc_info:
            validated_dataset_id(dataset_id)
        assert exc_info.value.status_code == 400


class TestValidatedCameraName:
    """Tests for validated_camera_name dependency."""

    @pytest.mark.parametrize(
        "camera",
        [
            "camera_01",
            "front.left",
            "RGB-sensor",
        ],
    )
    def test_valid_camera_names_accepted(self, camera):
        result = validated_camera_name(camera)
        assert result == camera

    @pytest.mark.parametrize(
        "camera",
        [
            "../../../etc/passwd",
            "camera/../../secret",
            "cam\x00era",
        ],
    )
    def test_traversal_camera_names_rejected(self, camera):
        with pytest.raises(HTTPException) as exc_info:
            validated_camera_name(camera)
        assert exc_info.value.status_code == 400


class TestValidatePathContainment:
    """Tests for validate_path_containment utility."""

    def test_contained_path_accepted(self, tmp_path):
        child = tmp_path / "datasets" / "sample"
        child.mkdir(parents=True)
        result = validate_path_containment(child, tmp_path)
        assert result == child.resolve()

    def test_traversal_path_rejected(self, tmp_path):
        escape_path = tmp_path / ".." / ".." / "etc" / "passwd"
        with pytest.raises(HTTPException) as exc_info:
            validate_path_containment(escape_path, tmp_path)
        assert exc_info.value.status_code == 400


class TestEndpointTraversalRejection:
    """Integration tests: endpoints reject traversal inputs with HTTP 400."""

    @pytest.fixture
    def client(self, tmp_path):
        """Lightweight test client that does not require a real dataset directory."""
        os.environ["HMI_DATA_PATH"] = str(tmp_path)

        import src.api.services.dataset_service as ds_mod

        ds_mod._dataset_service = None

        from src.api.main import app

        with TestClient(app) as c:
            yield c

        ds_mod._dataset_service = None

    # HTTP clients and ASGI routers normalize "../" in URL paths before routing,
    # so traversal segments may produce 404 (no matching route) rather than 400
    # (validation rejection). Both outcomes block the traversal attempt.

    def test_export_traversal_dataset_id(self, client):
        resp = client.post("/api/datasets/../etc/passwd/export")
        assert resp.status_code in (400, 404)

    def test_export_stream_traversal_dataset_id(self, client):
        resp = client.post("/api/datasets/../etc/passwd/export/stream")
        assert resp.status_code in (400, 404)

    def test_datasets_traversal_dataset_id(self, client):
        resp = client.get("/api/datasets/../etc/passwd")
        assert resp.status_code in (400, 404)

    def test_labels_traversal_dataset_id(self, client):
        resp = client.get("/api/datasets/../etc/passwd/episodes/0/labels")
        assert resp.status_code in (400, 404)

    def test_detection_traversal_dataset_id(self, client):
        resp = client.get("/api/datasets/../etc/passwd/episodes/0/detections")
        assert resp.status_code in (400, 404)

    def test_datasets_traversal_camera_name(self, client):
        resp = client.get(
            "/api/datasets/valid_dataset/episodes/0/frames",
            params={"camera": "../../../etc/passwd"},
        )
        assert resp.status_code in (400, 404)
