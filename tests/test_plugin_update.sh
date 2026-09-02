#!/usr/bin/env bash
# tests/test_plugin_update.sh
# `aphotic plugin update`: refresh an installed plugin's payload from the
# repo in place. The distinguishing behaviour against the old
# remove-then-install workaround is that a disabled plugin stays disabled
# and a staged copy that fails leaves the working install intact.
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
SRC="$APHOTIC_PLUGINS_REPO/scratch-upd"
mkdir -p "$SRC/qml" "$SRC/hooks"
write_manifest() {
    cat > "$SRC/plugin.toml" <<EOF
[plugin]
name = "scratch-upd"
display_name = "Scratch Update"
description = "test plugin"
version = "$1"
category = "ai"
capabilities = ["ui-surface"]

[owns]
config_keys = [$2]

[ui.dashboard_tab]
id = "scratchTab"
icon = "extension"
label = "Scratch Tab"
component = "qml/ScratchTab.qml"
EOF
}
write_manifest "1.0.0" '"keyOne"'
echo "// v1" > "$SRC/qml/ScratchTab.qml"
echo "ScratchTab 1.0 ScratchTab.qml" > "$SRC/qml/qmldir"
printf '#!/bin/sh\nexit 0\n' > "$SRC/hooks/on_theme_change.sh"
git -C "$APHOTIC_PLUGINS_REPO" init -q 2>/dev/null || true

_aphotic_plugin_install scratch-upd false >/dev/null 2>&1
DEST="$(_aphotic_plugin_dir scratch-upd)"
[[ -d "$DEST" ]] || fail "expected scratch-upd installed"

# --- update picks up a new version's files and registry entry ---

write_manifest "1.3.0" '"keyOne", "keyTwo"'
echo "// v2" > "$SRC/qml/ScratchTab.qml"

_aphotic_plugin_update scratch-upd >/dev/null 2>&1
[[ "$(aphotic_toml_get "$DEST/plugin.toml" plugin version)" == "1.3.0" ]] \
    || fail "expected the installed manifest to be at 1.3.0 after update"
grep -qx "// v2" "$DEST/qml/ScratchTab.qml" \
    || fail "expected update to replace the plugin's QML payload"
[[ "$(jq -r '.installed["scratch-upd"].version' "$APHOTIC_PLUGINS_STATE_FILE")" == "1.3.0" ]] \
    || fail "expected update to sync the registry entry's version"
[[ "$(jq -r '.installed["scratch-upd"].owns.config_keys | length' "$APHOTIC_PLUGINS_STATE_FILE")" -eq 2 ]] \
    || fail "expected update to pick up the manifest's new config_keys"

# --- hooks stay executable across an update ---

[[ -x "$DEST/hooks/on_theme_change.sh" ]] || fail "expected hook scripts to stay executable after update"

# --- a disabled plugin stays disabled (the reason update exists) ---

aphotic_plugin_set_enabled scratch-upd false
aphotic_plugin_is_enabled scratch-upd && fail "expected scratch-upd to be disabled before update"
write_manifest "1.4.0" '"keyOne"'
_aphotic_plugin_update scratch-upd >/dev/null 2>&1
aphotic_plugin_is_enabled scratch-upd && fail "expected update to leave a disabled plugin disabled"
[[ "$(aphotic_toml_get "$DEST/plugin.toml" plugin version)" == "1.4.0" ]] \
    || fail "expected a disabled plugin's files to still update"
aphotic_plugin_set_enabled scratch-upd true

# --- a failed stage leaves the working install alone ---

chmod 000 "$SRC/qml/ScratchTab.qml"
if [[ ! -r "$SRC/qml/ScratchTab.qml" ]]; then
    write_manifest "9.9.9" '"keyOne"'
    _aphotic_plugin_update scratch-upd >/dev/null 2>&1 || true
    [[ "$(aphotic_toml_get "$DEST/plugin.toml" plugin version)" == "1.4.0" ]] \
        || fail "expected a failed update to leave the installed version untouched"
    [[ -d "$DEST" ]] || fail "expected a failed update to leave the install dir intact"
    [[ -e "${DEST}.updating" ]] && fail "expected a failed update to clean up its staging dir"
fi
chmod 644 "$SRC/qml/ScratchTab.qml"
write_manifest "1.4.0" '"keyOne"'

# --- a --link install refreshes its registry rather than copying ---

LSRC="$APHOTIC_PLUGINS_REPO/scratch-link"
mkdir -p "$LSRC/qml"
sed 's/scratch-upd/scratch-link/; s/version = "1.4.0"/version = "2.0.0"/' "$SRC/plugin.toml" > "$LSRC/plugin.toml"
echo "// linked" > "$LSRC/qml/ScratchTab.qml"
_aphotic_plugin_install scratch-link true >/dev/null 2>&1
[[ -L "$(_aphotic_plugin_dir scratch-link)" ]] || fail "expected --link install to be a symlink"
sed -i 's/version = "2.0.0"/version = "2.1.0"/' "$LSRC/plugin.toml"
_aphotic_plugin_update scratch-link >/dev/null 2>&1
[[ -L "$(_aphotic_plugin_dir scratch-link)" ]] || fail "expected update to keep a linked install a symlink"
[[ "$(jq -r '.installed["scratch-link"].version' "$APHOTIC_PLUGINS_STATE_FILE")" == "2.1.0" ]] \
    || fail "expected update to refresh a linked install's registry version"

# --- --all covers every installed plugin ---

write_manifest "1.5.0" '"keyOne"'
sed -i 's/version = "2.1.0"/version = "2.2.0"/' "$LSRC/plugin.toml"
_aphotic_plugin_update --all >/dev/null 2>&1
[[ "$(jq -r '.installed["scratch-upd"].version' "$APHOTIC_PLUGINS_STATE_FILE")" == "1.5.0" ]] \
    || fail "expected --all to update scratch-upd"
[[ "$(jq -r '.installed["scratch-link"].version' "$APHOTIC_PLUGINS_STATE_FILE")" == "2.2.0" ]] \
    || fail "expected --all to update scratch-link"

# --- --all skips disabled plugins, but naming one still updates it ---
#
# install_deps runs `yay -S` for missing [requires] binaries, so a blanket
# --all must not act on plugins the user has turned off.

aphotic_plugin_set_enabled scratch-upd false
write_manifest "1.6.0" '"keyOne"'
sed -i 's/version = "2.2.0"/version = "2.3.0"/' "$LSRC/plugin.toml"
out="$(_aphotic_plugin_update --all 2>&1)"
[[ "$(aphotic_toml_get "$DEST/plugin.toml" plugin version)" == "1.5.0" ]] \
    || fail "expected --all to skip the disabled scratch-upd"
[[ "$(jq -r '.installed["scratch-link"].version' "$APHOTIC_PLUGINS_STATE_FILE")" == "2.3.0" ]] \
    || fail "expected --all to still update the enabled scratch-link"
grep -q "scratch-upd" <<<"$out" \
    || fail "expected --all to name the disabled plugin it skipped"
_aphotic_plugin_update scratch-upd >/dev/null 2>&1
[[ "$(aphotic_toml_get "$DEST/plugin.toml" plugin version)" == "1.6.0" ]] \
    || fail "expected an explicitly named disabled plugin to still update"
aphotic_plugin_is_enabled scratch-upd && fail "expected the explicit update to leave it disabled"
aphotic_plugin_set_enabled scratch-upd true

# --- the swap never leaves the install path missing, and rolls back ---

[[ ! -e "${DEST}.previous" ]] || fail "expected update to clean up its rollback copy"
[[ ! -e "${DEST}.updating" ]] || fail "expected update to clean up its staging dir"

# --- not-installed and missing-name are errors, not silent no-ops ---

_aphotic_plugin_update nonexistent >/dev/null 2>&1 && fail "expected update of an uninstalled plugin to fail"
_aphotic_plugin_update "" >/dev/null 2>&1 && fail "expected update with no argument to fail"

echo "PASS: plugin update refreshes in place, preserves disabled state, and stages safely"
