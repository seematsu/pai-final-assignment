#!/usr/bin/env bash
# Re-encode videos written by LabUtopia (OpenCV mp4v, which browsers and phones often cannot play) to H.264.
# Uses the ffmpeg bundled with imageio-ffmpeg in this project's uv environment.
# Usage: bash scripts/to_h264.sh <input.mp4> <output.mp4> [extra ffmpeg output options...]
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG="$("$TASK_ROOT/.venv/bin/python" -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')"
IN="$1"; OUT="$2"; shift 2
mkdir -p "$(dirname -- "$OUT")"
"$FFMPEG" -hide_banner -loglevel error -y -i "$IN" "$@" \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -movflags +faststart -an "$OUT"
