#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
DISABLE_VENV=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --disable-venv)
      DISABLE_VENV=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# shellcheck source=deploy/002-setup/lib/common.sh
source "${SCRIPT_DIR}/deploy/002-setup/lib/common.sh"

# Preamble: Recommend devcontainer for easier setup
echo
echo "💡 RECOMMENDED: Use the Dev Container for the best experience."
echo
echo "The devcontainer includes all tools pre-configured:"
echo "  • Azure CLI, Terraform, kubectl, helm, jq"
echo "  • Python with all dependencies"
echo "  • VS Code extensions for Terraform and Python"
echo
echo "To use:"
echo "  VS Code    → Reopen in Container (F1 → Dev Containers: Reopen)"
echo "  Codespaces → Open in Codespace from GitHub"
echo
echo "If this script fails, the devcontainer is your fallback."
echo

section "Tool Verification"

require_tools az terraform kubectl helm jq
info "All required tools found"

section "Python Environment Setup"

PYTHON_VERSION="$(cat "${SCRIPT_DIR}/.python-version")"
info "Target Python version: ${PYTHON_VERSION}"

if command -v pyenv &>/dev/null; then
  info "Installing Python ${PYTHON_VERSION} via pyenv..."
  pyenv install -s "${PYTHON_VERSION}"
  PYTHON_CMD="python"
elif command -v python3 &>/dev/null; then
  warn "pyenv not found, using system python3"
  PYTHON_CMD="python3"
else
  fatal "Neither pyenv nor python3 found. Please install Python 3.11+"
fi

info "Using Python: $($PYTHON_CMD --version)"

# Detect package manager - prefer uv for performance (10-100x faster)
if command -v uv &>/dev/null; then
  USE_UV=true
  info "Using uv package manager (10-100x faster than pip)"
else
  USE_UV=false
  info "Using pip (install uv for faster package management)"
fi

if [[ "${DISABLE_VENV}" == "true" ]]; then
  info "Virtual environment disabled, installing packages directly..."
else
  if [[ ! -d "${VENV_DIR}" ]]; then
    info "Creating virtual environment at ${VENV_DIR}..."
    if [[ "${USE_UV}" == "true" ]]; then
      uv venv "${VENV_DIR}"
    else
      $PYTHON_CMD -m venv "${VENV_DIR}"
    fi
  else
    info "Virtual environment already exists at ${VENV_DIR}"
  fi
  info "Activating virtual environment..."
  source "${VENV_DIR}/bin/activate"
fi

info "Upgrading pip..."
if [[ "${USE_UV}" == "true" ]]; then
  uv pip install --upgrade pip --quiet
else
  pip install --upgrade pip --quiet
fi

info "Installing root dependencies..."
if [[ "${USE_UV}" == "true" ]]; then
  if ! uv pip install -r "${SCRIPT_DIR}/requirements.txt" --quiet 2>/dev/null; then
    warn "Some packages failed to install (expected on macOS for Linux-only packages)"
  fi
else
  if ! pip install -r "${SCRIPT_DIR}/requirements.txt" --quiet 2>/dev/null; then
    warn "Some packages failed to install (expected on macOS for Linux-only packages)"
  fi
fi

info "Installing training dependencies..."
if [[ "${USE_UV}" == "true" ]]; then
  if ! uv pip install -r "${SCRIPT_DIR}/src/training/requirements.txt" --quiet 2>/dev/null; then
    warn "Some training packages failed to install"
  fi
else
  if ! pip install -r "${SCRIPT_DIR}/src/training/requirements.txt" --quiet 2>/dev/null; then
    warn "Some training packages failed to install"
  fi
fi

section "IsaacLab Setup"

ISAACLAB_DIR="${SCRIPT_DIR}/external/IsaacLab"

if [[ -d "${ISAACLAB_DIR}" ]]; then
  info "IsaacLab already cloned at ${ISAACLAB_DIR}"
  info "To update, run: cd ${ISAACLAB_DIR} && git pull"
else
  info "Cloning IsaacLab for intellisense/Pylance support..."
  mkdir -p "${SCRIPT_DIR}/external"
  git clone https://github.com/isaac-sim/IsaacLab.git "${ISAACLAB_DIR}"
  info "IsaacLab cloned successfully"
fi

section "Setup Complete"

echo
echo "✅ Development environment setup complete!"
echo
if [[ "${DISABLE_VENV}" == "false" ]]; then
  warn "Run this command to activate the virtual environment:"
  echo
  echo "  source .venv/bin/activate"
  echo
fi
echo "Next steps:"
echo "  1. Run: source deploy/000-prerequisites/az-sub-init.sh"
echo "  2. Configure: deploy/001-iac/terraform.tfvars"
echo "  3. Deploy: cd deploy/001-iac && terraform init && terraform apply"
echo
echo "Documentation:"
echo "  - README.md           - Quick start guide"
echo "  - deploy/README.md    - Deployment overview"
echo
