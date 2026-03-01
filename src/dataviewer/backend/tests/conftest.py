"""Pytest configuration and shared fixtures for integration tests."""

import os

import pytest
from fastapi.testclient import TestClient

TEST_DATASET_PATH = os.environ.get(
    "TEST_DATASET_PATH",
    "/home/alizaidi/dev/rl/azure-nvidia-robotics-reference-architecture/datasets",
)

TEST_DATASET_ID = os.environ.get("TEST_DATASET_ID", "sample_lerobot")


@pytest.fixture(scope="session")
def test_dataset_path():
    """Absolute path to the directory containing the test LeRobot dataset."""
    assert os.path.isdir(TEST_DATASET_PATH), f"Dataset base path not found: {TEST_DATASET_PATH}"
    assert os.path.isdir(os.path.join(TEST_DATASET_PATH, TEST_DATASET_ID)), (
        f"LeRobot dataset not found at {TEST_DATASET_PATH}/{TEST_DATASET_ID}"
    )
    return TEST_DATASET_PATH


@pytest.fixture(scope="session")
def test_dataset_id():
    return TEST_DATASET_ID


@pytest.fixture
def client(test_dataset_path):
    """Create a FastAPI test client with HMI_DATA_PATH pointing to the real dataset."""
    os.environ["HMI_DATA_PATH"] = test_dataset_path

    import src.api.services.dataset_service as ds_mod

    ds_mod._dataset_service = None

    from src.api.main import app

    with TestClient(app) as c:
        yield c

    ds_mod._dataset_service = None
