#!/usr/bin/env bash
# Train a LabUtopia policy with a config from ../configs/train, saving outputs under out/train/.
# Usage: bash scripts/train.sh <config-name> <dataset-dir> <run-name> [extra hydra overrides...]
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_NAME="$1"; DATASET_DIR="$(cd -- "$2" && pwd)"; RUN_NAME="$3"; shift 3
RUN_DIR="$TASK_ROOT/out/train/$(TZ=Asia/Tokyo date +%Y%m%d-%H%M%S)_$RUN_NAME"
mkdir -p "$RUN_DIR"
export XDG_CACHE_HOME="$TASK_ROOT/.cache"
export MPLCONFIGDIR="$TASK_ROOT/.cache/matplotlib"
export TORCH_HOME="$TASK_ROOT/.cache/torch"
export HF_HOME="$TASK_ROOT/.cache/huggingface"
export WANDB_MODE="${WANDB_MODE:-disabled}"
export PYTHONUNBUFFERED=1
printf 'Artifacts: %s\n' "$RUN_DIR"
cd "$TASK_ROOT/repo"
set +e
"$TASK_ROOT/.venv/bin/python" train.py --config-dir ../configs/train --config-name "$CONFIG_NAME" \
  task.dataset_path="$DATASET_DIR" hydra.run.dir="$RUN_DIR" multi_run.run_dir="$RUN_DIR" "$@" \
  > "$RUN_DIR/stdout.log" 2>&1
EXIT=$?
set -e
printf '%s\n' "$EXIT" > "$RUN_DIR/exit-code.txt"
exit "$EXIT"
