#!/usr/bin/env bash
# Apply patches/*.patch to the upstream LabUtopia checkout in repo/ (skips patches that are already applied).
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for patch in "$TASK_ROOT"/patches/*.patch; do
  name="$(basename "$patch")"
  if git -C "$TASK_ROOT/repo" apply --check --reverse "$patch" 2>/dev/null; then
    echo "already applied: $name"
  else
    git -C "$TASK_ROOT/repo" apply "$patch"
    echo "applied: $name"
  fi
done
