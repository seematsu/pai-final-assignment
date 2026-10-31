#!/usr/bin/env bash
# Run LabUtopia main.py headless with a config from ../configs, saving outputs under out/.
# Usage: bash scripts/run_main.sh <config-name> [extra main.py args...]
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
if ! .venv/bin/python -c 'import json; from pathlib import Path; p=Path("environment/eula-consent.json"); raise SystemExit(0 if p.is_file() and json.loads(p.read_text()).get("accepted") is True else 1)'; then
  echo 'NVIDIA Omniverse license consent is required before launching Isaac Sim.' >&2
  exit 2
fi
CONFIG_NAME="$1"; shift
RUN_DIR="$TASK_ROOT/out/$(TZ=Asia/Tokyo date +%Y%m%d-%H%M%S)_$CONFIG_NAME${LABUTOPIA_RUN_TAG:+_$LABUTOPIA_RUN_TAG}"
mkdir -p "$RUN_DIR"
export UV_PROJECT="$TASK_ROOT"
export UV_PROJECT_ENVIRONMENT="$TASK_ROOT/.venv"
export VIRTUAL_ENV="$TASK_ROOT/.venv"
export UV_CACHE_DIR="$TASK_ROOT/.cache/uv"
export UV_PYTHON_INSTALL_DIR="$TASK_ROOT/.python"
export XDG_CACHE_HOME="$TASK_ROOT/.cache"
export XDG_CONFIG_HOME="$TASK_ROOT/.config"
export XDG_DATA_HOME="$TASK_ROOT/.local/share"
export CUDA_CACHE_PATH="$TASK_ROOT/.cache/cuda"
export MPLCONFIGDIR="$TASK_ROOT/.cache/matplotlib"
export WANDB_MODE="${WANDB_MODE:-disabled}"
export OMNI_KIT_ACCEPT_EULA=YES
export LD_PRELOAD=/lib/aarch64-linux-gnu/libgomp.so.1
# Isaac Sim extensions load torch after Kit; enlarge static TLS so libc10.so fits (aarch64).
export GLIBC_TUNABLES="${GLIBC_TUNABLES:-glibc.rtld.optional_static_tls=16384}"
export PYTHONUNBUFFERED=1
export LABUTOPIA_RUN_DIR="$RUN_DIR"
export LABUTOPIA_ROOT="$TASK_ROOT"
printf '%s\n' "$RUN_DIR" > "$TASK_ROOT/environment/latest-run.txt"
printf 'Artifacts: %s\n' "$RUN_DIR"
cd "$TASK_ROOT/repo"
set +e
timeout --signal=TERM --kill-after=30s "${LABUTOPIA_TIMEOUT:-1800}s" \
  uv run --frozen python -u main.py --headless --config-dir ../configs --config-name "$CONFIG_NAME" "$@" \
  2>&1 | tee "$RUN_DIR/run.log"
EXIT=${PIPESTATUS[0]}
set -e
printf '%s\n' "$EXIT" > "$RUN_DIR/exit-code.txt"
exit "$EXIT"
