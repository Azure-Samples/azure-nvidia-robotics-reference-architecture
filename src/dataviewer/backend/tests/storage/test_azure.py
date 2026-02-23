"""
Unit tests for Azure Blob Storage adapter.

These tests use mocking to avoid requiring actual Azure credentials.
"""

import asyncio
import json
from datetime import datetime
from unittest import TestCase
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from src.api.models.annotations import (
    EpisodeAnnotationFile,
    AnnotationMetadata,
    TaskCompletenessAnnotation,
    TaskCompletenessRating,
)
from src.api.storage.base import StorageError


def create_test_annotation(episode_index: int) -> EpisodeAnnotationFile:
    """Create a test annotation file."""
    now = datetime.utcnow()
    return EpisodeAnnotationFile(
        schema_version="1.0",
        episode_index=episode_index,
        metadata=AnnotationMetadata(
            created_at=now,
            updated_at=now,
            annotator_id="test-user",
            review_status="pending",
        ),
        task_completeness=TaskCompletenessAnnotation(
            rating=TaskCompletenessRating.SUCCESS,
            partial_progress_pct=100.0,
            timestamped_ratings=[],
            notes="Test annotation",
        ),
        trajectory_quality=None,
        data_quality=None,
        anomalies=[],
        frame_annotations=[],
        tags=[],
        curriculum=None,
    )


class TestAzureBlobStorageAdapter(TestCase):
    """Tests for AzureBlobStorageAdapter."""

    def setUp(self):
        """Set up test fixtures."""
        self.dataset_id = "test-dataset"

    @patch("src.api.storage.azure.AZURE_AVAILABLE", True)
    @patch("src.api.storage.azure.BlobServiceClient")
    def test_get_annotation_not_found(self, mock_blob_service):
        """Test getting a non-existent annotation returns None."""
        from src.api.storage.azure import AzureBlobStorageAdapter

        # Import the exception we need to mock
        from azure.core.exceptions import ResourceNotFoundError

        # Set up mock to raise ResourceNotFoundError
        mock_client = MagicMock()
        mock_container = MagicMock()
        mock_blob = MagicMock()
        mock_blob.download_blob = AsyncMock(side_effect=ResourceNotFoundError("Not found"))

        mock_container.get_blob_client.return_value = mock_blob
        mock_client.get_container_client.return_value = mock_container

        adapter = AzureBlobStorageAdapter(
            account_name="testaccount",
            container_name="testcontainer",
            sas_token="test-sas-token",
        )
        adapter._client = mock_client

        result = asyncio.run(adapter.get_annotation(self.dataset_id, 0))
        assert result is None

    @patch("src.api.storage.azure.AZURE_AVAILABLE", True)
    @patch("src.api.storage.azure.BlobServiceClient")
    def test_get_annotation_success(self, mock_blob_service):
        """Test successfully retrieving an annotation."""
        from src.api.storage.azure import AzureBlobStorageAdapter

        # Create test annotation data
        annotation = create_test_annotation(episode_index=5)
        annotation_json = json.dumps(annotation.model_dump(mode="json"))

        # Set up mock
        mock_client = MagicMock()
        mock_container = MagicMock()
        mock_blob = MagicMock()

        mock_download = AsyncMock()
        mock_download.readall = AsyncMock(return_value=annotation_json.encode("utf-8"))
        mock_blob.download_blob = AsyncMock(return_value=mock_download)

        mock_container.get_blob_client.return_value = mock_blob
        mock_client.get_container_client.return_value = mock_container

        adapter = AzureBlobStorageAdapter(
            account_name="testaccount",
            container_name="testcontainer",
            sas_token="test-sas-token",
        )
        adapter._client = mock_client

        result = asyncio.run(adapter.get_annotation(self.dataset_id, 5))

        assert result is not None
        assert result.episode_index == 5

    @patch("src.api.storage.azure.AZURE_AVAILABLE", True)
    @patch("src.api.storage.azure.BlobServiceClient")
    def test_save_annotation(self, mock_blob_service):
        """Test saving an annotation."""
        from src.api.storage.azure import AzureBlobStorageAdapter

        # Set up mock
        mock_client = MagicMock()
        mock_container = MagicMock()
        mock_blob = MagicMock()
        mock_blob.upload_blob = AsyncMock()

        mock_container.get_blob_client.return_value = mock_blob
        mock_client.get_container_client.return_value = mock_container

        adapter = AzureBlobStorageAdapter(
            account_name="testaccount",
            container_name="testcontainer",
            sas_token="test-sas-token",
        )
        adapter._client = mock_client

        annotation = create_test_annotation(episode_index=5)
        asyncio.run(adapter.save_annotation(self.dataset_id, 5, annotation))

        # Verify upload was called
        mock_blob.upload_blob.assert_called_once()
        call_args = mock_blob.upload_blob.call_args
        assert call_args[1]["overwrite"] is True
        assert call_args[1]["content_settings"]["content_type"] == "application/json"

    @patch("src.api.storage.azure.AZURE_AVAILABLE", True)
    @patch("src.api.storage.azure.BlobServiceClient")
    def test_list_annotated_episodes(self, mock_blob_service):
        """Test listing annotated episodes."""
        from src.api.storage.azure import AzureBlobStorageAdapter

        # Create mock blob list
        mock_blobs = [
            MagicMock(name="test-dataset/annotations/episodes/episode_000003.json"),
            MagicMock(name="test-dataset/annotations/episodes/episode_000001.json"),
            MagicMock(name="test-dataset/annotations/episodes/episode_000005.json"),
        ]

        # Set up mock
        mock_client = MagicMock()
        mock_container = MagicMock()

        async def mock_list_blobs(name_starts_with):
            for blob in mock_blobs:
                yield blob

        mock_container.list_blobs = mock_list_blobs
        mock_client.get_container_client.return_value = mock_container

        adapter = AzureBlobStorageAdapter(
            account_name="testaccount",
            container_name="testcontainer",
            sas_token="test-sas-token",
        )
        adapter._client = mock_client

        result = asyncio.run(adapter.list_annotated_episodes(self.dataset_id))

        assert result == [1, 3, 5]

    @patch("src.api.storage.azure.AZURE_AVAILABLE", True)
    @patch("src.api.storage.azure.BlobServiceClient")
    def test_delete_annotation_success(self, mock_blob_service):
        """Test deleting an existing annotation."""
        from src.api.storage.azure import AzureBlobStorageAdapter

        # Set up mock
        mock_client = MagicMock()
        mock_container = MagicMock()
        mock_blob = MagicMock()
        mock_blob.delete_blob = AsyncMock()

        mock_container.get_blob_client.return_value = mock_blob
        mock_client.get_container_client.return_value = mock_container

        adapter = AzureBlobStorageAdapter(
            account_name="testaccount",
            container_name="testcontainer",
            sas_token="test-sas-token",
        )
        adapter._client = mock_client

        result = asyncio.run(adapter.delete_annotation(self.dataset_id, 5))

        assert result is True
        mock_blob.delete_blob.assert_called_once()

    @patch("src.api.storage.azure.AZURE_AVAILABLE", True)
    @patch("src.api.storage.azure.BlobServiceClient")
    def test_delete_annotation_not_found(self, mock_blob_service):
        """Test deleting a non-existent annotation returns False."""
        from src.api.storage.azure import AzureBlobStorageAdapter
        from azure.core.exceptions import ResourceNotFoundError

        # Set up mock
        mock_client = MagicMock()
        mock_container = MagicMock()
        mock_blob = MagicMock()
        mock_blob.delete_blob = AsyncMock(side_effect=ResourceNotFoundError("Not found"))

        mock_container.get_blob_client.return_value = mock_blob
        mock_client.get_container_client.return_value = mock_container

        adapter = AzureBlobStorageAdapter(
            account_name="testaccount",
            container_name="testcontainer",
            sas_token="test-sas-token",
        )
        adapter._client = mock_client

        result = asyncio.run(adapter.delete_annotation(self.dataset_id, 5))

        assert result is False

    def test_requires_auth_method(self):
        """Test that adapter requires SAS token or managed identity."""
        from src.api.storage.azure import AzureBlobStorageAdapter

        with pytest.raises(ValueError, match="sas_token or use_managed_identity"):
            AzureBlobStorageAdapter(
                account_name="testaccount",
                container_name="testcontainer",
            )

    @patch("src.api.storage.azure.AZURE_AVAILABLE", True)
    def test_blob_path_format(self):
        """Test blob path formatting."""
        from src.api.storage.azure import AzureBlobStorageAdapter

        adapter = AzureBlobStorageAdapter(
            account_name="testaccount",
            container_name="testcontainer",
            sas_token="test-sas",
        )

        path = adapter._get_blob_path("my-dataset", 42)
        assert path == "my-dataset/annotations/episodes/episode_000042.json"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
