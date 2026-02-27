"""FastAPI application entry point."""

import logging
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Configure logging to show INFO level
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

# Load environment variables from .env file
env_path = Path(__file__).parent.parent.parent / ".env"
load_dotenv(env_path)

# Resolve HMI_DATA_PATH relative to the .env file location (backend/)
import os  # noqa: E402

_data_path = os.environ.get("HMI_DATA_PATH", "")
if _data_path and not Path(_data_path).is_absolute():
    os.environ["HMI_DATA_PATH"] = str((env_path.parent / _data_path).resolve())

from .routers import analysis, annotations, datasets, detection, export, labels  # noqa: E402
from .routes import ai_analysis  # noqa: E402

app = FastAPI(
    title="LeRobot Annotation API",
    description="API for episode annotation in robot demonstration datasets",
    version="0.1.0",
)

# Configure CORS for frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://localhost:5174",
        "http://localhost:5175",
        "http://localhost:5176",
        "http://localhost:5177",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "Accept"],
)

# Include routers - export must come before datasets to match longer paths first
app.include_router(export.router, prefix="/api/datasets", tags=["export"])
app.include_router(detection.router, prefix="/api/datasets", tags=["detection"])
app.include_router(datasets.router, prefix="/api/datasets", tags=["datasets"])
app.include_router(annotations.router, prefix="/api", tags=["annotations"])
app.include_router(analysis.router, prefix="/api/analysis", tags=["analysis"])
app.include_router(ai_analysis.router, prefix="/api", tags=["ai"])
app.include_router(labels.router, prefix="/api/datasets", tags=["labels"])


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}
