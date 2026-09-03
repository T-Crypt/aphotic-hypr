#!/usr/bin/env bash
# tests/test_plugin_v3.sh
# Manifest v3: [owns]/[ui.*] parsing, and the install/remove
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
requires_layer = "ai"
requires_data = "harness"

[ui.notch_tile]
id = "scratchTile"
icon = "monitoring"
label = "Scratch Tile"
component = "qml/ScratchTile.qml"

[ui.settings_pane]
id = "scratchPane"
icon = "tune"
label = "Scratch Pane"
component = "qml/ScratchPane.qml"
requires_layer = "dev"
parent = "language"
EOF
echo "// placeholder" > "$PLUGDIR/qml/ScratchTab.qml"
echo "// placeholder" > "$PLUGDIR/qml/ScratchTile.qml"
echo "// placeholder" > "$PLUGDIR/qml/ScratchPane.qml"

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
[[ "$(echo "$described" | jq -r '.ui.surfaces | length')" == "3" ]] || fail "expected all three declared surfaces to be described"
[[ "$(echo "$described" | jq -r '.ui.surfaces[0].surface')" == "dashboard" ]] || fail "expected the first surface to be the dashboard tab"
[[ "$(echo "$described" | jq -r '.ui.surfaces[0].id')" == "scratchTab" ]] || fail "expected dashboard surface id to be scratchTab"
[[ "$(echo "$described" | jq -r '.ui.surfaces[0].component')" == "qml/ScratchTab.qml" ]] || fail "expected dashboard surface component to be qml/ScratchTab.qml"
[[ "$(echo "$described" | jq -r '.ui.surfaces[0].requires_layer')" == "ai" ]] || fail "expected the declared requires_layer to survive into the description"
[[ "$(echo "$described" | jq -r '.ui.surfaces[0].requires_data')" == "harness" ]] || fail "expected the declared requires_data to survive into the description"
[[ "$(echo "$described" | jq -r '.ui.surfaces[1].surface')" == "notch" ]] || fail "expected the second surface to be the notch tile"
[[ "$(echo "$described" | jq -r '.ui.surfaces[1].id')" == "scratchTile" ]] || fail "expected notch surface id to be scratchTile"
[[ "$(echo "$described" | jq -r '.ui.surfaces[1].requires_layer')" == "" ]] || fail "expected an undeclared gate to read as empty, not null"
[[ "$(echo "$described" | jq -r '.ui.surfaces[2].surface')" == "settings" ]] || fail "expected the third surface to be the settings pane"
[[ "$(echo "$described" | jq -r '.ui.surfaces[2].id')" == "scratchPane" ]] || fail "expected settings surface id to be scratchPane"
[[ "$(echo "$described" | jq -r '.ui.surfaces[2].requires_layer')" == "dev" ]] || fail "expected the settings pane's own layer gate to survive"
# A settings pane docks into a category as a section; it never becomes a
# rail entry of its own, which is what keeps the rail a fixed length.
[[ "$(echo "$described" | jq -r '.ui.surfaces[2].parent')" == "language" ]] || fail "expected the settings pane's declared parent category to survive"
[[ "$(echo "$described" | jq -r '.ui.surfaces[0].parent')" == "" ]] || fail "expected a non-settings surface to carry an empty parent, not null"

# --- profile capability: a plugin that registers a ProfileEngine profile ---
# rather than drawing a surface. Claims are deliberately not declared in
# the manifest -- ProfileEngine.register() takes them from the component.

PROFDIR="$APHOTIC_PLUGINS_DIR/scratch-profile"
mkdir -p "$PROFDIR/qml"
cat > "$PROFDIR/plugin.toml" <<'EOF'
[plugin]
name = "scratch-profile"
display_name = "Scratch Profile"
description = "test profile plugin"
version = "1.0.0"
category = "gaming"
capabilities = ["profile"]

[profile]
id = "scratchProfile"
label = "Scratch Profile"
component = "qml/ScratchProfile.qml"
snapshot = ["dnd", "theme"]
requires_layer = "gaming"
EOF
echo "// placeholder" > "$PROFDIR/qml/ScratchProfile.qml"

described_profile="$(_aphotic_plugin_describe scratch-profile)"
[[ "$(echo "$described_profile" | jq -r '.profile.id')" == "scratchProfile" ]] || fail "expected the profile id to be described"
[[ "$(echo "$described_profile" | jq -r '.profile.component')" == "qml/ScratchProfile.qml" ]] || fail "expected the profile component path to be described"
[[ "$(echo "$described_profile" | jq -r '.profile.requires_layer')" == "gaming" ]] || fail "expected the profile's layer gate to be described"
[[ "$(echo "$described_profile" | jq -r '.profile.snapshot | join(",")')" == "dnd,theme" ]] || fail "expected the profile's snapshot list to be described"
[[ "$(echo "$described_profile" | jq -r '.ui')" == "null" ]] || fail "expected a profile-only plugin to declare no ui surfaces"


# A ui-only plugin must record profile: null, not a half-built object --
# PluginRegistry keys profileRegistrations off exactly that.
[[ "$(echo "$described" | jq -r '.profile')" == "null" ]] || fail "expected a ui-only plugin's profile to be null"

# --- describe: v1-shaped plugin degrades cleanly, not an error ---

described_v1="$(_aphotic_plugin_describe v1only)"
[[ "$(echo "$described_v1" | jq -r '.owns.config_keys | length')" -eq 0 ]] || fail "expected v1only's owned config keys to be empty"
[[ "$(echo "$described_v1" | jq -r '.ui')" == "null" ]] || fail "expected v1only's ui to be null, not an error"
[[ "$(echo "$described_v1" | jq -r '.profile')" == "null" ]] || fail "expected v1only's profile to be null, not an error"

# --- registry sync: install-time bookkeeping the QML side reads ---

[[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] && fail "registry file should not exist before any sync"
_aphotic_plugin_registry_sync scratch-ui
[[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] || fail "expected registry sync to create the state file"

reg="$(jq -c '.installed["scratch-ui"]' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(echo "$reg" | jq -r '.version')" == "2.0.0" ]] || fail "expected registry entry version 2.0.0"
[[ "$(echo "$reg" | jq -r '.ui.surfaces[0].component')" == "qml/ScratchTab.qml" ]] || fail "expected registry entry to carry the dashboard surface component path"
[[ "$(echo "$reg" | jq -r '.ui.surfaces[1].surface')" == "notch" ]] || fail "expected registry entry to carry the notch surface too"

_aphotic_plugin_registry_sync scratch-profile
[[ "$(jq -r '.installed["scratch-profile"].profile.id' "$APHOTIC_PLUGINS_STATE_FILE")" == "scratchProfile" ]] || fail "expected the registry entry to carry the profile block"

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
[[ "$(jq -r '.installed["scratch-ui2"].ui.surfaces[0].id // "missing"' "$APHOTIC_PLUGINS_STATE_FILE")" == "scratchTab" ]] || fail "expected install() to have synced scratch-ui2's registry entry"

_aphotic_plugin_remove scratch-ui2 >/dev/null
[[ -d "$(_aphotic_plugin_dir scratch-ui2)" ]] && fail "expected scratch-ui2's install dir to be gone after remove()"
[[ "$(jq -r '.installed["scratch-ui2"] // "absent"' "$APHOTIC_PLUGINS_STATE_FILE")" == "absent" ]] || fail "expected remove() to have cleared scratch-ui2's registry entry too"

# --- ui module symlink: install links it, remove unlinks it, a bare
# ui-surface *without* a qml/qmldir (like scratch-ui above) is a no-op ---
# Real bug, caught live 2026-08-30: a plugin's same-directory `pragma
# Singleton` sibling does not reliably resolve without a real qmldir +
# explicit import, and that import can't resolve at all unless the
# plugin's qml/ dir is symlinked into the shell's own qs.* import root.
# See _aphotic_plugin_link_ui_module's own comment.

[[ -e "${QUICKSHELL_CONFIG_DIR}/modules/plugins/scratchTab" ]] && fail "scratch-ui/scratch-ui2 ship no qml/qmldir -- expected no symlink to have been created for them"

PLUGDIR3="$APHOTIC_PLUGINS_DIR/scratch-modular"
mkdir -p "$PLUGDIR3/qml"
cat > "$PLUGDIR3/plugin.toml" <<'EOF'
[plugin]
name = "scratch-modular"
display_name = "Scratch Modular"
description = "test ui-surface plugin with a real qmldir"
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.dashboard_tab]
id = "scratchModularTab"
component = "qml/ScratchModularTab.qml"
EOF
cat > "$PLUGDIR3/qml/qmldir" <<'EOF'
module qs.modules.plugins.scratchModular
ScratchModularTab 1.0 ScratchModularTab.qml
EOF
echo "// placeholder" > "$PLUGDIR3/qml/ScratchModularTab.qml"

link_path="${QUICKSHELL_CONFIG_DIR}/modules/plugins/scratchModular"
[[ -e "$link_path" ]] && fail "link should not exist before install links it"
_aphotic_plugin_link_ui_module scratch-modular
[[ -L "$link_path" ]] || fail "expected _aphotic_plugin_link_ui_module to create a symlink at $link_path"
[[ "$(readlink -f "$link_path")" == "$(readlink -f "$PLUGDIR3/qml")" ]] || fail "expected the symlink to point at the plugin's qml/ dir"

_aphotic_plugin_unlink_ui_module scratch-modular
[[ -e "$link_path" ]] && fail "expected _aphotic_plugin_unlink_ui_module to remove the symlink"

# --- relink-all: simulates install.sh's deploy_user_configs wiping
# QUICKSHELL_CONFIG_DIR/modules/plugins/* on every config redeploy ---

_aphotic_plugin_link_ui_module scratch-modular
rm -rf "${QUICKSHELL_CONFIG_DIR}/modules/plugins" # the redeploy wipes this
[[ -e "$link_path" ]] && fail "sanity: link should be gone after simulating a config redeploy"
_aphotic_plugin_relink_all_ui_modules
[[ -L "$link_path" ]] || fail "expected relink-all to restore the symlink after a simulated config redeploy"

# A disabled plugin must not get relinked.
aphotic_plugin_set_enabled scratch-modular false
rm -rf "${QUICKSHELL_CONFIG_DIR}/modules/plugins"
_aphotic_plugin_relink_all_ui_modules
[[ -e "$link_path" ]] && fail "expected relink-all to skip a disabled plugin"
aphotic_plugin_set_enabled scratch-modular true

echo "PASS: plugin v3 (owns/ui manifest fields, install/remove registry symmetry, ui-module symlink + relink-all)"
