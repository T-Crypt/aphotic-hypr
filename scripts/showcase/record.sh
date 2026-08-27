#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO_ROOT/recordings"
OUT_FILE="$OUT_DIR/aphotic-showcase-raw.mp4"

FRAMERATE="${FRAMERATE:-30}"
OUTPUT_NAME="${OUTPUT_NAME:-}"
PREROLL="${PREROLL:-1}"

if ! command -v wf-recorder >/dev/null 2>&1; then
    printf 'wf-recorder not found on PATH.\n' >&2
    printf 'Install it first: pacman -S wf-recorder\n' >&2
    exit 1
fi

if ! command -v hyprctl >/dev/null 2>&1; then
    printf 'hyprctl not found on PATH -- this needs to run inside a live Hyprland session.\n' >&2
    exit 1
fi

if [[ -z "$OUTPUT_NAME" ]]; then
    OUTPUT_NAME="$(hyprctl monitors -j | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["name"])' 2>/dev/null)"
fi

if [[ -z "$OUTPUT_NAME" ]]; then
    printf 'Could not resolve an output name from hyprctl -- set OUTPUT_NAME explicitly.\n' >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

printf 'Recording output "%s" at %sfps -> %s\n' "$OUTPUT_NAME" "$FRAMERATE" "$OUT_FILE" >&2

wf-recorder -o "$OUTPUT_NAME" -f "$OUT_FILE" -r "$FRAMERATE" -y &
RECORDER_PID=$!

sleep "$PREROLL"

if ! kill -0 "$RECORDER_PID" 2>/dev/null; then
    printf 'wf-recorder exited immediately -- check its output above.\n' >&2
    exit 1
fi

"$SCRIPT_DIR/run_demo.sh"
DEMO_STATUS=$?

kill -INT "$RECORDER_PID" 2>/dev/null
wait "$RECORDER_PID" 2>/dev/null

if [[ -f "$OUT_FILE" ]]; then
    printf 'Raw recording saved: %s\n' "$OUT_FILE" >&2
else
    printf 'Recording did not produce an output file.\n' >&2
    exit 1
fi

exit "$DEMO_STATUS"
