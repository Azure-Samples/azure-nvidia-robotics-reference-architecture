# Backend Implementation Guide: Robotic Episode Annotation System

**Target Audience**: Backend developers implementing the annotation system in any language/framework
**Reference Implementation**: Python with FastAPI
**Last Updated**: February 10, 2026

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Project Structure](#2-project-structure)
3. [Data Models and Type Definitions](#3-data-models-and-type-definitions)
4. [API Endpoint Implementation](#4-api-endpoint-implementation)
5. [Storage Backend Abstraction](#5-storage-backend-abstraction)
6. [Business Logic Services](#6-business-logic-services)
7. [AI Analysis Engine](#7-ai-analysis-engine)
8. [Export Pipeline](#8-export-pipeline)
9. [Error Handling and Validation](#9-error-handling-and-validation)
10. [Testing Strategy](#10-testing-strategy)
11. [Performance Optimization](#11-performance-optimization)
12. [Deployment Considerations](#12-deployment-considerations)

---

## 1. Architecture Overview

### Layered Architecture

The backend follows a **clean architecture** pattern with clear separation of concerns:

```text
┌─────────────────────────────────────┐
│     HTTP Layer (API Routes)         │  ← FastAPI routers, Express routes, Spring controllers
├─────────────────────────────────────┤
│    Business Logic (Services)        │  ← Dataset service, annotation service, analysis
├─────────────────────────────────────┤
│   Storage Abstraction (Adapters)    │  ← Local, Azure, HuggingFace storage adapters
├─────────────────────────────────────┤
│      Data Access (I/O)              │  ← File I/O, HDF5 readers, database clients
└─────────────────────────────────────┘
```

### Key Design Principles

1. **Dependency Injection**: Services are injected into routes, making testing easier
2. **Interface Segregation**: Storage adapters implement common interfaces
3. **Single Responsibility**: Each service handles one domain area
4. **Technology Agnostic**: Business logic doesn't depend on framework specifics

### Reference: Python/FastAPI Structure

```python
# Example: Dependency injection in FastAPI
from fastapi import APIRouter, Depends

router = APIRouter()

def get_annotation_service() -> AnnotationService:
    """Dependency provider for annotation service."""
    storage = LocalStorageAdapter()  # Or inject from config
    return AnnotationService(storage)

@router.get("/datasets/{dataset_id}/episodes/{episode_idx}/annotations")
async def get_annotations(
    dataset_id: str,
    episode_idx: int,
    service: AnnotationService = Depends(get_annotation_service),
):
    return await service.get_annotation(dataset_id, episode_idx)
```

**Translation to Other Frameworks**:

- **Express.js**: Use middleware injection or factory functions
- **Spring Boot**: Use `@Autowired` or constructor injection
- **Django**: Use service layer pattern with class-based views
- **Go**: Use struct composition and interface types

---

## 2. Project Structure

### Recommended Directory Layout

```text
backend/
├── src/
│   ├── api/                     # HTTP layer
│   │   ├── main.{py,js,java}   # Application entry point
│   │   ├── routers/             # API route handlers (one per resource)
│   │   │   ├── datasets
│   │   │   ├── annotations
│   │   │   ├── detection
│   │   │   ├── export
│   │   │   └── ai_analysis
│   │   ├── models/              # Request/response schemas (DTOs)
│   │   │   ├── annotations
│   │   │   ├── datasources
│   │   │   └── detection
│   │   ├── services/            # Business logic
│   │   │   ├── dataset_service
│   │   │   ├── annotation_service
│   │   │   ├── detection_service
│   │   │   ├── trajectory_analysis
│   │   │   ├── anomaly_detection
│   │   │   ├── clustering
│   │   │   ├── frame_interpolation
│   │   │   └── hdf5_exporter
│   │   └── storage/             # Storage adapters
│   │       ├── base             # Abstract interface
│   │       ├── local
│   │       ├── azure
│   │       └── huggingface
│   └── config/                  # Configuration management
├── tests/                       # Test suite
│   ├── unit/
│   ├── integration/
│   └── fixtures/
├── pyproject.toml / package.json / pom.xml  # Dependencies
└── README.md
```

### Separation of Concerns

- **Routers**: HTTP-specific logic (request parsing, response formatting)
- **Models**: Data transfer objects (JSON serializable)
- **Services**: Business logic (pure functions, no HTTP knowledge)
- **Storage**: Persistence layer (file I/O, database access)

---

## 3. Data Models and Type Definitions

### Type System Requirements

**Use strong typing** to ensure data integrity and self-documenting code:

- **Python**: Pydantic models, dataclasses, or TypedDict
- **TypeScript/JavaScript**: Interfaces or Zod schemas
- **Java**: POJOs with Bean Validation annotations
- **Go**: Structs with JSON tags
- **Rust**: Structs with serde

### Annotation Models - Reference Implementation

#### Python (Pydantic)

```python
from pydantic import BaseModel, Field
from enum import Enum
from datetime import datetime

class TaskCompletenessRating(str, Enum):
    SUCCESS = "success"
    PARTIAL = "partial"
    FAILURE = "failure"
    UNKNOWN = "unknown"

class TaskCompletenessAnnotation(BaseModel):
    rating: TaskCompletenessRating
    confidence: int = Field(ge=1, le=5)
    completion_percentage: int | None = Field(None, ge=0, le=100)
    failure_reason: str | None = None
    subtask_reached: str | None = None

    model_config = {"use_enum_values": True}

class TrajectoryQualityMetrics(BaseModel):
    smoothness: int = Field(ge=1, le=5)
    efficiency: int = Field(ge=1, le=5)
    safety: int = Field(ge=1, le=5)
    precision: int = Field(ge=1, le=5)

class Anomaly(BaseModel):
    id: str
    type: str  # enum in production
    severity: str  # enum in production
    frame_range: tuple[int, int]
    timestamp: tuple[float, float]
    description: str
    auto_detected: bool = False
    verified: bool = False

class EpisodeAnnotation(BaseModel):
    annotator_id: str
    timestamp: datetime
    task_completeness: TaskCompletenessAnnotation
    trajectory_quality: TrajectoryQualityMetrics
    data_quality: dict  # Simplified for brevity
    anomalies: list[Anomaly]
    notes: str | None = None

class EpisodeAnnotationFile(BaseModel):
    schema_version: str = "1.0"
    episode_index: int
    dataset_id: str
    annotations: list[EpisodeAnnotation]
```

**Key Patterns**:

1. **Enums for fixed sets**: Prevents invalid values
2. **Field validation**: `ge` (greater/equal), `le` (less/equal) for ranges
3. **Optional fields**: Use `| None` or `Optional[T]`
4. **Nested models**: Composition for complex structures

#### Translation to TypeScript

```typescript
type TaskCompletenessRating = 'success' | 'partial' | 'failure' | 'unknown';

interface TaskCompletenessAnnotation {
  rating: TaskCompletenessRating;
  confidence: 1 | 2 | 3 | 4 | 5;  // Literal union for validation
  completionPercentage?: number;
  failureReason?: string;
  subtaskReached?: string;
}

interface EpisodeAnnotation {
  annotatorId: string;
  timestamp: string;  // ISO 8601
  taskCompleteness: TaskCompletenessAnnotation;
  trajectoryQuality: TrajectoryQualityMetrics;
  dataQuality: DataQualityAnnotation;
  anomalies: Anomaly[];
  notes?: string;
}
```

**Runtime Validation**: Use Zod, io-ts, or class-validator for runtime checking in JavaScript/TypeScript.

### Dataset and Episode Models

```python
class EpisodeMeta(BaseModel):
    """Lightweight episode metadata for list views."""
    index: int = Field(ge=0)
    length: int = Field(ge=0)
    task_index: int = Field(ge=0)
    has_annotations: bool = False

class TrajectoryPoint(BaseModel):
    """Single trajectory sample."""
    timestamp: float = Field(ge=0)
    frame: int = Field(ge=0)
    joint_positions: list[float]
    joint_velocities: list[float]
    end_effector_pose: list[float]
    gripper_state: float = Field(ge=0, le=1)

class EpisodeData(BaseModel):
    """Complete episode data for viewing."""
    meta: EpisodeMeta
    video_urls: dict[str, str]  # camera_name -> URL
    trajectory_data: list[TrajectoryPoint]

class DatasetInfo(BaseModel):
    """Dataset metadata."""
    id: str
    name: str
    total_episodes: int = Field(ge=0)
    fps: float = Field(gt=0)
    features: dict[str, dict]  # feature_name -> schema
    tasks: list[dict]  # task definitions
```

---

## 4. API Endpoint Implementation

### RESTful Route Design

Follow REST conventions for predictable APIs:

| HTTP Method | Endpoint | Purpose |
| ----------- | -------- | ------- |
| GET | `/datasets` | List all datasets |
| GET | `/datasets/{id}` | Get dataset metadata |
| GET | `/datasets/{id}/episodes` | List episodes (paginated) |
| GET | `/datasets/{id}/episodes/{idx}` | Get episode data |
| GET | `/datasets/{id}/episodes/{idx}/annotations` | Get annotations |
| PUT | `/datasets/{id}/episodes/{idx}/annotations` | Save annotations |
| DELETE | `/datasets/{id}/episodes/{idx}/annotations` | Delete annotations |
| POST | `/datasets/{id}/episodes/{idx}/detect` | Run object detection |

### Example: Dataset Listing Endpoint

#### Python/FastAPI

```python
from fastapi import APIRouter, Depends, HTTPException, Query

router = APIRouter()

@router.get("/datasets", response_model=list[DatasetInfo])
async def list_datasets(
    service: DatasetService = Depends(get_dataset_service),
) -> list[DatasetInfo]:
    """List all available datasets.

    Returns metadata for all configured datasets including episode counts,
    FPS, features, and available tasks.
    """
    return await service.list_datasets()

@router.get("/datasets/{dataset_id}/episodes", response_model=list[EpisodeMeta])
async def list_episodes(
    dataset_id: str,
    offset: int = Query(0, ge=0, description="Number of episodes to skip"),
    limit: int = Query(100, ge=1, le=1000, description="Maximum episodes to return"),
    has_annotations: bool | None = Query(None, description="Filter by annotation status"),
    task_index: int | None = Query(None, ge=0, description="Filter by task index"),
    service: DatasetService = Depends(get_dataset_service),
) -> list[EpisodeMeta]:
    """List episodes for a dataset with optional filtering."""
    return await service.list_episodes(
        dataset_id,
        offset=offset,
        limit=limit,
        has_annotations=has_annotations,
        task_index=task_index,
    )
```

**Key Features**:

- **Type annotations**: `response_model` ensures serialization matches schema
- **Query parameters**: `Query()` for validation and documentation
- **Dependency injection**: `Depends()` for service instances
- **Async/await**: Non-blocking I/O for better concurrency

#### Translation to Express.js

```javascript
const express = require('express');
const router = express.Router();

router.get('/datasets', async (req, res, next) => {
  try {
    const service = getDatasetService();
    const datasets = await service.listDatasets();
    res.json(datasets);
  } catch (error) {
    next(error);  // Pass to error handler
  }
});

router.get('/datasets/:datasetId/episodes', async (req, res, next) => {
  try {
    const { datasetId } = req.params;
    const { offset = 0, limit = 100, has_annotations, task_index } = req.query;

    // Validate query params
    if (offset < 0 || limit < 1 || limit > 1000) {
      return res.status(400).json({ detail: 'Invalid query parameters' });
    }

    const service = getDatasetService();
    const episodes = await service.listEpisodes(datasetId, {
      offset: parseInt(offset),
      limit: parseInt(limit),
      hasAnnotations: has_annotations,
      taskIndex: task_index ? parseInt(task_index) : undefined,
    });

    res.json(episodes);
  } catch (error) {
    next(error);
  }
});

module.exports = router;
```

### Annotation CRUD Endpoints

```python
@router.get(
    "/datasets/{dataset_id}/episodes/{episode_idx}/annotations",
    response_model=EpisodeAnnotationFile,
)
async def get_annotations(
    dataset_id: str,
    episode_idx: int,
    service: AnnotationService = Depends(get_annotation_service),
) -> EpisodeAnnotationFile:
    """Get annotations for a specific episode."""
    annotation = await service.get_annotation(dataset_id, episode_idx)
    if annotation is None:
        # Return empty annotation file if none exists
        return EpisodeAnnotationFile(
            episode_index=episode_idx,
            dataset_id=dataset_id,
        )
    return annotation

@router.put(
    "/datasets/{dataset_id}/episodes/{episode_idx}/annotations",
    response_model=EpisodeAnnotationFile,
)
async def save_annotations(
    dataset_id: str,
    episode_idx: int,
    annotation: EpisodeAnnotation,
    service: AnnotationService = Depends(get_annotation_service),
) -> EpisodeAnnotationFile:
    """Save or update annotations for an episode."""
    return await service.save_annotation(dataset_id, episode_idx, annotation)

@router.delete(
    "/datasets/{dataset_id}/episodes/{episode_idx}/annotations",
)
async def delete_annotations(
    dataset_id: str,
    episode_idx: int,
    annotator_id: str | None = None,
    service: AnnotationService = Depends(get_annotation_service),
) -> dict:
    """Delete annotations for an episode."""
    deleted = await service.delete_annotation(dataset_id, episode_idx, annotator_id)
    return {"deleted": deleted, "episode_index": episode_idx}
```

### Image Serving Endpoint

Serve video frames as JPEG images:

```python
from fastapi.responses import Response

@router.get("/datasets/{dataset_id}/episodes/{episode_idx}/frames/{frame_idx}")
async def get_frame_image(
    dataset_id: str,
    episode_idx: int,
    frame_idx: int,
    camera: str = Query("il-camera", description="Camera name"),
    service: DatasetService = Depends(get_dataset_service),
) -> Response:
    """Get a single frame image as JPEG."""
    image_bytes = await service.get_frame_image(
        dataset_id, episode_idx, frame_idx, camera
    )
    if image_bytes is None:
        raise HTTPException(status_code=404, detail="Frame not found")

    return Response(content=image_bytes, media_type="image/jpeg")
```

**Optimization Tips**:

- Add caching headers (`Cache-Control`, `ETag`)
- Consider using CDN for frequently accessed frames
- Compress images with adjustable quality

---

## 5. Storage Backend Abstraction

### Abstract Storage Interface

Define a common interface that all storage backends implement:

```python
from abc import ABC, abstractmethod

class StorageAdapter(ABC):
    """Abstract base class for annotation storage backends."""

    @abstractmethod
    async def get_annotation(
        self, dataset_id: str, episode_index: int
    ) -> EpisodeAnnotationFile | None:
        """Retrieve annotations for an episode."""
        pass

    @abstractmethod
    async def save_annotation(
        self, dataset_id: str, episode_index: int, annotation: EpisodeAnnotationFile
    ) -> None:
        """Save annotations for an episode."""
        pass

    @abstractmethod
    async def list_annotated_episodes(self, dataset_id: str) -> list[int]:
        """List all episode indices with annotations."""
        pass

    @abstractmethod
    async def delete_annotation(self, dataset_id: str, episode_index: int) -> bool:
        """Delete annotations for an episode."""
        pass
```

**Benefits**:

- Swap storage backends without changing business logic
- Easy mocking for tests
- Support multiple backends simultaneously

### Local Filesystem Implementation

```python
import json
from pathlib import Path
import aiofiles

class LocalStorageAdapter(StorageAdapter):
    """Store annotations as JSON files on local filesystem."""

    def __init__(self, base_path: Path):
        self.base_path = base_path
        self.base_path.mkdir(parents=True, exist_ok=True)

    def _get_annotation_path(self, dataset_id: str, episode_index: int) -> Path:
        """Get path for annotation file."""
        return self.base_path / dataset_id / f"episode_{episode_index:06d}.json"

    async def get_annotation(
        self, dataset_id: str, episode_index: int
    ) -> EpisodeAnnotationFile | None:
        """Load annotation from JSON file."""
        path = self._get_annotation_path(dataset_id, episode_index)
        if not path.exists():
            return None

        async with aiofiles.open(path, 'r') as f:
            data = await f.read()
            return EpisodeAnnotationFile.model_validate_json(data)

    async def save_annotation(
        self, dataset_id: str, episode_index: int, annotation: EpisodeAnnotationFile
    ) -> None:
        """Save annotation to JSON file."""
        path = self._get_annotation_path(dataset_id, episode_index)
        path.parent.mkdir(parents=True, exist_ok=True)

        # Atomic write: write to temp file, then rename
        temp_path = path.with_suffix('.tmp')
        async with aiofiles.open(temp_path, 'w') as f:
            await f.write(annotation.model_dump_json(indent=2))

        temp_path.replace(path)  # Atomic on POSIX systems

    async def list_annotated_episodes(self, dataset_id: str) -> list[int]:
        """List episodes with annotations."""
        dataset_dir = self.base_path / dataset_id
        if not dataset_dir.exists():
            return []

        episodes = []
        for file_path in dataset_dir.glob("episode_*.json"):
            # Extract episode index from filename
            try:
                idx = int(file_path.stem.split('_')[1])
                episodes.append(idx)
            except (IndexError, ValueError):
                continue

        return sorted(episodes)

    async def delete_annotation(self, dataset_id: str, episode_index: int) -> bool:
        """Delete annotation file."""
        path = self._get_annotation_path(dataset_id, episode_index)
        if path.exists():
            path.unlink()
            return True
        return False
```

**Key Patterns**:

1. **Atomic writes**: Write to temp file, then rename (prevents corruption)
2. **Directory structure**: Organize by dataset for easy browsing
3. **Async I/O**: Use `aiofiles` for non-blocking file operations
4. **Error handling**: Handle missing files gracefully

### Cloud Storage Implementation (Azure Blob)

```python
from azure.storage.blob.aio import BlobServiceClient

class AzureBlobStorageAdapter(StorageAdapter):
    """Store annotations in Azure Blob Storage."""

    def __init__(self, account_name: str, container_name: str, sas_token: str):
        connection_string = f"DefaultEndpointsProtocol=https;AccountName={account_name};SharedAccessSignature={sas_token}"
        self.client = BlobServiceClient.from_connection_string(connection_string)
        self.container_name = container_name

    def _get_blob_name(self, dataset_id: str, episode_index: int) -> str:
        return f"{dataset_id}/annotations/episode_{episode_index:06d}.json"

    async def get_annotation(
        self, dataset_id: str, episode_index: int
    ) -> EpisodeAnnotationFile | None:
        blob_name = self._get_blob_name(dataset_id, episode_index)
        blob_client = self.client.get_blob_client(self.container_name, blob_name)

        try:
            blob_data = await blob_client.download_blob()
            content = await blob_data.readall()
            return EpisodeAnnotationFile.model_validate_json(content)
        except Exception:
            return None

    async def save_annotation(
        self, dataset_id: str, episode_index: int, annotation: EpisodeAnnotationFile
    ) -> None:
        blob_name = self._get_blob_name(dataset_id, episode_index)
        blob_client = self.client.get_blob_client(self.container_name, blob_name)

        content = annotation.model_dump_json(indent=2)
        await blob_client.upload_blob(content, overwrite=True)

    # ... implement list_annotated_episodes and delete_annotation similarly
```

**Adapt for Other Cloud Providers**:

- **AWS S3**: Use `aioboto3` library
- **GCS**: Use `google-cloud-storage` with asyncio
- **MinIO**: Compatible with S3 API

---

## 6. Business Logic Services

### Dataset Service

Handles dataset discovery, episode loading, and trajectory data access:

```python
class DatasetService:
    """Service for dataset and episode operations."""

    def __init__(self, data_path: Path):
        self.data_path = data_path

    async def list_datasets(self) -> list[DatasetInfo]:
        """List all available datasets."""
        datasets = []
        for dataset_dir in self.data_path.iterdir():
            if not dataset_dir.is_dir():
                continue

            info_file = dataset_dir / "info.json"
            if info_file.exists():
                async with aiofiles.open(info_file, 'r') as f:
                    data = json.loads(await f.read())
                    datasets.append(DatasetInfo(**data))

        return datasets

    async def get_dataset(self, dataset_id: str) -> DatasetInfo | None:
        """Get dataset metadata."""
        info_file = self.data_path / dataset_id / "info.json"
        if not info_file.exists():
            return None

        async with aiofiles.open(info_file, 'r') as f:
            data = json.loads(await f.read())
            return DatasetInfo(**data)

    async def list_episodes(
        self,
        dataset_id: str,
        offset: int = 0,
        limit: int = 100,
        has_annotations: bool | None = None,
        task_index: int | None = None,
    ) -> list[EpisodeMeta]:
        """List episodes with filtering."""
        # In production, this would query an index or database
        # For simplicity, we'll scan episode files

        dataset_dir = self.data_path / dataset_id / "episodes"
        episodes = []

        for episode_file in sorted(dataset_dir.glob("episode_*.hdf5")):
            # Extract episode index from filename
            idx = int(episode_file.stem.split('_')[1])

            # Load metadata (this is simplified - you'd use HDF5 reader)
            meta = EpisodeMeta(
                index=idx,
                length=100,  # Would read from HDF5
                task_index=0,  # Would read from HDF5
                has_annotations=False,  # Would check annotation storage
            )

            # Apply filters
            if has_annotations is not None and meta.has_annotations != has_annotations:
                continue
            if task_index is not None and meta.task_index != task_index:
                continue

            episodes.append(meta)

        # Apply pagination
        return episodes[offset:offset + limit]
```

### Annotation Service

Manages annotation CRUD operations:

```python
class AnnotationService:
    """Service for annotation management."""

    def __init__(self, storage: StorageAdapter):
        self.storage = storage

    async def get_annotation(
        self, dataset_id: str, episode_idx: int
    ) -> EpisodeAnnotationFile | None:
        """Get annotations for an episode."""
        return await self.storage.get_annotation(dataset_id, episode_idx)

    async def save_annotation(
        self, dataset_id: str, episode_idx: int, annotation: EpisodeAnnotation
    ) -> EpisodeAnnotationFile:
        """Save or update an annotation."""
        # Load existing annotation file
        file = await self.storage.get_annotation(dataset_id, episode_idx)
        if file is None:
            file = EpisodeAnnotationFile(
                episode_index=episode_idx,
                dataset_id=dataset_id,
                annotations=[],
            )

        # Update or add annotation for this annotator
        updated = False
        for i, existing in enumerate(file.annotations):
            if existing.annotator_id == annotation.annotator_id:
                file.annotations[i] = annotation
                updated = True
                break

        if not updated:
            file.annotations.append(annotation)

        # Recompute consensus if multiple annotators
        if len(file.annotations) > 1:
            file.consensus = self._compute_consensus(file.annotations)

        await self.storage.save_annotation(dataset_id, episode_idx, file)
        return file

    def _compute_consensus(self, annotations: list[EpisodeAnnotation]) -> dict:
        """Compute consensus from multiple annotations."""
        # Simple majority voting for task completeness
        ratings = [a.task_completeness.rating for a in annotations]
        consensus_rating = max(set(ratings), key=ratings.count)

        # Average for trajectory quality
        avg_score = sum(a.trajectory_quality.overall_score for a in annotations) / len(annotations)

        return {
            "task_completeness": consensus_rating,
            "trajectory_score": round(avg_score, 1),
            "agreement_score": ratings.count(consensus_rating) / len(ratings),
        }

    async def delete_annotation(
        self, dataset_id: str, episode_idx: int, annotator_id: str | None = None
    ) -> bool:
        """Delete annotations."""
        if annotator_id is None:
            # Delete entire file
            return await self.storage.delete_annotation(dataset_id, episode_idx)
        else:
            # Delete specific annotator's contribution
            file = await self.storage.get_annotation(dataset_id, episode_idx)
            if file is None:
                return False

            file.annotations = [
                a for a in file.annotations if a.annotator_id != annotator_id
            ]

            if len(file.annotations) == 0:
                return await self.storage.delete_annotation(dataset_id, episode_idx)
            else:
                await self.storage.save_annotation(dataset_id, episode_idx, file)
                return True
```

---

## 7. AI Analysis Engine

### Trajectory Quality Analysis

Use numerical methods to compute quality metrics:

```python
import numpy as np
from numpy.typing import NDArray
from dataclasses import dataclass

@dataclass
class TrajectoryMetrics:
    smoothness: float  # 0-1, higher is better
    efficiency: float  # 0-1, higher is better
    jitter: float  # Lower is better
    hesitation_count: int
    correction_count: int
    overall_score: int  # 1-5
    flags: list[str]

class TrajectoryAnalyzer:
    """Analyzes robot trajectories to compute quality metrics."""

    def __init__(
        self,
        velocity_threshold: float = 0.01,
        hesitation_min_frames: int = 5,
        jitter_frequency_threshold: float = 10.0,
    ):
        self.velocity_threshold = velocity_threshold
        self.hesitation_min_frames = hesitation_min_frames
        self.jitter_frequency_threshold = jitter_frequency_threshold

    def analyze(
        self,
        positions: NDArray[np.float64],  # Shape: (N, num_joints)
        timestamps: NDArray[np.float64],  # Shape: (N,)
        gripper_states: NDArray[np.float64] | None = None,
    ) -> TrajectoryMetrics:
        """Analyze a trajectory and compute quality metrics."""
        if len(positions) < 3:
            # Too short to analyze
            return TrajectoryMetrics(
                smoothness=1.0,
                efficiency=1.0,
                jitter=0.0,
                hesitation_count=0,
                correction_count=0,
                overall_score=3,
                flags=[],
            )

        # Compute time deltas
        dt = np.diff(timestamps)
        dt = np.where(dt > 0, dt, 1e-6)  # Avoid division by zero

        # Compute derivatives
        velocity = np.diff(positions, axis=0) / dt[:, np.newaxis]
        acceleration = np.diff(velocity, axis=0) / dt[1:, np.newaxis]
        jerk = np.diff(acceleration, axis=0) / dt[2:, np.newaxis]

        # Compute metrics
        smoothness = self._compute_smoothness(jerk)
        efficiency = self._compute_efficiency(positions)
        jitter = self._compute_jitter(velocity, timestamps)
        hesitation_count = self._count_hesitations(velocity)
        correction_count = self._count_corrections(velocity)

        # Determine flags
        flags = self._determine_flags(
            smoothness, jitter, hesitation_count, correction_count
        )

        # Compute overall score
        overall_score = self._compute_overall_score(
            smoothness, efficiency, jitter, hesitation_count, correction_count
        )

        return TrajectoryMetrics(
            smoothness=smoothness,
            efficiency=efficiency,
            jitter=jitter,
            hesitation_count=hesitation_count,
            correction_count=correction_count,
            overall_score=overall_score,
            flags=flags,
        )

    def _compute_smoothness(self, jerk: NDArray[np.float64]) -> float:
        """Compute smoothness from jerk (third derivative)."""
        if len(jerk) == 0:
            return 1.0

        # RMS jerk
        rms_jerk = np.sqrt(np.mean(jerk**2))

        # Normalize to 0-1 scale using sigmoid-like transformation
        smoothness = 1.0 / (1.0 + rms_jerk)
        return float(smoothness)

    def _compute_efficiency(self, positions: NDArray[np.float64]) -> float:
        """Compute path efficiency (actual path vs direct path)."""
        if len(positions) < 2:
            return 1.0

        # Compute actual path length (sum of segment lengths)
        segments = np.diff(positions, axis=0)
        actual_length = np.sum(np.linalg.norm(segments, axis=1))

        # Compute direct path length (start to end)
        direct_length = np.linalg.norm(positions[-1] - positions[0])

        if actual_length == 0:
            return 1.0

        # Efficiency is ratio of direct to actual
        efficiency = direct_length / actual_length
        return float(np.clip(efficiency, 0.0, 1.0))

    def _compute_jitter(
        self, velocity: NDArray[np.float64], timestamps: NDArray[np.float64]
    ) -> float:
        """Compute jitter (high-frequency oscillations)."""
        # Use FFT to find high-frequency components
        velocity_magnitude = np.linalg.norm(velocity, axis=1)

        # Compute power spectral density
        from scipy import signal
        fs = 1.0 / np.mean(np.diff(timestamps[:-1]))  # Sampling frequency
        frequencies, psd = signal.welch(velocity_magnitude, fs=fs)

        # Sum power in high-frequency range
        high_freq_mask = frequencies > self.jitter_frequency_threshold
        jitter = float(np.sum(psd[high_freq_mask]))

        return jitter

    def _count_hesitations(self, velocity: NDArray[np.float64]) -> int:
        """Count hesitation events (near-zero velocity)."""
        velocity_magnitude = np.linalg.norm(velocity, axis=1)
        is_stopped = velocity_magnitude < self.velocity_threshold

        # Find contiguous stopped regions
        hesitations = 0
        current_length = 0
        for stopped in is_stopped:
            if stopped:
                current_length += 1
            else:
                if current_length >= self.hesitation_min_frames:
                    hesitations += 1
                current_length = 0

        return hesitations

    def _count_corrections(self, velocity: NDArray[np.float64]) -> int:
        """Count direction correction events."""
        velocity_magnitude = np.linalg.norm(velocity, axis=1)
        velocity_direction = velocity / (velocity_magnitude[:, np.newaxis] + 1e-10)

        # Compute dot product of consecutive velocity directions
        direction_changes = np.sum(
            velocity_direction[:-1] * velocity_direction[1:], axis=1
        )

        # Count significant direction reversals (dot product < -0.5)
        corrections = np.sum(direction_changes < -0.5)
        return int(corrections)

    def _determine_flags(
        self, smoothness: float, jitter: float, hesitation_count: int, correction_count: int
    ) -> list[str]:
        """Determine quality flags based on metrics."""
        flags = []

        if smoothness < 0.5:
            flags.append("jittery")
        if jitter > 1.0:
            flags.append("jittery")
        if hesitation_count > 3:
            flags.append("hesitation")
        if correction_count > 5:
            flags.append("correction-heavy")

        return flags

    def _compute_overall_score(
        self,
        smoothness: float,
        efficiency: float,
        jitter: float,
        hesitation_count: int,
        correction_count: int,
    ) -> int:
        """Compute overall quality score (1-5)."""
        # Weighted average of normalized metrics
        score = (
            smoothness * 0.3 +
            efficiency * 0.25 +
            (1.0 - min(jitter, 1.0)) * 0.25 +
            max(0, 1.0 - hesitation_count / 10) * 0.1 +
            max(0, 1.0 - correction_count / 20) * 0.1
        )

        # Map 0-1 to 1-5 scale
        return int(np.clip(score * 5, 1, 5))
```

**Key Techniques**:

1. **Numerical differentiation**: Compute velocity, acceleration, jerk
2. **Frequency analysis**: Use FFT (via scipy.signal) for jitter detection
3. **Pattern detection**: Find hesitations and corrections via thresholding
4. **Normalization**: Map metrics to 0-1 or 1-5 scales

### Anomaly Detection

```python
class AnomalyDetector:
    """Detects anomalies in robot trajectories."""

    def detect(
        self,
        positions: NDArray[np.float64],
        timestamps: NDArray[np.float64],
        forces: NDArray[np.float64] | None = None,
    ) -> list[dict]:
        """Detect anomalies in a trajectory."""
        anomalies = []

        # Compute velocity
        dt = np.diff(timestamps)
        velocity = np.diff(positions, axis=0) / dt[:, np.newaxis]

        # Detect velocity spikes using z-score
        velocity_magnitude = np.linalg.norm(velocity, axis=1)
        mean_vel = np.mean(velocity_magnitude)
        std_vel = np.std(velocity_magnitude)
        z_scores = (velocity_magnitude - mean_vel) / (std_vel + 1e-10)

        spike_indices = np.where(np.abs(z_scores) > 3.0)[0]
        for idx in spike_indices:
            anomalies.append({
                "id": f"vel_spike_{idx}",
                "type": "velocity-spike",
                "severity": "medium",
                "frame_range": [int(idx), int(idx) + 1],
                "description": f"Velocity spike detected (z-score: {z_scores[idx]:.2f})",
                "auto_detected": True,
                "verified": False,
            })

        # Detect unexpected stops
        # ... similar logic

        return anomalies
```

---

## 8. Export Pipeline

### HDF5 Export with Edits Applied

```python
import h5py
from PIL import Image
import io

class HDF5Exporter:
    """Exports episodes to HDF5 files with edits applied."""

    def __init__(self, source_path: Path, output_path: Path):
        self.source_path = source_path
        self.output_path = output_path

    def export_episodes(
        self,
        episode_indices: list[int],
        edits_map: dict[int, dict] | None = None,
    ) -> dict:
        """Export episodes with edit operations applied."""
        output_files = []

        for episode_idx in episode_indices:
            # Load source episode
            source_file = self.source_path / f"episode_{episode_idx:06d}.hdf5"
            output_file = self.output_path / f"episode_{episode_idx:06d}.hdf5"

            edits = edits_map.get(episode_idx) if edits_map else None

            with h5py.File(source_file, 'r') as src, h5py.File(output_file, 'w') as dst:
                self._export_episode(src, dst, edits)

            output_files.append(str(output_file))

        return {
            "success": True,
            "output_files": output_files,
        }

    def _export_episode(self, src: h5py.File, dst: h5py.File, edits: dict | None):
        """Export a single episode with edits."""
        # Determine frames to include
        total_frames = src['action'].shape[0]
        removed_frames = set(edits.get('removedFrames', [])) if edits else set()
        included_frames = [i for i in range(total_frames) if i not in removed_frames]

        # Copy trajectory data (excluding removed frames)
        for key in ['action', 'observation.state', 'observation.velocity']:
            if key in src:
                data = src[key][:]
                dst.create_dataset(key, data=data[included_frames])

        # Process video frames with transforms
        for camera_name in ['il-camera', 'et-camera']:
            if f'observation.images.{camera_name}' in src:
                self._export_video_frames(
                    src, dst, camera_name, included_frames, edits
                )

    def _export_video_frames(
        self,
        src: h5py.File,
        dst: h5py.File,
        camera_name: str,
        included_frames: list[int],
        edits: dict | None,
    ):
        """Export video frames with transforms applied."""
        dataset_name = f'observation.images.{camera_name}'
        src_images = src[dataset_name]

        # Get transform for this camera
        transform = self._get_camera_transform(camera_name, edits)

        # Process frames
        processed_frames = []
        for frame_idx in included_frames:
            image = src_images[frame_idx]

            if transform:
                image = self._apply_transform(image, transform)

            processed_frames.append(image)

        # Write to destination
        dst.create_dataset(
            dataset_name,
            data=np.array(processed_frames),
            compression='gzip',
        )

    def _apply_transform(self, image: np.ndarray, transform: dict) -> np.ndarray:
        """Apply image transform (crop, resize, color adjustment)."""
        img = Image.fromarray(image)

        # Apply crop
        if 'crop' in transform:
            crop = transform['crop']
            img = img.crop((crop['x'], crop['y'],
                           crop['x'] + crop['width'],
                           crop['y'] + crop['height']))

        # Apply resize
        if 'resize' in transform:
            resize = transform['resize']
            img = img.resize((resize['width'], resize['height']), Image.LANCZOS)

        # Apply color adjustments (using PIL ImageEnhance)
        # ... implement brightness, contrast, etc.

        return np.array(img)
```

**Performance Optimization**:

- Process frames in batches
- Use multiprocessing for parallel frame processing
- Stream data to avoid loading entire episode in memory

---

## 9. Error Handling and Validation

### Input Validation

Use schema validation libraries:

```python
from pydantic import BaseModel, validator, Field

class DetectionRequest(BaseModel):
    frames: list[int] | None = None
    confidence: float = Field(default=0.25, ge=0.0, le=1.0)
    model: str = Field(default="yolo11n")

    @validator('frames')
    def validate_frames(cls, v):
        if v is not None and len(v) == 0:
            raise ValueError("frames list cannot be empty")
        return v

    @validator('model')
    def validate_model(cls, v):
        allowed = ['yolo11n', 'yolo11s', 'yolo11m', 'yolo11l', 'yolo11x']
        if v not in allowed:
            raise ValueError(f"model must be one of {allowed}")
        return v
```

### Custom Exception Classes

```python
class DatasetNotFoundError(Exception):
    """Dataset does not exist."""
    pass

class EpisodeNotFoundError(Exception):
    """Episode does not exist."""
    pass

class StorageError(Exception):
    """Storage operation failed."""
    pass

# Usage in routes
@router.get("/datasets/{dataset_id}")
async def get_dataset(dataset_id: str, service: DatasetService = Depends()):
    try:
        dataset = await service.get_dataset(dataset_id)
        if dataset is None:
            raise DatasetNotFoundError(f"Dataset '{dataset_id}' not found")
        return dataset
    except DatasetNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Unexpected error loading dataset")
        raise HTTPException(status_code=500, detail="Internal server error")
```

---

## 10. Testing Strategy

### Unit Tests

Test services in isolation with mocked dependencies:

```python
import pytest
from unittest.mock import AsyncMock, MagicMock

@pytest.mark.asyncio
async def test_save_annotation_creates_new_file():
    # Arrange
    storage = AsyncMock(spec=StorageAdapter)
    storage.get_annotation.return_value = None  # No existing annotation

    service = AnnotationService(storage)
    annotation = EpisodeAnnotation(
        annotator_id="user1",
        timestamp=datetime.now(),
        # ... other fields
    )

    # Act
    result = await service.save_annotation("dataset1", 0, annotation)

    # Assert
    assert len(result.annotations) == 1
    assert result.annotations[0].annotator_id == "user1"
    storage.save_annotation.assert_called_once()

@pytest.mark.asyncio
async def test_trajectory_analyzer_computes_metrics():
    analyzer = TrajectoryAnalyzer()

    # Create simple trajectory (straight line)
    positions = np.array([[0, 0, 0], [1, 1, 1], [2, 2, 2]], dtype=np.float64)
    timestamps = np.array([0.0, 0.1, 0.2], dtype=np.float64)

    metrics = analyzer.analyze(positions, timestamps)

    assert metrics.smoothness > 0.9  # Should be smooth
    assert metrics.efficiency > 0.9  # Should be efficient (straight line)
    assert metrics.hesitation_count == 0
```

### Integration Tests

Test API endpoints with real services and in-memory storage:

```python
from fastapi.testclient import TestClient

def test_list_episodes_returns_paginated_results():
    client = TestClient(app)

    response = client.get("/datasets/test_dataset/episodes?offset=0&limit=10")

    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) <= 10

def test_save_annotation_requires_valid_schema():
    client = TestClient(app)

    invalid_annotation = {
        "annotator_id": "user1",
        # Missing required fields
    }

    response = client.put(
        "/datasets/test_dataset/episodes/0/annotations",
        json=invalid_annotation,
    )

    assert response.status_code == 422  # Validation error
```

---

## 11. Performance Optimization

### Caching Strategies

```python
from functools import lru_cache
import asyncio

class DatasetService:
    def __init__(self):
        self._dataset_cache = {}
        self._cache_lock = asyncio.Lock()

    async def get_dataset(self, dataset_id: str) -> DatasetInfo | None:
        # Check cache
        async with self._cache_lock:
            if dataset_id in self._dataset_cache:
                return self._dataset_cache[dataset_id]

        # Load from disk
        dataset = await self._load_dataset_from_disk(dataset_id)

        # Update cache
        async with self._cache_lock:
            self._dataset_cache[dataset_id] = dataset

        return dataset
```

### Database Indexing

If using a database for episode metadata:

```sql
-- Index for episode listing queries
CREATE INDEX idx_episodes_dataset_task ON episodes(dataset_id, task_index);
CREATE INDEX idx_episodes_annotations ON episodes(dataset_id, has_annotations);

-- Index for annotation lookups
CREATE INDEX idx_annotations_dataset_episode ON annotations(dataset_id, episode_index);
```

### Async I/O

Use async/await throughout to avoid blocking:

```python
import asyncio

async def process_batch(episodes: list[int]):
    """Process multiple episodes in parallel."""
    tasks = [process_episode(idx) for idx in episodes]
    results = await asyncio.gather(*tasks)
    return results
```

---

## 12. Deployment Considerations

### Docker Containerization

```dockerfile
# Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY src/ ./src/

# Expose port
EXPOSE 8000

# Run application
CMD ["uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Environment Configuration

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Data paths
    hmi_data_path: Path
    annotation_path: Path

    # Storage backend
    storage_type: str = "local"  # or "azure", "s3"

    # Azure (if using)
    azure_account_name: str | None = None
    azure_container_name: str | None = None
    azure_sas_token: str | None = None

    # Server
    cors_origins: list[str] = ["http://localhost:5173"]

    class Config:
        env_file = ".env"

settings = Settings()
```

### Health Check Endpoint

```python
@router.get("/health")
async def health_check():
    """Health check endpoint for load balancers."""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
    }
```

---

## Summary

This guide provides a comprehensive blueprint for implementing the backend:

1. **Use layered architecture**: Separate HTTP, business logic, and storage layers
2. **Define strong types**: Use Pydantic, TypeScript interfaces, or similar
3. **Abstract storage**: Implement adapter pattern for swappable backends
4. **Leverage async I/O**: Non-blocking operations for better performance
5. **Implement AI analysis**: NumPy/SciPy for trajectory metrics, scikit-learn for clustering
6. **Build robust export**: HDF5 with edit operations applied
7. **Test thoroughly**: Unit, integration, and E2E tests
8. **Optimize performance**: Caching, indexing, batching
9. **Deploy with Docker**: Containerize for consistent environments

Adapt these patterns to your chosen technology stack while preserving the architectural principles.

---

## End of Backend Implementation Guide
