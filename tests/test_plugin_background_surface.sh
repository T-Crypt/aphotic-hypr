#!/usr/bin/env bash
# tests/test_plugin_background_surface.sh
# Manifest v3.8's `background` surface kind: a plugin draws on the desktop
# background itself, inside the PanelWindow core already owns. The live
# wallpaper case is what it exists for -- core applies a still frame and
# the plugin animates over it. Covers the manifest parse, the registry
# round-trip, drift, and the host gate. See docs/PLUGIN_LAYER_MODEL.md.
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

# --- manifest parse ----------------------------------------------------

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-background"
mkdir -p "$PLUGDIR/qml"
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "scratch-background"
display_name = "Scratch Background"
description = "test background plugin"
version = "1.0.0"
category = "theming"
capabilities = ["ui-surface"]

[ui.background]
id = "scratchlive"
label = "Scratch Live"
icon = "movie"
component = "qml/Live.qml"
TOML

ui="$(_aphotic_plugin_ui_json "$PLUGDIR/plugin.toml")"
bg="$(jq -c '.surfaces[] | select(.surface == "background")' <<<"$ui")"
[[ -n "$bg" ]]                                        || fail "background surface not parsed: $ui"
[[ "$(jq -r '.id' <<<"$bg")" == "scratchlive" ]]      || fail "id not parsed: $bg"
[[ "$(jq -r '.component' <<<"$bg")" == "qml/Live.qml" ]] || fail "component not parsed: $bg"

# --- no geometry to budget ---------------------------------------------
# Unlike [ui.overlay], the host window here is core's own full-screen
# BackgroundWindow, so a plugin has no say in its size. The keys still
# serialise (one shared surface parser) but must read as the absent
# default rather than as something a host might act on.
[[ "$(jq -r '.width' <<<"$bg")" == "0" ]]  || fail "background should not carry a width budget: $bg"
[[ "$(jq -r '.height' <<<"$bg")" == "0" ]] || fail "background should not carry a height budget: $bg"

# --- ungated is the default --------------------------------------------
# theming is not one of the four profile layers, so the live-wallpaper
# case has no layer to gate on: installing the plugin is the opt-in.
[[ "$(jq -r '.requires_layer' <<<"$bg")" == "" ]] || fail "expected no layer gate: $bg"
[[ "$(jq -r '.requires_data' <<<"$bg")" == "" ]]  || fail "expected no data gate: $bg"

# --- a declared gate still parses --------------------------------------
cat > "$TESTHOME/gated.toml" <<'TOML'
[plugin]
name = "x"
[ui.background]
id = "y"
component = "qml/Y.qml"
requires_layer = "gaming"
TOML
g="$(_aphotic_plugin_ui_json "$TESTHOME/gated.toml" | jq -c '.surfaces[0]')"
[[ "$(jq -r '.requires_layer' <<<"$g")" == "gaming" ]] || fail "declared gate lost: $g"

# --- a component-less declaration contributes no surface ---------------
printf '[plugin]\nname = "x"\n\n[ui.background]\nid = "y"\n' > "$TESTHOME/partial.toml"
[[ "$(_aphotic_plugin_ui_json "$TESTHOME/partial.toml")" == "null" ]] \
    || fail "an [ui.background] with no component should contribute nothing"

# --- the other kinds are unaffected ------------------------------------
cat > "$TESTHOME/mixed.toml" <<'TOML'
[plugin]
name = "mixed"
[ui.dashboard_tab]
id = "d"
component = "qml/D.qml"
[ui.overlay]
id = "o"
component = "qml/O.qml"
anchor = "top"
width = 100
height = 50
[ui.background]
id = "b"
component = "qml/B.qml"
TOML
mixed="$(_aphotic_plugin_ui_json "$TESTHOME/mixed.toml")"
[[ "$(jq '.surfaces | length' <<<"$mixed")" == "3" ]] \
    || fail "expected all three surfaces to parse: $mixed"
[[ "$(jq -r '.surfaces[] | select(.surface=="dashboard") | .id' <<<"$mixed")" == "d" ]] \
    || fail "dashboard surface broken by the background addition: $mixed"
[[ "$(jq -r '.surfaces[] | select(.surface=="overlay") | .id' <<<"$mixed")" == "o" ]] \
    || fail "overlay surface broken by the background addition: $mixed"

# --- background and overlay stay distinct ------------------------------
# They mount on different layers (background inside core's wallpaper
# window, overlay in its own WlrLayer.Bottom window). A parser that
# collapsed them would put a live wallpaper on top of the desktop clock.
cat > "$TESTHOME/both.toml" <<'TOML'
[plugin]
name = "both"
[ui.overlay]
id = "ov"
component = "qml/O.qml"
[ui.background]
id = "bg"
component = "qml/B.qml"
TOML
both="$(_aphotic_plugin_ui_json "$TESTHOME/both.toml")"
[[ "$(jq -r '.surfaces[] | select(.surface=="background") | .id' <<<"$both")" == "bg" ]] \
    || fail "background collapsed into overlay: $both"
[[ "$(jq -r '.surfaces[] | select(.surface=="overlay") | .id' <<<"$both")" == "ov" ]] \
    || fail "overlay collapsed into background: $both"

# --- registry round-trip: what the shell actually reads ----------------

_aphotic_plugin_registry_sync scratch-background || fail "registry sync failed"
entry="$(jq -c '.installed["scratch-background"].ui.surfaces[] | select(.surface=="background")' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(jq -r '.id' <<<"$entry")" == "scratchlive" ]] \
    || fail "registry did not record the background surface: $entry"
[[ "$(jq -r '.component' <<<"$entry")" == "qml/Live.qml" ]] \
    || fail "registry did not record the component: $entry"

# --- drift -------------------------------------------------------------

[[ "$(_aphotic_plugin_describe scratch-background | jq -r '.drifted')" == "false" ]] \
    || fail "a freshly synced plugin should not report drift"

sed -i 's|^component = "qml/Live.qml"|component = "qml/Other.qml"|' "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-background | jq -r '.drifted')" == "true" ]] \
    || fail "editing [ui.background] in place should report drift"
sed -i 's|^component = "qml/Other.qml"|component = "qml/Live.qml"|' "$PLUGDIR/plugin.toml"

# --- host gate ---------------------------------------------------------
# The allowlist and the host grow in the same commit; a surface kind the
# shell reads but the gate does not name would be reported unhosted.

_aphotic_plugin_in_list "background" "$APHOTIC_PLUGIN_HOSTED_SURFACES" \
    || fail "this build hosts the background surface but the gate does not say so"
for kind in dashboard notch settings overlay fullscreen-overlay; do
    _aphotic_plugin_in_list "$kind" "$APHOTIC_PLUGIN_HOSTED_SURFACES" \
        || fail "adding background dropped '$kind' from the hosted list"
done

echo "PASS: tests/test_plugin_background_surface.sh"
