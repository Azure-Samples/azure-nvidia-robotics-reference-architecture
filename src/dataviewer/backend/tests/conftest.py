"""Pytest configuration and shared fixtures for integration tests."""

import os
from pathlib import Path

import pytest
from dotenv import load_dotenv
from fastapi.testclient import TestClient

# Load .env from the backend directory so tests pick up HMI_DATA_PATH / TEST_DATASET_ID
_env_file = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(_env_file)

_raw_data_path = os.environ.get("HMI_DATA_PATH", "")
if _raw_data_path and not Path(_raw_data_path).is_absolute():
    DATASET_BASE_PATH = str((_env_file.parent / _raw_data_path).resolve())
else:
    DATASET_BASE_PATH = _raw_data_path

DATASET_ID = os.environ.get("TEST_DATASET_ID", "")


@pytest.fixture(scope="session")
def dataset_base_path():
    """Absolute path to the directory containing datasets."""
    assert DATASET_BASE_PATH, (
        "HMI_DATA_PATH not set. Configure it in backend/.env or as an environment variable."
    )
    assert os.path.isdir(DATASET_BASE_PATH), (
        f"Dataset base path not found: {DATASET_BASE_PATH}. Set HMI_DATA_PATH env var."
    )
    assert DATASET_ID, (
        "TEST_DATASET_ID not set. Configure it in backend/.env or as an environment variable."
    )
    assert os.path.isdir(os.path.join(DATASET_BASE_PATH, DATASET_ID)), (
        f"Dataset '{DATASET_ID}' not found at {DATASET_BASE_PATH}/{DATASET_ID}"
    )
    return DATASET_BASE_PATH


@pytest.fixture(scope="session")
def dataset_id():
    return DATASET_ID


@pytest.fixture
def client(dataset_base_path):
    """Create a FastAPI test client with HMI_DATA_PATH pointing to the real dataset."""
    os.environ["HMI_DATA_PATH"] = dataset_base_path

    import src.api.services.dataset_service as ds_mod

    ds_mod._dataset_service = None

    from src.api.main import app

    with TestClient(app) as c:
        yield c

    ds_mod._dataset_service = None
