#!/usr/bin/env bash
# Package installer detection utility - prefers uv when available, falls back to pip
set -o errexit -o nounset

# Detect and return the best package install command
# Args: python_cmd - The python command/path to use for pip fallback
# Returns: Package install command string via stdout
# Exit: 1 if no package installer available
get_pip_install_cmd() {
    local python_cmd="${1:-python3}"

    # Check for uv first (much faster)
    if command -v uv &>/dev/null; then
        echo "uv pip install"
        return 0
    fi

    # Check for uv in VIRTUAL_ENV (IsaacLab pattern)
    if [[ -n "${VIRTUAL_ENV:-}" ]] && \
       [[ -f "${VIRTUAL_ENV}/pyvenv.cfg" ]] && \
       grep -q "uv" "${VIRTUAL_ENV}/pyvenv.cfg"; then
        echo "uv pip install"
        return 0
    fi

    # Fallback to python -m pip
    if ${python_cmd} -m pip --version >/dev/null 2>&1; then
        echo "${python_cmd} -m pip install"
        return 0
    fi

    # Try ensurepip bootstrap
    if ${python_cmd} -m ensurepip --version >/dev/null 2>&1; then
        ${python_cmd} -m ensurepip --upgrade >/dev/null 2>&1
        echo "${python_cmd} -m pip install"
        return 0
    fi

    echo "Error: neither uv nor pip available" >&2
    return 1
}
