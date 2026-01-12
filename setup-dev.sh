#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"

echo "Setting up local development environment..."

if ! command -v uv &> /dev/null; then
    echo "Installing uv package manager..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi

PYTHON_VERSION="$(cat "${SCRIPT_DIR}/.python-version")"
echo "Python version from .python-version: ${PYTHON_VERSION}"

if [[ ! -d "${VENV_DIR}" ]]; then
    echo "Creating virtual environment at ${VENV_DIR} with Python ${PYTHON_VERSION}..."
    uv venv "${VENV_DIR}" --python "${PYTHON_VERSION}"
else
    echo "Virtual environment already exists at ${VENV_DIR}"
fi

echo "Syncing dependencies from pyproject.toml..."
uv sync

echo "Locking dependencies..."
uv lock

echo ""
echo "Setting up IsaacLab for local development..."
ISAACLAB_DIR="${SCRIPT_DIR}/external/IsaacLab"

if [[ -d "${ISAACLAB_DIR}" ]]; then
    echo "IsaacLab already cloned at ${ISAACLAB_DIR}"
    echo "To update, run: cd ${ISAACLAB_DIR} && git pull"
else
    echo "Cloning IsaacLab for intellisense/Pylance support..."
    mkdir -p "${SCRIPT_DIR}/external"
    git clone https://github.com/isaac-sim/IsaacLab.git "${ISAACLAB_DIR}"
    echo "✓ IsaacLab cloned successfully"
fi

echo ""
echo "✓ Development environment setup complete!"
echo ""
echo "To activate the environment, run:"
echo "  source .venv/bin/activate"
echo ""
echo "Or use uv run to execute commands directly:"
echo "  uv run python main.py"
echo ""
echo "Python path: ${VENV_DIR}/bin/python"
