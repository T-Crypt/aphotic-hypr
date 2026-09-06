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

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-audit"
mkdir -p "$PLUGDIR/qml"
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "scratch-audit"
display_name = "Scratch Audit"
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.workspace]
id = "scratchAudit"
label = "Scratch Audit"
icon = "fact_check"
component = "qml/Audit.qml"
requires_layer = "ai"
requires_data = "harness"
TOML

ui="$(_aphotic_plugin_ui_json "$PLUGDIR/plugin.toml")"
workspace="$(jq -c '.surfaces[]? | select(.surface == "workspace")' <<<"$ui")"
[[ -n "$workspace" ]] || fail "workspace surface not parsed: $ui"
[[ "$(jq -r '.id' <<<"$workspace")" == "scratchAudit" ]] || fail "workspace id not parsed: $workspace"
[[ "$(jq -r '.requires_layer' <<<"$workspace")" == "ai" ]] || fail "workspace layer gate not parsed: $workspace"
[[ "$(jq -r '.requires_data' <<<"$workspace")" == "harness" ]] || fail "workspace data gate not parsed: $workspace"

_aphotic_plugin_registry_sync scratch-audit || fail "workspace registry sync failed"
entry="$(jq -c '.installed["scratch-audit"].ui.surfaces[] | select(.surface == "workspace")' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(jq -r '.component' <<<"$entry")" == "qml/Audit.qml" ]] || fail "workspace registry entry missing: $entry"

scanned="$(_aphotic_plugin_manifest_surfaces "$PLUGDIR/plugin.toml")"
_aphotic_plugin_in_list "workspace" "$scanned" || fail "workspace scanner missed manifest section: $scanned"
_aphotic_plugin_in_list "workspace" "$APHOTIC_PLUGIN_HOSTED_SURFACES" || fail "workspace host declaration missing"
[[ "$(_aphotic_plugin_host_verdict "ui-surface" "workspace")" == "ok" ]] || fail "workspace should be fully hosted"

echo "PASS: tests/test_plugin_workspace_surface.sh"
