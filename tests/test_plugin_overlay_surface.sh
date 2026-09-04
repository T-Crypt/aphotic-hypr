#!/usr/bin/env bash
# tests/test_plugin_overlay_surface.sh
# Manifest v3.4's `overlay` surface kind: a plugin contributes a screen
# overlay -- a window of its own rather than content docked inside one
# core already owns. Covers the manifest parse, the geometry budget the
# host sizes its window from, the registry round-trip, drift, and the host
# gate. See docs/PLUGIN_LAYER_MODEL.md.
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

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-overlay"
mkdir -p "$PLUGDIR/qml"
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "scratch-overlay"
display_name = "Scratch Overlay"
description = "test overlay plugin"
version = "1.0.0"
category = "productivity"
capabilities = ["ui-surface"]

[ui.overlay]
id = "scratchpet"
label = "Scratch Pet"
icon = "pets"
component = "qml/Pet.qml"
anchor = "bottom"
width = 240
height = 200
TOML

ui="$(_aphotic_plugin_ui_json "$PLUGDIR/plugin.toml")"
ov="$(jq -c '.surfaces[] | select(.surface == "overlay")' <<<"$ui")"
[[ -n "$ov" ]]                                     || fail "overlay surface not parsed: $ui"
[[ "$(jq -r '.id' <<<"$ov")" == "scratchpet" ]]    || fail "id not parsed: $ov"
[[ "$(jq -r '.component' <<<"$ov")" == "qml/Pet.qml" ]] || fail "component not parsed: $ov"
[[ "$(jq -r '.anchor' <<<"$ov")" == "bottom" ]]    || fail "anchor not parsed: $ov"
[[ "$(jq -r '.width' <<<"$ov")" == "240" ]]        || fail "width not parsed: $ov"
[[ "$(jq -r '.height' <<<"$ov")" == "200" ]]       || fail "height not parsed: $ov"

# width/height are numbers, not strings -- the host binds them straight to
# PanelWindow's implicitWidth/implicitHeight.
[[ "$(jq -r '.width | type' <<<"$ov")" == "number" ]] \
    || fail "width must serialise as a number, got $(jq -r '.width | type' <<<"$ov")"

# --- ungated is the default, and that is the whole mechanism -----------
# An overlay with no requires_layer/requires_data is available on every
# install. Both plugins that need this kind are ungated-for-all, so an
# empty gate reading as anything but "no gate" would break them.
[[ "$(jq -r '.requires_layer' <<<"$ov")" == "" ]] || fail "expected no layer gate: $ov"
[[ "$(jq -r '.requires_data' <<<"$ov")" == "" ]]  || fail "expected no data gate: $ov"

# --- a declared gate still parses, so ungated stays a choice -----------
cat > "$TESTHOME/gated.toml" <<'TOML'
[plugin]
name = "x"
[ui.overlay]
id = "y"
component = "qml/Y.qml"
requires_layer = "gaming"
TOML
g="$(_aphotic_plugin_ui_json "$TESTHOME/gated.toml" | jq -c '.surfaces[0]')"
[[ "$(jq -r '.requires_layer' <<<"$g")" == "gaming" ]] || fail "declared gate lost: $g"

# A manifest that omits the geometry budget must still resolve to numbers.
# The shell substitutes a usable default; zero here would be a window that
# mounts and silently draws nothing.
[[ "$(jq -r '.width' <<<"$g")" == "0" ]]  || fail "absent width should read as 0, got $g"
[[ "$(jq -r '.height' <<<"$g")" == "0" ]] || fail "absent height should read as 0, got $g"

# --- a component-less declaration contributes no surface ---------------
printf '[plugin]\nname = "x"\n\n[ui.overlay]\nid = "y"\n' > "$TESTHOME/partial.toml"
[[ "$(_aphotic_plugin_ui_json "$TESTHOME/partial.toml")" == "null" ]] \
    || fail "an [ui.overlay] with no component should contribute nothing"

# --- the other three kinds are unaffected ------------------------------
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
TOML
mixed="$(_aphotic_plugin_ui_json "$TESTHOME/mixed.toml")"
[[ "$(jq '.surfaces | length' <<<"$mixed")" == "2" ]] \
    || fail "expected both surfaces to parse: $mixed"
[[ "$(jq -r '.surfaces[] | select(.surface=="dashboard") | .id' <<<"$mixed")" == "d" ]] \
    || fail "dashboard surface broken by the overlay addition: $mixed"

# --- registry round-trip: what the shell actually reads ----------------

_aphotic_plugin_registry_sync scratch-overlay || fail "registry sync failed"
entry="$(jq -c '.installed["scratch-overlay"].ui.surfaces[] | select(.surface=="overlay")' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(jq -r '.id' <<<"$entry")" == "scratchpet" ]] \
    || fail "registry did not record the overlay: $entry"
[[ "$(jq -r '.anchor' <<<"$entry")" == "bottom" ]] \
    || fail "registry did not record the anchor: $entry"

# --- drift -------------------------------------------------------------

[[ "$(_aphotic_plugin_describe scratch-overlay | jq -r '.drifted')" == "false" ]] \
    || fail "a freshly synced plugin should not report drift"

sed -i 's/^anchor = "bottom"/anchor = "top"/' "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-overlay | jq -r '.drifted')" == "true" ]] \
    || fail "editing [ui.overlay] in place should report drift"
sed -i 's/^anchor = "top"/anchor = "bottom"/' "$PLUGDIR/plugin.toml"

# --- host gate ---------------------------------------------------------
# The allowlist and the host grow in the same commit; a surface kind the
# shell reads but the gate does not name would be reported unhosted.

_aphotic_plugin_in_list "overlay" "$APHOTIC_PLUGIN_HOSTED_SURFACES" \
    || fail "this build hosts the overlay surface but the gate does not say so"
for kind in dashboard notch settings; do
    _aphotic_plugin_in_list "$kind" "$APHOTIC_PLUGIN_HOSTED_SURFACES" \
        || fail "adding overlay dropped '$kind' from the hosted list"
done

echo "PASS: tests/test_plugin_overlay_surface.sh"
