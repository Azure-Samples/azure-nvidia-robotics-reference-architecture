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

# Install dependencies
uv pip install -e ".[dev,analysis,export]"
```

### Frontend Setup

```bash
cd frontend
npm install
```

## Configuration

Create or edit `backend/.env` to configure your data path:

```env
# Path to the directory containing datasets
# Each subdirectory is treated as a dataset_id
HMI_DATA_PATH=/path/to/your/datasets
```

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

**Environment variables:**

- `BACKEND_PORT` - Backend port (default: 8000)
- `FRONTEND_PORT` - Frontend port (default: 5173)

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
