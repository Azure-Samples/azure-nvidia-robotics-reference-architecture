---
name: dataviewer
description: 'Start and interact with the Dataset Analysis Tool (dataviewer) for browsing, annotating, and exporting robotic training episodes'
---

# Dataviewer Skill

Launch and interact with the Dataset Analysis Tool — a full-stack application for analyzing and annotating robotic training data from episode-based datasets.

## Prerequisites

| Platform | Requirement |
|----------|-------------|
| All | Python 3.11+, Node.js 18+, npm, `uv` |

The backend virtual environment and frontend `node_modules` are auto-created on first launch by `start.sh`.

## Quick Start

Start the dataviewer with the default dataset path:

```bash
cd src/dataviewer && ./start.sh
```

Start with a custom dataset path:

```bash
cd src/dataviewer && HMI_DATA_PATH=/path/to/datasets ./start.sh
```

## Parameters Reference

| Parameter | Default | Description |
|-----------|---------|-------------|
| `HMI_DATA_PATH` | `../../../datasets` (relative to `backend/`) | Directory containing dataset subdirectories |
| `BACKEND_PORT` | `8000` | FastAPI backend port |
| `FRONTEND_PORT` | `5173` | Vite frontend dev server port |
| `HEALTH_TIMEOUT` | `30` | Seconds to wait for backend health check |

### Dataset Path Configuration

The `HMI_DATA_PATH` environment variable controls which datasets are visible in the app. Each subdirectory under this path is treated as a separate `dataset_id`.

**Methods to set `HMI_DATA_PATH`:**

1. **Environment variable override** (recommended for ad-hoc use):

    ```bash
    HMI_DATA_PATH=/path/to/datasets ./start.sh
    ```

2. **Edit `backend/.env`** (persists across restarts):

    ```env
    HMI_DATA_PATH=/path/to/datasets
    ```

3. **Export before launch** (session-scoped):

    ```bash
    export HMI_DATA_PATH=/path/to/datasets
    cd src/dataviewer && ./start.sh
    ```

When a dataset path is provided, update `backend/.env` so the value persists:

1. Read the current `backend/.env` file.
2. Replace the `HMI_DATA_PATH=` line with the new absolute path.
3. Start the app with `./start.sh`.

## Architecture

```text
src/dataviewer/
├── start.sh              # Orchestrator: launches backend + frontend
├── backend/
│   ├── .env              # HMI_DATA_PATH and test config
│   ├── pyproject.toml    # Python dependencies (uv)
│   └── src/api/
│       ├── main.py       # FastAPI app, CORS, router registration
│       ├── routers/      # REST endpoints: datasets, annotations, labels, export, detection, analysis
│       ├── routes/       # AI analysis routes
│       ├── services/     # Business logic and dataset service
│       ├── models/       # Pydantic models
│       └── storage/      # Persistence layer
├── frontend/
│   ├── vite.config.ts    # Dev server + API proxy to :8000
│   └── src/
│       ├── App.tsx       # Root: dataset selector, episode list, annotation workspace
│       ├── api/          # HTTP client and typed API functions
│       ├── components/   # UI components (annotation, dashboard, episode viewer, export)
│       ├── hooks/        # React Query hooks for datasets, episodes, annotations
│       ├── stores/       # Zustand stores for episode and dataset state
│       └── types/        # TypeScript type definitions
```

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/api/datasets` | GET | List all datasets |
| `/api/datasets/{id}/episodes` | GET | List episodes in a dataset |
| `/api/datasets/{id}/episodes/{idx}` | GET | Get episode data with frames |
| `/api/datasets/{id}/episodes/{idx}/frames/{frame}/image` | GET | Get frame image |
| `/api/datasets/{id}/episodes/{idx}/export` | POST | Export episode data |
| `/api/datasets/{id}/labels` | GET/POST | Manage dataset labels |
| `/api/annotations` | GET/POST/PUT/DELETE | CRUD annotation operations |
| `/api/analysis/*` | GET/POST | Analysis endpoints |
| `http://localhost:8000/docs` | GET | Swagger UI documentation |

## Frontend UI Structure

The React app has these key areas for Playwright interaction:

| Area | Selector Pattern | Description |
|------|-----------------|-------------|
| Header | `header` | Contains title and dataset selector dropdown |
| Dataset selector | `header select` or `header input` | Dropdown (multi-dataset) or text input (single) |
| Episode sidebar | `aside` | Scrollable episode list with selection state |
| Episode item | `aside li button` | Clickable episode entry with index and metadata |
| Main workspace | `main` | Annotation workspace with frame viewer |
| Label filter | Label filter component in sidebar | Filter episodes by annotation labels |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Backend fails to start | Check `backend/.venv` exists; run `cd backend && uv venv --python 3.11 && source .venv/bin/activate && uv pip install -e ".[dev,analysis,export]"` |
| Frontend shows "Loading..." indefinitely | Verify backend is healthy: `curl http://localhost:8000/health` |
| No datasets visible | Check `HMI_DATA_PATH` in `backend/.env` points to a directory with dataset subdirectories |
| Port conflict | Set `BACKEND_PORT` or `FRONTEND_PORT` environment variables |
| CORS errors | Backend allows localhost ports 5173-5177; check the frontend port is in range |

> Brought to you by azure-nvidia-robotics-reference-architecture
