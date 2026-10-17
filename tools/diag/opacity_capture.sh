#!/usr/bin/env bash
# Read-only capture for diagnosing opacity flashes during GPU work.
# Samples compositor decoration, the focused window, inference mode and GPU
# memory every 250 ms and appends one TSV row per sample. It writes only the
# output file: hyprctl getoption/activewindow/clients, the read-only
# `inference status` IPC and nvidia-smi are the only things it runs, so it
# never changes a setting.
set -uo pipefail

usage() {
    printf 'usage: %s [seconds]  (default 60, one sample every 250 ms)\n' "${0##*/}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

duration="${1:-60}"
if ! [[ "$duration" =~ ^[0-9]+$ ]] || (( duration == 0 )); then
    printf 'error: seconds must be a positive integer\n' >&2
    usage >&2
    exit 2
fi

need() { command -v "$1" >/dev/null 2>&1; }
need jq || { printf 'error: jq is required\n' >&2; exit 2; }
need hyprctl || { printf 'error: hyprctl is required (run inside a Hyprland session)\n' >&2; exit 2; }

stamp="$(date +%Y%m%d-%H%M%S)"
out="/tmp/opacity-capture-${stamp}.tsv"
: > "$out"

# getoption -j carries only the field for the option's own type (bool for a
# toggle, float for an opacity), so check which key is present rather than
# relying on `//`, which folds a legitimate false into the next key.
hypr_opt() {
    local json
    json="$(hyprctl getoption "$1" -j 2>/dev/null)" || return 0
    [[ -n "$json" ]] || return 0
    jq -r 'if has("bool") then .bool elif has("int") then .int elif has("float") then .float elif has("str") then .str else "" end | tostring' <<<"$json" 2>/dev/null
}

flat() { printf '%s' "${1:-}" | tr '\t\n\r' '   '; }

printf 'output: %s\n' "$out"
printf 'columns: ts_ms blur_enabled active_opacity inactive_opacity animations_enabled active_class active_tags active_window_opacity inference_status gpu_used_mib shadow_enabled opaque_tagged_windows\n'

# Sample on a fixed 250 ms grid: sleep only the remainder after the reads,
# so a slow socket round trip does not stretch the interval.
interval_ms=250
start_ms="$(date +%s%3N)"
end_ms=$(( start_ms + duration * 1000 ))
next_ms=$(( start_ms + interval_ms ))
samples=0

while :; do
    now_ms="$(date +%s%3N)"
    (( now_ms >= end_ms )) && break

    blur="$(hypr_opt decoration:blur:enabled)"
    active_op="$(hypr_opt decoration:active_opacity)"
    inactive_op="$(hypr_opt decoration:inactive_opacity)"
    anim="$(hypr_opt animations:enabled)"
    shadow="$(hypr_opt decoration:shadow:enabled)"

    active_json="$(hyprctl activewindow -j 2>/dev/null)"
    class="" tags="" win_op=""
    if [[ "$active_json" == "{"* ]]; then
        class="$(jq -r '.class // ""' <<<"$active_json" 2>/dev/null)"
        tags="$(jq -r '(.tags // []) | join(",")' <<<"$active_json" 2>/dev/null)"
        win_op="$(jq -r '.opacity // ""' <<<"$active_json" 2>/dev/null)"
    fi
    opaque_count="$(hyprctl clients -j 2>/dev/null | jq -r '[.[] | select((.tags // []) | index("opaque"))] | length' 2>/dev/null)"

    inference=""
    if need qs; then
        inference="$(qs -c aphotic ipc call inference status 2>/dev/null)"
    fi

    gpu=""
    if need nvidia-smi; then
        gpu="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -n1)"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$now_ms" "$(flat "$blur")" "$(flat "$active_op")" "$(flat "$inactive_op")" \
        "$(flat "$anim")" "$(flat "$class")" "$(flat "$tags")" "$(flat "$win_op")" \
        "$(flat "$inference")" "$(flat "$gpu")" "$(flat "$shadow")" "$(flat "$opaque_count")" \
        >>"$out"

    samples=$(( samples + 1 ))
    next_ms=$(( next_ms + interval_ms ))
    sleep_ms=$(( next_ms - $(date +%s%3N) ))
    if (( sleep_ms > 0 )); then
        sleep "$(printf '%d.%03d' $(( sleep_ms / 1000 )) $(( sleep_ms % 1000 )))"
    fi
done

printf 'captured %d samples\n' "$samples"
printf 'output: %s\n' "$out"
