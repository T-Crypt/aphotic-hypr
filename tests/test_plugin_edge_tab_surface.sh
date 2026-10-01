#!/usr/bin/env bash
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

source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"
source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_plugin.sh"

PLUGDIR="$APHOTIC_PLUGINS_DIR/shelf-tabs"
mkdir -p "$PLUGDIR/qml"

# Placement is data. A token the host does not understand has to survive
# parsing untouched so the host can refuse it, rather than being rewritten
# here into something that looks valid.
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "shelf-tabs"
display_name = "Shelf Tabs"
description = "Shelf tab fixture"
category = "productivity"
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.edge_tab]
id = "odd"
label = "Odd"
icon = "dock_to_left"
component = "qml/Odd.qml"
requires_layer = "ai"
requires_data = "harness"
edges = ["sideways", "right"]
notch = true
TOML

odd="$(jq -c '.surfaces[]? | select(.surface == "edge_tab")' <<<"$(_aphotic_plugin_ui_json "$PLUGDIR/plugin.toml")")"
[[ -n "$odd" ]] || fail "edge_tab surface not parsed"
[[ "$(jq -r '.id' <<<"$odd")" == "odd" ]] || fail "id not parsed: $odd"
[[ "$(jq -r '.icon' <<<"$odd")" == "dock_to_left" ]] || fail "icon not parsed: $odd"
[[ "$(jq -r '.component' <<<"$odd")" == "qml/Odd.qml" ]] || fail "component not parsed: $odd"
[[ "$(jq -r '.requires_layer' <<<"$odd")" == "ai" ]] || fail "layer gate not parsed: $odd"
[[ "$(jq -r '.requires_data' <<<"$odd")" == "harness" ]] || fail "data gate not parsed: $odd"
[[ "$(jq -c '.edges' <<<"$odd")" == '["sideways","right"]' ]] || fail "unknown edge token was rewritten: $odd"
[[ "$(jq -r '.notch' <<<"$odd")" == "true" ]] || fail "notch opt-in not parsed: $odd"

# Omitted fields read as both edges and false. The host allows both
# edges and no notch. Nothing here guesses a placement the manifest did not
# declare.
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "shelf-tabs"
display_name = "Shelf Tabs"
description = "Shelf tab fixture"
category = "productivity"
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.edge_tab]
id = "plain"
label = "Plain"
component = "qml/Plain.qml"
TOML
plain="$(jq -c '.surfaces[]? | select(.surface == "edge_tab")' <<<"$(_aphotic_plugin_ui_json "$PLUGDIR/plugin.toml")")"
[[ "$(jq -c '.edges' <<<"$plain")" == '["left","right"]' ]] || fail "omitted edges should allow both: $plain"
[[ "$(jq -r '.notch' <<<"$plain")" == "false" ]] || fail "notch should default false: $plain"

# A present empty placement fails closed instead of taking the omitted default.
printf '%s\n' 'edges = ""' >> "$PLUGDIR/plugin.toml"
empty="$(jq -c '.surfaces[]? | select(.surface == "edge_tab")' <<<"$(_aphotic_plugin_ui_json "$PLUGDIR/plugin.toml")")"
[[ "$(jq -c '.edges' <<<"$empty")" == '[]' ]] || fail "empty placement became both edges: $empty"
sed -i '/^edges =/d' "$PLUGDIR/plugin.toml"

# `notch = false` explicitly is the same answer as omitting it.
sed -i 's/component = "qml\/Plain.qml"/component = "qml\/Plain.qml"\nnotch = false/' "$PLUGDIR/plugin.toml"
[[ "$(jq -r '.notch' <<<"$(jq -c '.surfaces[]? | select(.surface == "edge_tab")' <<<"$(_aphotic_plugin_ui_json "$PLUGDIR/plugin.toml")")")" == "false" ]] \
    || fail "explicit notch=false was not honoured"

# An edge_tab without a component is not a surface at all.
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "shelf-tabs"
display_name = "Shelf Tabs"
description = "Shelf tab fixture"
category = "productivity"
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.edge_tab]
id = "empty"
label = "Empty"
TOML
[[ "$(jq -r '[.surfaces[]? | select(.surface == "edge_tab")] | length' <<<"$(_aphotic_plugin_ui_json "$PLUGDIR/plugin.toml")")" == "0" ]] \
    || fail "componentless edge_tab was accepted"

# Registry round trip, and the host/verdict path that refuses an install
# for a surface this build cannot mount.
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "shelf-tabs"
display_name = "Shelf Tabs"
description = "Shelf tab fixture"
category = "productivity"
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.edge_tab]
id = "rightPanel"
label = "Right panel"
icon = "dock_to_left"
component = "qml/RightPanel.qml"
edges = ["right"]
TOML
_aphotic_plugin_registry_sync shelf-tabs || fail "edge_tab registry sync failed"
entry="$(jq -c '.installed["shelf-tabs"].ui.surfaces[] | select(.surface == "edge_tab")' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(jq -r '.component' <<<"$entry")" == "qml/RightPanel.qml" ]] || fail "registry entry missing component: $entry"
[[ "$(jq -c '.edges' <<<"$entry")" == '["right"]' ]] || fail "registry entry missing edges: $entry"

scanned="$(_aphotic_plugin_manifest_surfaces "$PLUGDIR/plugin.toml")"
_aphotic_plugin_in_list "edge_tab" "$scanned" || fail "edge_tab scanner missed manifest section: $scanned"
_aphotic_plugin_in_list "edge_tab" "$APHOTIC_PLUGIN_HOSTED_SURFACES" || fail "edge_tab host declaration missing"
[[ "$(_aphotic_plugin_host_verdict "ui-surface" "edge_tab")" == "ok" ]] || fail "edge_tab should be fully hosted"

# Validation includes the new section and refuses URL/canonical escapes.
printf '%s\n' 'import QtQuick' 'Item {}' > "$PLUGDIR/qml/RightPanel.qml"
_aphotic_plugin_validate "$PLUGDIR" > "$TESTHOME/edge-validation.log" 2>&1 || { cat "$TESTHOME/edge-validation.log"; fail "valid edge tab rejected"; }
cp "$PLUGDIR/plugin.toml" "$TESTHOME/edge-valid.toml"
mkdir -p "$TESTHOME/outside"
printf '%s\n' 'import QtQuick' 'Item {}' > "$TESTHOME/outside/Outside.qml"
ln -s "$TESTHOME/outside/Outside.qml" "$PLUGDIR/qml/Link.qml"
for bad in '../other/Q.qml' 'qml/%2e%2e/Outside.qml' 'qml/Link.qml'; do
    sed "s|^component = .*|component = \"$bad\"|" "$TESTHOME/edge-valid.toml" > "$PLUGDIR/plugin.toml"
    if _aphotic_plugin_validate "$PLUGDIR" > "$TESTHOME/edge-validation.log" 2>&1; then
        fail "unsafe edge path accepted: $bad"
    fi
done
cp "$TESTHOME/edge-valid.toml" "$PLUGDIR/plugin.toml"

echo "PASS: tests/test_plugin_edge_tab_surface.sh"