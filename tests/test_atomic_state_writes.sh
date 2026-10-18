#!/usr/bin/env bash
# tests/test_atomic_state_writes.sh
# Every state file the CLI owns is rewritten from a temp file, and mktemp's
# default $TMPDIR (/tmp, a tmpfs here) is a different filesystem from
# ~/.local/state, so `mv` from there is a copy followed by an unlink: a
# reader in another process can see the file half-written. The shell watches
# plugins.json, theme.json and safe-mode.json through a FileView, and on
# 2026-10-13 a read that landed mid-write made every installed plugin drop
# out of the UI. CI has one filesystem, so a race would never reproduce
# there; this pins the staged path instead, which is the part that decides
# whether the move is a rename: the temp file has to be a sibling of the
# target.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export XDG_DATA_HOME="$TESTHOME/.local/share"
export APHOTIC_DOTS_DIR="$ROOT"

COMMANDS_DIR="$ROOT/Configs/.local/lib/aphotic/commands"
# shellcheck source=/dev/null
source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"
# shellcheck source=/dev/null
source "$COMMANDS_DIR/cmd_plugin.sh"
# shellcheck source=/dev/null
source "$COMMANDS_DIR/cmd_theme.sh"
# shellcheck source=/dev/null
source "$COMMANDS_DIR/cmd_recovery.sh"
# shellcheck source=/dev/null
source "$COMMANDS_DIR/cmd_ai.sh"
# shellcheck source=/dev/null
source "$COMMANDS_DIR/play/scores.sh"

mkdir -p "$APHOTIC_STATE_HOME" "$APHOTIC_CONFIG_HOME"

# Record every mv a writer makes. Nothing but the one helper moves a temp
# file onto a target, so any source outside the target's own directory is
# the copy-across-filesystems case this test exists to catch.
MV_LOG=""
mv() { MV_LOG="${MV_LOG}${1}"$'\n'; command mv "$@"; }

assert_sibling() {  # label target
    local label="$1" target="$2" dir line
    dir="$(dirname "$target")"
    [[ -n "$MV_LOG" ]] || fail "$label: nothing was moved onto $target"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$(dirname "$line")" == "$dir" ]] \
            || fail "$label: staged $line, not beside $target -- mv copies across filesystems, so a reader can see it half-written"
    done <<<"$MV_LOG"
    MV_LOG=""
}

make_plugin() {
    local dir="$APHOTIC_PLUGINS_DIR/$1"
    mkdir -p "$dir/qml"
    cat > "$dir/plugin.toml" <<EOF
[plugin]
name = "$1"
display_name = "$1"
description = "atomic write test"
version = "1.0.0"
category = "ai"
capabilities = ["ui-surface"]

[ui.workspace]
id = "${1}Plane"
icon = "extension"
label = "$1"
component = "qml/Plane.qml"
EOF
    echo 'import QtQuick; Item {}' > "$dir/qml/Plane.qml"
}

# --- plugins.json, the write the maintainer hit --------------------------

echo '{"disabled": []}' > "$APHOTIC_PLUGINS_STATE_FILE"

aphotic_plugin_set_enabled alpha false
assert_sibling "aphotic_plugin_set_enabled (disable)" "$APHOTIC_PLUGINS_STATE_FILE"
aphotic_plugin_set_enabled alpha true
assert_sibling "aphotic_plugin_set_enabled (enable)" "$APHOTIC_PLUGINS_STATE_FILE"
jq -e '.disabled == []' "$APHOTIC_PLUGINS_STATE_FILE" >/dev/null \
    || fail "enable/disable wrote the wrong content: $(cat "$APHOTIC_PLUGINS_STATE_FILE")"

make_plugin alpha
_aphotic_plugin_registry_sync alpha
assert_sibling "_aphotic_plugin_registry_sync" "$APHOTIC_PLUGINS_STATE_FILE"
jq -e '.installed.alpha.version == "1.0.0"' "$APHOTIC_PLUGINS_STATE_FILE" >/dev/null \
    || fail "registry sync wrote the wrong content: $(cat "$APHOTIC_PLUGINS_STATE_FILE")"

_aphotic_plugin_registry_remove alpha
assert_sibling "_aphotic_plugin_registry_remove" "$APHOTIC_PLUGINS_STATE_FILE"
jq -e '.installed.alpha == null' "$APHOTIC_PLUGINS_STATE_FILE" >/dev/null \
    || fail "registry remove wrote the wrong content: $(cat "$APHOTIC_PLUGINS_STATE_FILE")"

aphotic_plugins_set_security_index_trusted true
assert_sibling "aphotic_plugins_set_security_index_trusted" "$APHOTIC_PLUGINS_STATE_FILE"

# --- the rest of the state files -----------------------------------------

aphotic_json_set theme.active dark
assert_sibling "aphotic_json_set" "$APHOTIC_CONFIG_FILE"
jq -e '.theme.active == "dark"' "$APHOTIC_CONFIG_FILE" >/dev/null \
    || fail "aphotic_json_set wrote the wrong content: $(cat "$APHOTIC_CONFIG_FILE")"

aphotic_safe_mode_set true "atomic write test"
assert_sibling "aphotic_safe_mode_set" "$APHOTIC_SAFE_MODE_FILE"
jq -e '.active == true' "$APHOTIC_SAFE_MODE_FILE" >/dev/null \
    || fail "aphotic_safe_mode_set wrote the wrong content: $(cat "$APHOTIC_SAFE_MODE_FILE")"

# Bounded trail: only past 400 lines does it rewrite the file instead of
# appending to it.
for i in $(seq 401); do printf 'x\tchange\t%s\n' "$i"; done > "$APHOTIC_CHANGE_LOG"
aphotic_record_change test "atomic write test"
assert_sibling "aphotic_record_change" "$APHOTIC_CHANGE_LOG"
[[ "$(wc -l < "$APHOTIC_CHANGE_LOG")" -le 201 ]] \
    || fail "aphotic_record_change kept $(wc -l < "$APHOTIC_CHANGE_LOG") lines"

_aphotic_theme_write_state dark "$TESTHOME/wall.png"
assert_sibling "_aphotic_theme_write_state" "$APHOTIC_THEME_STATE_FILE"
jq -e '.theme == "dark"' "$APHOTIC_THEME_STATE_FILE" >/dev/null \
    || fail "_aphotic_theme_write_state wrote the wrong content: $(cat "$APHOTIC_THEME_STATE_FILE")"

_aphotic_recovery_record crash "exit 1"
assert_sibling "_aphotic_recovery_record" "$APHOTIC_RECOVERY_STATE_FILE"
jq -e '.failures | length == 1' "$APHOTIC_RECOVERY_STATE_FILE" >/dev/null \
    || fail "_aphotic_recovery_record wrote the wrong content: $(cat "$APHOTIC_RECOVERY_STATE_FILE")"

aphotic_cmd_ai profile claude >/dev/null
assert_sibling "aphotic_cmd_ai profile" "$APHOTIC_CONFIG_HOME/ai-config.json"
jq -e '.activeProvider == "claude"' "$APHOTIC_CONFIG_HOME/ai-config.json" >/dev/null \
    || fail "aphotic_cmd_ai profile wrote the wrong content: $(cat "$APHOTIC_CONFIG_HOME/ai-config.json")"

rm -f "$APHOTIC_PLAY_SCORES_FILE"
_aphotic_play_stat_set snake bestScore 3
assert_sibling "_aphotic_play_stat_set (new file)" "$APHOTIC_PLAY_SCORES_FILE"
_aphotic_play_stat_set snake attempts 1
assert_sibling "_aphotic_play_stat_set (existing file)" "$APHOTIC_PLAY_SCORES_FILE"
jq -e '.snake.bestScore == 3 and .snake.attempts == 1' "$APHOTIC_PLAY_SCORES_FILE" >/dev/null \
    || fail "_aphotic_play_stat_set wrote the wrong content: $(cat "$APHOTIC_PLAY_SCORES_FILE")"

# --- no second write path ------------------------------------------------
# Every writer in globalcontrol.sh is driven above; cmd_theme.sh's three
# settings.json pins sit behind wallust, gsettings and hyprctl, so the rest
# of the class is pinned by text instead: outside the one helper, nothing
# stages a temp file and moves it onto its target.

LIB="$ROOT/Configs/.local/lib/aphotic"
HELPER="$LIB/globalcontrol.sh"
movers="$(grep -rn 'mv[^|]*\$tmp' "$LIB" || true)"
strays="$(printf '%s\n' "$movers" | grep -v "^${HELPER}:" || true)"
[[ -z "$strays" ]] \
    || fail "a temp file is moved onto its target outside the helper: $(tr '\n' ' ' <<<"$strays")"
grep -q '^aphotic_write_atomic() {' "$HELPER" \
    || fail "the shared atomic write helper is gone from $(basename "$HELPER")"
grep -q 'mktemp "${dir}/' "$HELPER" \
    || fail "the helper no longer stages its temp file in the target's own directory"

echo "ok: test_atomic_state_writes"
