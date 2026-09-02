#!/usr/bin/env bash
# tests/test_plugin_registry_drift.sh
# `aphotic plugin list` flags an installed plugin whose files no longer
# match the registry entry the shell actually reads
# (~/.local/state/aphotic/plugins.json). Nothing reported that before, so
# a plugin edited in place -- a manual change, a `git pull` under a
# --link install, a half-finished install -- left the shell reading stale
# capabilities/ui indefinitely. Found three real cases on a live machine
# the first time it ran, one of them an enabled plugin with no registry
# entry at all.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export XDG_DATA_HOME="$TESTHOME/.local/share"
export APHOTIC_DOTS_DIR="$ROOT"

COMMANDS_DIR="$ROOT/Configs/.local/lib/aphotic/commands"
source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_plugin.sh"

export APHOTIC_PLUGINS_REPO="$TESTHOME/fake-repo"
SRC="$APHOTIC_PLUGINS_REPO/scratch-drift"
mkdir -p "$SRC/qml"
cat > "$SRC/plugin.toml" <<'EOF'
[plugin]
name = "scratch-drift"
display_name = "Scratch Drift"
description = "test plugin"
version = "1.0.0"
category = "ai"
capabilities = ["ui-surface"]

[owns]
config_keys = ["keyOne"]

[ui.dashboard_tab]
id = "scratchTab"
icon = "extension"
label = "Scratch Tab"
component = "qml/ScratchTab.qml"
EOF
echo "// v1" > "$SRC/qml/ScratchTab.qml"
echo "ScratchTab 1.0 ScratchTab.qml" > "$SRC/qml/qmldir"
git -C "$APHOTIC_PLUGINS_REPO" init -q 2>/dev/null || true

_aphotic_plugin_install scratch-drift false >/dev/null 2>&1
DEST="$(_aphotic_plugin_dir scratch-drift)"
[[ -d "$DEST" ]] || fail "expected scratch-drift installed"

drifted_of() { _aphotic_plugin_describe scratch-drift | jq -r '.drifted'; }

# --- a freshly installed plugin is in step ---

[[ "$(drifted_of)" == "false" ]] || fail "expected a freshly installed plugin not to be flagged as drifted"

# --- files edited in place, registry untouched -> drifted ---

sed -i 's/version = "1.0.0"/version = "1.2.0"/' "$DEST/plugin.toml"
[[ "$(drifted_of)" == "true" ]] || fail "expected an in-place version change to be reported as drift"

_aphotic_plugin_registry_sync scratch-drift
[[ "$(drifted_of)" == "false" ]] || fail "expected a registry sync to clear the drift flag"

# --- a capability/ui change drifts too, not just the version ---

sed -i 's/label = "Scratch Tab"/label = "Renamed Tab"/' "$DEST/plugin.toml"
[[ "$(drifted_of)" == "true" ]] || fail "expected a changed ui block to be reported as drift"
_aphotic_plugin_registry_sync scratch-drift

sed -i 's/capabilities = \["ui-surface"\]/capabilities = ["ui-surface", "theme-hook"]/' "$DEST/plugin.toml"
[[ "$(drifted_of)" == "true" ]] || fail "expected a changed capabilities list to be reported as drift"
_aphotic_plugin_registry_sync scratch-drift
[[ "$(drifted_of)" == "false" ]] || fail "expected the sync to clear it again"

# --- installed but absent from the registry entirely -> drifted ---
# The real case this caught live: an enabled plugin the shell had no
# entry for at all.

tmp="$(mktemp)"
jq 'del(.installed["scratch-drift"])' "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp" && mv "$tmp" "$APHOTIC_PLUGINS_STATE_FILE"
[[ "$(drifted_of)" == "true" ]] || fail "expected a plugin missing from the registry to be reported as drift"

# --- `update` is the documented fix, and it clears the flag ---

_aphotic_plugin_update scratch-drift >/dev/null 2>&1
[[ "$(drifted_of)" == "false" ]] || fail "expected 'aphotic plugin update' to clear the drift flag"

# --- the flag reaches both list outputs ---

_aphotic_plugin_registry_sync scratch-drift
sed -i 's/^version = .*/version = "9.9.9"/' "$DEST/plugin.toml"
[[ "$(drifted_of)" == "true" ]] || fail "expected the version bump to register as drift before checking the listings"
_aphotic_plugin_list_installed_json | jq -e '.[] | select(.name=="scratch-drift") | .drifted' >/dev/null \
    || fail "expected --json output to carry the drifted flag"
out="$(aphotic_cmd_plugin list 2>&1)"
grep -q "stale registry entry" <<<"$out" || fail "expected the text listing to mark the stale entry, got: $out"
grep -q "aphotic plugin update" <<<"$out" || fail "expected the warning to name the fix, got: $out"

echo "PASS: plugin list flags installed files that have drifted from the registry entry"
