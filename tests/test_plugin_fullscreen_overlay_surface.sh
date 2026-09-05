#!/usr/bin/env bash
# tests/test_plugin_fullscreen_overlay_surface.sh
# Manifest v3.5's `fullscreen-overlay` surface kind: a plugin contributes
# a surface that covers one output and takes every event on it, rather
# than the fixed-budget click-through box `overlay` gives it. Covers the
# manifest parse, the trigger vocabulary, the registry round-trip, drift,
# and the host gate -- including the gate's own scanner, which has to see
# a hyphenated kind to report it at all.
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

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-saver"
mkdir -p "$PLUGDIR/qml"
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "scratch-saver"
display_name = "Scratch Saver"
description = "test fullscreen overlay plugin"
version = "1.0.0"
category = "theming"
capabilities = ["ui-surface"]

[ui.fullscreen-overlay]
id = "scratchsaver"
label = "Scratch Saver"
icon = "screenshot_monitor"
component = "qml/Saver.qml"
trigger = "idle"
TOML

ui="$(_aphotic_plugin_ui_json "$PLUGDIR/plugin.toml")"
fs="$(jq -c '.surfaces[] | select(.surface == "fullscreen-overlay")' <<<"$ui")"
[[ -n "$fs" ]]                                          || fail "fullscreen-overlay surface not parsed: $ui"
[[ "$(jq -r '.id' <<<"$fs")" == "scratchsaver" ]]       || fail "id not parsed: $fs"
[[ "$(jq -r '.component' <<<"$fs")" == "qml/Saver.qml" ]] || fail "component not parsed: $fs"
[[ "$(jq -r '.trigger' <<<"$fs")" == "idle" ]]          || fail "trigger not parsed: $fs"

# A fullscreen overlay declares no geometry -- it is the output. The
# budget fields still come through as numbers so the one registry shape
# stays uniform across every kind; the host simply ignores them.
[[ "$(jq -r '.width | type' <<<"$fs")" == "number" ]]   || fail "width should still be a number: $fs"

# An omitted trigger parses as empty here and is defaulted by the
# registry, not by this side -- so it must not arrive as the string
# "null" or disappear from the record.
cat > "$TESTHOME/notrigger.toml" <<'TOML'
[plugin]
name = "notrigger"

[ui.fullscreen-overlay]
id = "nt"
component = "qml/S.qml"
TOML
nt="$(_aphotic_plugin_ui_json "$TESTHOME/notrigger.toml" | jq -c '.surfaces[0]')"
[[ "$(jq -r '.trigger' <<<"$nt")" == "" ]]              || fail "absent trigger should parse empty: $nt"

# Same "no component, no surface" rule every other kind follows.
printf '[plugin]\nname = "x"\n\n[ui.fullscreen-overlay]\nid = "y"\n' > "$TESTHOME/partial.toml"
[[ "$(_aphotic_plugin_ui_json "$TESTHOME/partial.toml")" == "null" ]] \
    || fail "an [ui.fullscreen-overlay] with no component should contribute nothing"

# Adding the kind must not have disturbed the other four.
cat > "$TESTHOME/mixed.toml" <<'TOML'
[plugin]
name = "mixed"

[ui.dashboard_tab]
id = "d"
component = "qml/D.qml"

[ui.overlay]
id = "o"
component = "qml/O.qml"

[ui.fullscreen-overlay]
id = "f"
component = "qml/F.qml"
TOML
mixed="$(_aphotic_plugin_ui_json "$TESTHOME/mixed.toml")"
[[ "$(jq '.surfaces | length' <<<"$mixed")" == "3" ]]   || fail "mixed manifest lost a surface: $mixed"
[[ -n "$(jq -c '.surfaces[] | select(.surface == "dashboard")' <<<"$mixed")" ]] \
    || fail "dashboard surface broken by the fullscreen-overlay addition: $mixed"
[[ -n "$(jq -c '.surfaces[] | select(.surface == "overlay")' <<<"$mixed")" ]] \
    || fail "overlay surface broken by the fullscreen-overlay addition: $mixed"

# --- registry round-trip and drift -------------------------------------

_aphotic_plugin_registry_sync scratch-saver || fail "registry sync failed"
entry="$(jq -c '.installed["scratch-saver"].ui.surfaces[] | select(.surface=="fullscreen-overlay")' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(jq -r '.trigger' <<<"$entry")" == "idle" ]] \
    || fail "registry did not record the trigger: $entry"

[[ "$(_aphotic_plugin_describe scratch-saver | jq -r '.drifted')" == "false" ]] \
    || fail "a freshly synced plugin should not report drift"

sed -i 's/trigger = "idle"/trigger = "manual"/' "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-saver | jq -r '.drifted')" == "true" ]] \
    || fail "editing [ui.fullscreen-overlay] in place should report drift"

# --- host gate ---------------------------------------------------------

# The gate's scanner reads section headers directly, so a hyphen in the
# kind name has to survive it. Before v3.5 the pattern was [a-z_]* and
# this section scanned as nothing at all, which would have reported an
# unhostable plugin as simply having no surfaces.
scanned="$(_aphotic_plugin_manifest_surfaces "$PLUGDIR/plugin.toml")"
_aphotic_plugin_in_list "fullscreen-overlay" "$scanned" \
    || fail "the manifest scanner does not see a hyphenated kind: $scanned"

_aphotic_plugin_in_list "fullscreen-overlay" "$APHOTIC_PLUGIN_HOSTED_SURFACES" \
    || fail "this build hosts the fullscreen-overlay surface but the gate does not say so"
for kind in dashboard notch settings overlay; do
    _aphotic_plugin_in_list "$kind" "$APHOTIC_PLUGIN_HOSTED_SURFACES" \
        || fail "adding fullscreen-overlay dropped '$kind' from the hosted list"
done

[[ "$(_aphotic_plugin_host_verdict "ui-surface" "fullscreen-overlay")" == "ok" ]] \
    || fail "a fullscreen-overlay-only plugin should be fully hosted"

echo "PASS: tests/test_plugin_fullscreen_overlay_surface.sh"
