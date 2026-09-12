#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT
export HOME="$TESTHOME" XDG_CONFIG_HOME="$TESTHOME/config" XDG_STATE_HOME="$TESTHOME/state" XDG_DATA_HOME="$TESTHOME/data" APHOTIC_DOTS_DIR="$TESTHOME/dots"
source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"
source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_plugin.sh"
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$APHOTIC_PLUGINS_DIR/consumer/cli" "$APHOTIC_DOTS_DIR"
manifest="$APHOTIC_PLUGINS_DIR/consumer/plugin.toml"
cat > "$manifest" <<'TOML'
[plugin]
name = "consumer"
version = "1.0.0"
capabilities = ["cli", "ui-surface", "profile", "action"]
[cli]
command = "example"
script = "cli/run.sh"
requires_plugin = "prerequisite"
requires_layer = "gaming"
[ui.workspace]
component = "Panel.qml"
requires_plugin = "prerequisite"
[profile]
id = "example"
component = "Profile.qml"
requires_plugin = "prerequisite"
[action]
id = "example"
component = "Action.qml"
requires_plugin = "prerequisite"
TOML
printf 'true\n' > "$APHOTIC_PLUGINS_DIR/consumer/cli/run.sh"
if aphotic_plugin_cli_resolve example >/dev/null; then fail 'missing prerequisite allowed CLI'; fi
mkdir -p "$APHOTIC_PLUGINS_DIR/prerequisite"
printf '[plugin]\nname = "prerequisite"\n' > "$APHOTIC_PLUGINS_DIR/prerequisite/plugin.toml"
aphotic_plugin_cli_resolve example >/dev/null || fail 'enabled prerequisite blocked CLI'
printf '{"disabled":["prerequisite"]}\n' > "$APHOTIC_PLUGINS_STATE_FILE"
if aphotic_plugin_cli_resolve example >/dev/null; then fail 'disabled prerequisite allowed CLI'; fi
[[ -z "$(aphotic_plugin_cli_top_level)" ]] || fail 'disabled prerequisite visible in help'
printf '{"disabled":[]}\n' > "$APHOTIC_PLUGINS_STATE_FILE"
printf '[install]\nlayers = ["ai"]\n' > "$APHOTIC_DOTS_DIR/aphotic.toml"
if aphotic_plugin_cli_resolve example >/dev/null; then fail 'disabled layer allowed CLI'; fi
for result in "$(_aphotic_plugin_cli_json "$manifest")" "$(_aphotic_plugin_surface_json "$manifest" ui.workspace workspace)" "$(_aphotic_plugin_profile_json "$manifest")" "$(_aphotic_plugin_action_entry_json "$manifest" action)"; do
    [[ "$(jq -r .requires_plugin <<<"$result")" == prerequisite ]] || fail 'dependency lost in serialization'
done
_aphotic_plugin_registry_sync consumer
[[ "$(_aphotic_plugin_describe consumer | jq -r .drifted)" == false ]] || fail 'fresh registry drifted'
sed -i '/requires_plugin/d; /requires_layer/d' "$manifest"
_aphotic_plugin_registry_sync consumer
jq 'walk(if type == "object" then del(.requires_plugin) else . end) | del(.installed.consumer.cli.requires_layer)' "$APHOTIC_PLUGINS_STATE_FILE" > "$TESTHOME/old.json"
mv "$TESTHOME/old.json" "$APHOTIC_PLUGINS_STATE_FILE"
[[ "$(_aphotic_plugin_describe consumer | jq -r .drifted)" == false ]] || fail 'old ungated registry drifted'
printf '\nrequires_plugin = "prerequisite"\n' >> "$manifest"
[[ "$(_aphotic_plugin_describe consumer | jq -r .drifted)" == true ]] || fail 'new prerequisite did not drift'
echo 'PASS: plugin dependency gates' 
