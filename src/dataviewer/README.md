# Dataset Analysis Tool

A full-stack application for analyzing and annotating robotic training data from episode-based datasets. Features include episode browsing, frame annotation, and export capabilities.

## Architecture

- **Backend**: FastAPI (Python) - serves REST API on port 8000
- **Frontend**: React + Vite + TypeScript - runs on port 5173 with API proxy

## Prerequisites

- Python 3.11+
- Node.js 18+
- npm

## Installation

### Backend Setup

```bash
cd backend

# Create virtual environment (using uv)
uv venv --python 3.11
source .venv/bin/activate

# Install dependencies (include 'azure' extra for blob storage support)
uv pip install -e ".[dev,analysis,export,azure]"
```

### Frontend Setup

```bash
cd frontend
npm install
```

## Configuration

Copy `backend/.env.example` to `backend/.env` and set values for your environment.

### Local File Storage (default)

```env
HMI_STORAGE_BACKEND=local
HMI_DATA_PATH=/path/to/your/datasets
```

### Azure Blob Storage

Use this mode when datasets live in Azure Blob Storage. Authentication uses
[DefaultAzureCredential](https://learn.microsoft.com/azure/developer/python/sdk/authentication-overview),
which supports managed identity, workload identity, and Azure CLI credentials
automatically — no SAS token required in AKS or Container Apps.

```env
HMI_STORAGE_BACKEND=azure
AZURE_STORAGE_ACCOUNT_NAME=mystorageaccount
AZURE_STORAGE_DATASET_CONTAINER=datasets
AZURE_STORAGE_ANNOTATION_CONTAINER=annotations
# Leave AZURE_STORAGE_SAS_TOKEN unset to use managed identity (MSI)
```

Expected blob structure:

```
{dataset_id}/meta/info.json
{dataset_id}/meta/tasks.parquet
{dataset_id}/data/chunk-000/file-000.parquet
{dataset_id}/videos/{camera}/chunk-000/file-000.mp4
{dataset_id}/annotations/episodes/episode_000000.json
```

### Full Environment Variable Reference

| Variable | Default | Description |
|---|---|---|
| `HMI_STORAGE_BACKEND` | `local` | Storage backend: `local` or `azure` |
| `HMI_DATA_PATH` | `./data` | Local dataset directory (local mode) |
| `AZURE_STORAGE_ACCOUNT_NAME` | — | Azure Storage account name (azure mode) |
| `AZURE_STORAGE_DATASET_CONTAINER` | — | Blob container for dataset files |
| `AZURE_STORAGE_ANNOTATION_CONTAINER` | — | Blob container for annotations (defaults to dataset container) |
| `AZURE_STORAGE_SAS_TOKEN` | — | SAS token (omit to use DefaultAzureCredential / MSI) |
| `BACKEND_HOST` | `127.0.0.1` | Bind address (`0.0.0.0` for containers) |
| `BACKEND_PORT` | `8000` | API server port |
| `FRONTEND_PORT` | `5173` | Dev server port |
| `CORS_ORIGINS` | localhost ports | Comma-separated allowed CORS origins |

## Running the Application

### Quick Start (Recommended)

```bash
./start.sh
```

This launches both backend and frontend in the correct order, with health checking and graceful shutdown.

**Options:**

```bash
./start.sh --backend   # Start backend only
./start.sh --frontend  # Start frontend only
./start.sh --help      # Show all options
```

### Manual Start

#### Start Backend

```bash
cd backend
source .venv/bin/activate
uvicorn src.api.main:app --reload --port 8000
```

#### Start Frontend

```bash
cd frontend
npm run dev
```

The application will be available at `http://localhost:5173`.

## Container Deployment

### Docker Compose (local)

```bash
# Local storage mode (mount datasets directory)
HMI_LOCAL_DATA_PATH=/path/to/datasets docker compose up --build

# Azure Blob Storage mode
export HMI_STORAGE_BACKEND=azure
export AZURE_STORAGE_ACCOUNT_NAME=mystorageaccount
export AZURE_STORAGE_DATASET_CONTAINER=datasets
export AZURE_STORAGE_ANNOTATION_CONTAINER=annotations
docker compose up --build
```

### Azure Kubernetes Service (AKS) / Container Apps

For AKS with workload identity or Container Apps with managed identity, set:

```env
HMI_STORAGE_BACKEND=azure
AZURE_STORAGE_ACCOUNT_NAME=mystorageaccount
AZURE_STORAGE_DATASET_CONTAINER=datasets
BACKEND_HOST=0.0.0.0
CORS_ORIGINS=https://your-frontend-url.example.com
```

`AZURE_STORAGE_SAS_TOKEN` is **not** needed — `DefaultAzureCredential` automatically
uses the pod/container managed identity when running in Azure.

### Building Images

```bash
# Backend
docker build -t dataviewer-backend ./backend

# Frontend
docker build -t dataviewer-frontend ./frontend
```

## Development

### Backend Development

```bash
# Run tests
cd backend
pytest

# Lint
ruff check src/
```

### Frontend Development

```bash
cd frontend
npm run lint
npm run build
```

## API Documentation

Once the backend is running, visit:

- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`
- Health check: `http://localhost:8000/health`
