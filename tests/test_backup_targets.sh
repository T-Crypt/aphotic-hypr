#!/usr/bin/env bash
# tests/test_backup_targets.sh
# aphotic backup create/revert used $(basename "$target") as each
# snapshot's slot name. QUICKSHELL_CONFIG_DIR (~/.config/quickshell/
# aphotic) and APHOTIC_CONFIG_HOME (~/.config/aphotic) both basename to
# "aphotic", so every real backup silently overwrote one with the other
# in the same slot -- found while wiring aphotic reconcile's rollback
# through this. Targets are now "name|path" pairs. Also covers revert
# creating a target's parent directory, which plain cp -a does not do.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$ROOT/Configs/.local/lib/aphotic"
COMMANDS_DIR="$LIB_DIR/commands"
TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export XDG_DATA_HOME="$TESTHOME/.local/share"
export APHOTIC_DOTS_DIR="$ROOT"

source "$LIB_DIR/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_backup.sh"

# Two distinct, real targets that collide on basename ("aphotic"), each
# with content that would prove which one survived.
mkdir -p "$QUICKSHELL_CONFIG_DIR"
echo "quickshell-content" > "$QUICKSHELL_CONFIG_DIR/shell.qml"
mkdir -p "$APHOTIC_CONFIG_HOME"
echo '{"marker": "shell.json-content"}' > "$APHOTIC_CONFIG_FILE"

id="$(_aphotic_backup_create --label test 2>/dev/null | tail -1)"
[[ -n "$id" ]] || fail "expected _aphotic_backup_create to print a snapshot id"

snapshot="${APHOTIC_BACKUP_DIR}/${id}"
[[ -f "${snapshot}/quickshell/shell.qml" ]] || fail "expected the quickshell target captured under its own name"
[[ -f "${snapshot}/aphotic/shell.json" ]] || fail "expected the aphotic-config target captured under its own name, not overwritten by quickshell"
[[ "$(<"${snapshot}/quickshell/shell.qml")" == "quickshell-content" ]] || fail "expected quickshell's own content, not clobbered"

# --- mutate both, then revert: both must come back independently ---

echo "mutated" > "$QUICKSHELL_CONFIG_DIR/shell.qml"
echo '{"marker": "mutated"}' > "$APHOTIC_CONFIG_FILE"

_aphotic_backup_revert --yes "$id" >/dev/null 2>&1

[[ "$(<"$QUICKSHELL_CONFIG_DIR/shell.qml")" == "quickshell-content" ]] || fail "expected quickshell restored to its pre-mutation content"
grep -q "shell.json-content" "$APHOTIC_CONFIG_FILE" || fail "expected aphotic config restored to its pre-mutation content"

# --- revert into a target whose parent directory doesn't exist yet ---

rm -rf "$QUICKSHELL_CONFIG_DIR" "$(dirname "$QUICKSHELL_CONFIG_DIR")"
[[ -d "$(dirname "$QUICKSHELL_CONFIG_DIR")" ]] && fail "test setup: expected quickshell's parent dir gone"

_aphotic_backup_revert --yes "$id" >/dev/null 2>&1

[[ -f "$QUICKSHELL_CONFIG_DIR/shell.qml" ]] || fail "expected revert to create the missing parent directory and restore the file"

echo "ok: test_backup_targets"
