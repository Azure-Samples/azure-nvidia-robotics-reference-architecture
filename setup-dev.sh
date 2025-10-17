#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"

echo "Setting up local development environment..."

if command -v pyenv &> /dev/null; then
    PYTHON_VERSION="$(cat "${SCRIPT_DIR}/.python-version")"
    echo "Python version from .python-version: ${PYTHON_VERSION}"
    echo "Installing Python ${PYTHON_VERSION} via pyenv..."
    pyenv install -s "${PYTHON_VERSION}"
fi

echo "Using pyenv Python $(python --version)"

if [[ ! -d "${VENV_DIR}" ]]; then
    echo "Creating virtual environment at ${VENV_DIR}..."
    python -m venv "${VENV_DIR}"
else
    echo "Virtual environment already exists at ${VENV_DIR}"
fi

echo "Activating virtual environment..."
source "${VENV_DIR}/bin/activate"

echo "Upgrading pip..."
pip install --upgrade pip

echo "Installing root dependencies..."
pip install -r "${SCRIPT_DIR}/requirements.txt"

echo "Installing training dependencies..."
pip install -r "${SCRIPT_DIR}/src/training/requirements.txt"

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
echo "Python path: ${VENV_DIR}/bin/python"
