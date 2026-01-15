#!/usr/bin/env bash
# Package installer detection utility - prefers uv when available, falls back to pip
set -o errexit -o nounset

# Isaac Sim bundled packages - DO NOT override these via uv/pip
# These versions are validated by NVIDIA for Isaac Sim 5.0 compatibility
# Format: "package:fallback_constraint" - fallback used when detection fails
readonly ISAAC_SIM_PROTECTED_PACKAGES=(
    "numpy:<2.0.0"
    "scipy:<1.16.0"
)

# Cached resolved Python executable path
_RESOLVED_PYTHON=""

# Resolve Python executable from wrapper command (e.g., isaaclab.sh -p)
# Args: python_cmd - Python command or wrapper script
# Returns: Resolved Python executable path via stdout
resolve_python_executable() {
    local python_cmd="${1:-python3}"

    # Return cached value if available
    if [[ -n "${_RESOLVED_PYTHON}" ]]; then
        echo "${_RESOLVED_PYTHON}"
        return 0
    fi

    # Use UV_PYTHON if set
    if [[ -n "${UV_PYTHON:-}" ]]; then
        _RESOLVED_PYTHON="${UV_PYTHON}"
        echo "${_RESOLVED_PYTHON}"
        return 0
    fi

    # Resolve via Python sys.executable, extract last line to skip wrapper INFO messages
    local resolved
    resolved="$(eval "${python_cmd}" -c "'import sys; print(sys.executable)'" 2>&1 | tail -n1 || true)"

    # Validate it's a real path
    if [[ -n "${resolved}" && "${resolved}" == /* && -x "${resolved}" ]]; then
        _RESOLVED_PYTHON="${resolved}"
        echo "${_RESOLVED_PYTHON}"
        return 0
    fi

    # Fallback to python_cmd as-is
    echo "${python_cmd}"
}

# Detect and return the best package install command
# Args: python_cmd - The python command/path to use for pip fallback
# Returns: Package install command string via stdout
# Exit: 1 if no package installer available
get_pip_install_cmd() {
    local python_cmd="${1:-python3}"
    local resolved_python

    # Use centralized Python resolution
    resolved_python="$(resolve_python_executable "${python_cmd}")"
    echo "Debug: python_cmd='${python_cmd}' resolved_python='${resolved_python}'" >&2

    # Check for uv first (much faster)
    if command -v uv &>/dev/null; then
        echo "Using uv package installer (fast mode)" >&2
        if [[ -n "${resolved_python}" && -x "${resolved_python}" ]]; then
            echo "uv pip install --python ${resolved_python}"
        else
            echo "uv pip install --system"
        fi
        return 0
    fi

    # Check for uv in VIRTUAL_ENV (IsaacLab pattern)
    if [[ -n "${VIRTUAL_ENV:-}" ]] && \
       [[ -f "${VIRTUAL_ENV}/pyvenv.cfg" ]] && \
       grep -q "uv" "${VIRTUAL_ENV}/pyvenv.cfg"; then
        echo "Using uv package installer via VIRTUAL_ENV (fast mode)" >&2
        echo "uv pip install --system"
        return 0
    fi

    # Fallback to python -m pip
    if ${python_cmd} -m pip --version >/dev/null 2>&1; then
        echo "Using pip package installer (fallback)" >&2
        echo "${python_cmd} -m pip install"
        return 0
    fi

    # Try ensurepip bootstrap
    if ${python_cmd} -m ensurepip --version >/dev/null 2>&1; then
        echo "Bootstrapping pip via ensurepip..." >&2
        ${python_cmd} -m ensurepip --upgrade >/dev/null 2>&1
        echo "Using pip package installer (bootstrapped)" >&2
        echo "${python_cmd} -m pip install"
        return 0
    fi

    echo "Error: neither uv nor pip available" >&2
    return 1
}

# Generate constraints file to protect Isaac Sim bundled packages from upgrade
# Args: python_cmd - Python command to query installed versions
# Returns: Path to generated constraints file via stdout
generate_isaac_constraints() {
    local python_cmd="${1:-python3}"
    local constraints_file
    constraints_file="$(mktemp --suffix=.txt)"

    # Use resolved Python directly to avoid wrapper script output pollution
    local resolved_python
    resolved_python="$(resolve_python_executable "${python_cmd}")"

    echo "Generating Isaac Sim package constraints..." >&2
    echo "  Using Python: ${resolved_python}" >&2

    # Query actual installed versions to create precise constraints
    for pkg_entry in "${ISAAC_SIM_PROTECTED_PACKAGES[@]}"; do
        local pkg="${pkg_entry%%:*}"
        local fallback_constraint="${pkg_entry#*:}"

        local version
        # Use resolved Python directly, capture only stdout
        version="$("${resolved_python}" -c "
try:
    import ${pkg}
    print(getattr(${pkg}, '__version__', ''))
except Exception:
    pass
" 2>/dev/null || true)"

        # Validate version format
        if [[ -n "${version}" && "${version}" =~ ^[0-9]+\.[0-9]+ ]]; then
            echo "${pkg}==${version}" >> "${constraints_file}"
            echo "  Constraint: ${pkg}==${version}" >&2
        elif [[ -n "${fallback_constraint}" ]]; then
            echo "${pkg}${fallback_constraint}" >> "${constraints_file}"
            echo "  Fallback constraint: ${pkg}${fallback_constraint} (version detection failed)" >&2
        else
            echo "  Warning: Could not detect ${pkg} version, skipping constraint" >&2
        fi
    done

    # Only output file path if we have valid constraints
    if [[ -s "${constraints_file}" ]]; then
        echo "${constraints_file}"
    else
        echo "  No constraints generated, proceeding without protection" >&2
        rm -f "${constraints_file}"
        echo ""
    fi
}

# Install packages from requirements file, protecting Isaac Sim bundled packages
# Args: requirements_file - Path to requirements.txt
#       python_cmd - Python command/path (optional, defaults to python3)
# Returns: 0 on success, 1 on failure
install_requirements_safe() {
    local requirements_file="$1"
    local python_cmd="${2:-python3}"
    local install_cmd
    local constraints_file

    install_cmd="$(get_pip_install_cmd "${python_cmd}")"
    constraints_file="$(generate_isaac_constraints "${python_cmd}")"

    # Cleanup trap only if constraints file exists
    if [[ -n "${constraints_file}" && -f "${constraints_file}" ]]; then
        # shellcheck disable=SC2064
        trap "rm -f ${constraints_file}" EXIT
    fi

    echo "Installing requirements with Isaac Sim package protection..." >&2

    # Use constraints to prevent transitive dependency upgrades
    # shellcheck disable=SC2086
    if [[ -n "${constraints_file}" && -f "${constraints_file}" ]]; then
        if [[ "${install_cmd}" == uv* ]]; then
            ${install_cmd} --constraint "${constraints_file}" -r "${requirements_file}" 2>&1
        else
            ${install_cmd} -c "${constraints_file}" -r "${requirements_file}" 2>&1
        fi
    else
        echo "Warning: No constraints available, installing without protection" >&2
        ${install_cmd} -r "${requirements_file}" 2>&1
    fi
}
