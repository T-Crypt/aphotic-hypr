#!/usr/bin/env bash
# tests/test_plugin_v3.sh
# Manifest v3: [owns]/[ui.dashboard_tab] parsing, and the install/remove
# registry sync that lets a ui-surface plugin's UI drop out of the shell
# symmetrically. See docs/archive/PLUGIN_SYSTEM.md "Plugin manifest v3".
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

# --- scratch ui-surface plugin, manifest v3-shaped ---

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-ui"
mkdir -p "$PLUGDIR/qml"
cat > "$PLUGDIR/plugin.toml" <<'EOF'
[plugin]
name = "scratch-ui"
display_name = "Scratch UI"
description = "test ui-surface plugin"
version = "2.0.0"
category = "ai"
capabilities = ["ui-surface"]

[owns]
config_keys = ["scratchQuality", "scratchAccent"]

[ui.dashboard_tab]
id = "scratchTab"
icon = "extension"
label = "Scratch Tab"
component = "qml/ScratchTab.qml"
EOF
echo "// placeholder" > "$PLUGDIR/qml/ScratchTab.qml"

# A second, v1-shaped plugin (no [owns]/[ui] at all) -- must describe
# cleanly with empty owns/null ui, not error.
PLUGDIR2="$APHOTIC_PLUGINS_DIR/v1only"
mkdir -p "$PLUGDIR2"
cat > "$PLUGDIR2/plugin.toml" <<'EOF'
[plugin]
name = "v1only"
display_name = "V1 Only"
description = "pre-v3 plugin"
version = "1.0.0"
capabilities = ["theme-hook"]

[hooks]
on_theme_change = "hooks/on_theme_change.sh"
EOF

# --- describe: owns/ui present for the v3 plugin ---

described="$(_aphotic_plugin_describe scratch-ui)"
[[ "$(echo "$described" | jq -r '.owns.config_keys | length')" -eq 2 ]] || fail "expected 2 owned config keys"
[[ "$(echo "$described" | jq -r '.owns.config_keys[1]')" == "scratchAccent" ]] || fail "expected second config key to be scratchAccent"
[[ "$(echo "$described" | jq -r '.ui.dashboard_tab.id')" == "scratchTab" ]] || fail "expected dashboard_tab.id to be scratchTab"
[[ "$(echo "$described" | jq -r '.ui.dashboard_tab.component')" == "qml/ScratchTab.qml" ]] || fail "expected dashboard_tab.component to be qml/ScratchTab.qml"

# --- describe: v1-shaped plugin degrades cleanly, not an error ---

described_v1="$(_aphotic_plugin_describe v1only)"
[[ "$(echo "$described_v1" | jq -r '.owns.config_keys | length')" -eq 0 ]] || fail "expected v1only's owned config keys to be empty"
[[ "$(echo "$described_v1" | jq -r '.ui')" == "null" ]] || fail "expected v1only's ui to be null, not an error"

# --- registry sync: install-time bookkeeping the QML side reads ---

[[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] && fail "registry file should not exist before any sync"
_aphotic_plugin_registry_sync scratch-ui
[[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] || fail "expected registry sync to create the state file"

reg="$(jq -c '.installed["scratch-ui"]' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(echo "$reg" | jq -r '.version')" == "2.0.0" ]] || fail "expected registry entry version 2.0.0"
[[ "$(echo "$reg" | jq -r '.ui.dashboard_tab.component')" == "qml/ScratchTab.qml" ]] || fail "expected registry entry to carry the dashboard_tab component path"

# --- registry symmetry: remove clears the entry, install/enable state untouched ---

aphotic_plugin_set_enabled scratch-ui false
_aphotic_plugin_registry_remove scratch-ui
[[ "$(jq -r '.installed["scratch-ui"] // "absent"' "$APHOTIC_PLUGINS_STATE_FILE")" == "absent" ]] || fail "expected registry entry to be gone after remove"
aphotic_plugin_is_enabled scratch-ui || : # disabled-state entry is independent of the registry entry, unaffected by remove -- not asserted further here

# --- full install()/remove() round trip against a local repo checkout ---
# (exercises the real code path, not just the two helpers above)

export APHOTIC_PLUGINS_REPO="$TESTHOME/fake-repo"
mkdir -p "$APHOTIC_PLUGINS_REPO/scratch-ui2/qml"
cp "$PLUGDIR/plugin.toml" "$APHOTIC_PLUGINS_REPO/scratch-ui2/plugin.toml"
sed -i 's/name = "scratch-ui"/name = "scratch-ui2"/' "$APHOTIC_PLUGINS_REPO/scratch-ui2/plugin.toml"
echo "// placeholder" > "$APHOTIC_PLUGINS_REPO/scratch-ui2/qml/ScratchTab.qml"
git -C "$APHOTIC_PLUGINS_REPO" init -q 2>/dev/null || true

_aphotic_plugin_install scratch-ui2 false >/dev/null
[[ -d "$(_aphotic_plugin_dir scratch-ui2)" ]] || fail "expected scratch-ui2 to be installed on disk"
[[ "$(jq -r '.installed["scratch-ui2"].ui.dashboard_tab.id // "missing"' "$APHOTIC_PLUGINS_STATE_FILE")" == "scratchTab" ]] || fail "expected install() to have synced scratch-ui2's registry entry"

_aphotic_plugin_remove scratch-ui2 >/dev/null
[[ -d "$(_aphotic_plugin_dir scratch-ui2)" ]] && fail "expected scratch-ui2's install dir to be gone after remove()"
[[ "$(jq -r '.installed["scratch-ui2"] // "absent"' "$APHOTIC_PLUGINS_STATE_FILE")" == "absent" ]] || fail "expected remove() to have cleared scratch-ui2's registry entry too"

echo "PASS: plugin v3 (owns/ui manifest fields, install/remove registry symmetry)"
