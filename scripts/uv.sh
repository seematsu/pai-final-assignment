#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
export UV_PROJECT="$TASK_ROOT"
export UV_PROJECT_ENVIRONMENT="$TASK_ROOT/.venv"
export VIRTUAL_ENV="$TASK_ROOT/.venv"
export UV_CACHE_DIR="$TASK_ROOT/.cache/uv"
export UV_PYTHON_INSTALL_DIR="$TASK_ROOT/.python"
exec uv "$@"
