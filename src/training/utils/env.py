"""Environment variable helpers for training workflows."""

from __future__ import annotations

import os
from typing import Mapping


def require_env(name: str, *, error_type: type[Exception] = RuntimeError) -> str:
    """Return the value of *name* or raise when missing."""

    value = os.environ.get(name)
    if not value:
        raise error_type(f"Environment variable {name} is required for Azure ML bootstrap")
    return value


def set_env_defaults(defaults: Mapping[str, str]) -> None:
    """Set default values for environment variables that may be unset."""

    for key, default_value in defaults.items():
        os.environ.setdefault(key, default_value)
