#!/usr/bin/env bash
# Collect demos for one config with several Isaac Sim processes in parallel.
# Each process writes its own out/<timestamp>_<config>_p<i>/ directory.
# Usage: bash scripts/collect_parallel.sh <config-name> <episodes-per-process> [<episodes-per-process> ...] [-- extra main.py args...]
set -uo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_NAME="$1"; shift
COUNTS=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do COUNTS+=("$1"); shift; done
[ "${1:-}" = "--" ] && shift
pids=()
for i in "${!COUNTS[@]}"; do
  LABUTOPIA_RUN_TAG="p$i" LABUTOPIA_MAX_EPISODES="${COUNTS[$i]}" LABUTOPIA_TIMEOUT="${LABUTOPIA_TIMEOUT:-36000}" \
    bash "$TASK_ROOT/scripts/run_main.sh" "$CONFIG_NAME" "$@" > /dev/null 2>&1 &
  pids+=($!)
  sleep 5
done
status=0
for i in "${!pids[@]}"; do
  wait "${pids[$i]}"; ec=$?
  printf '%s p%s exit=%s\n' "$CONFIG_NAME" "$i" "$ec"
  [ "$ec" -eq 0 ] || status=1
done
exit "$status"
