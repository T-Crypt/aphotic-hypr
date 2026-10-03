#!/usr/bin/env bash
# tests/test_plugin_api.sh
# Manifest v3.9's [api]: the shell runtime API version and the calls a
# plugin declares. Covers the manifest parse, validate, the install gate
# on a newer API version, the registry round-trip and drift, `aphotic
# plugin api`, and that the CLI and the shell agree on the call list.
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

# --- the CLI and the shell hand out the same calls ---------------------
CORE="$ROOT/Configs/quickshell/aphotic/services/PluginApiCore.js"
js_uses="$(sed -n "s/^var USES = \[\(.*\)\];/\1/p" "$CORE" | tr -d "' " | tr ',' ' ')"
[[ "$js_uses" == "$APHOTIC_PLUGIN_API_USES" ]] \
    || fail "PluginApiCore.js USES ($js_uses) != APHOTIC_PLUGIN_API_USES ($APHOTIC_PLUGIN_API_USES)"
js_version="$(sed -n 's/^var VERSION = \([0-9]*\);/\1/p' "$CORE")"
[[ "$js_version" == "$APHOTIC_PLUGIN_API_VERSION" ]] || fail "API version differs: js $js_version, cli $APHOTIC_PLUGIN_API_VERSION"
for use in $APHOTIC_PLUGIN_API_USES; do
    [[ -n "$(_aphotic_plugin_api_describe "$use")" ]] || fail "no description for $use"
done

# --- manifest parse -----------------------------------------------------
make_plugin() { # dir api-block
    mkdir -p "$1/qml"
    cat > "$1/plugin.toml" <<TOML
[plugin]
name = "$(basename "$1")"
display_name = "Scratch Api"
description = "test api plugin"
version = "1.0.0"
category = "productivity"
capabilities = ["action"]

[action]
id = "doThing"
component = "qml/Do.qml"
$2
TOML
    echo 'import QtQuick; QtObject {}' > "$1/qml/Do.qml"
}

SRC="$TESTHOME/src"
make_plugin "$SRC/scratch-api" $'\n[api]\nversion = 1\nuses = ["context.observe", "resource.observe"]'
api="$(_aphotic_plugin_api_json "$SRC/scratch-api/plugin.toml")"
[[ "$(jq -c . <<<"$api")" == '{"version":1,"uses":["context.observe","resource.observe"]}' ]] || fail "api not parsed: $api"

make_plugin "$SRC/no-api" ""
[[ "$(_aphotic_plugin_api_json "$SRC/no-api/plugin.toml")" == "null" ]] || fail "no [api] should be null"
[[ "$(_aphotic_plugin_api_version "$SRC/no-api/plugin.toml")" == "0" ]] || fail "no [api] should be version 0"

make_plugin "$SRC/implicit-v1" $'\n[api]\nuses = ["context.observe"]'
[[ "$(jq -r .version <<<"$(_aphotic_plugin_api_json "$SRC/implicit-v1/plugin.toml")")" == "1" ]] || fail "missing version should read as 1"

# --- validate -----------------------------------------------------------
out="$(_aphotic_plugin_validate "$SRC/scratch-api" 2>&1)" || fail "valid api plugin failed validate: $out"

make_plugin "$SRC/typo-api" $'\n[api]\nversion = 1\nuses = ["context.observ"]'
out="$(_aphotic_plugin_validate "$SRC/typo-api" 2>&1)" || fail "unknown use should warn, not fail: $out"
grep -q "uses 'context.observ' isn't part of plugin API v2" <<<"$out" || fail "expected an unknown-use warning: $out"

make_plugin "$SRC/future-api" $'\n[api]\nversion = 3\nuses = ["context.observe"]'
out="$(_aphotic_plugin_validate "$SRC/future-api" 2>&1)" && fail "API v3 should fail validate: $out"
grep -q "newer than this build's plugin API" <<<"$out" || fail "expected a version error: $out"

make_plugin "$SRC/bad-version" $'\n[api]\nversion = "one"'
out="$(_aphotic_plugin_validate "$SRC/bad-version" 2>&1)" && fail "non-numeric version should fail validate: $out"
grep -q "is not a whole number" <<<"$out" || fail "expected a whole-number error: $out"

make_plugin "$SRC/sonar-v1" $'\n[api]\nversion = 1\nuses = ["sonar.register"]'
out="$(_aphotic_plugin_validate "$SRC/sonar-v1" 2>&1)" && fail "v1 + sonar.register should fail validate: $out"
grep -q "sonar.register requires plugin API v2" <<<"$out" || fail "expected the grant version error: $out"

# --- install gate, registry round-trip, drift --------------------------
export APHOTIC_PLUGINS_REPO="$SRC"
# A local checkout, so install pulls (and fails the pull, non-fatally)
# instead of cloning the real catalogue.
git -C "$SRC" init -q 2>/dev/null || true
mkdir -p "$APHOTIC_PLUGINS_DIR"
out="$(aphotic_cmd_plugin install future-api 2>&1)" && fail "API v3 install should be refused: $out"
grep -q "plugin API v3, this shell speaks v2" <<<"$out" || fail "expected the version refusal: $out"
[[ -e "$APHOTIC_PLUGINS_DIR/future-api" ]] && fail "refused install must not copy files"

out="$(aphotic_cmd_plugin install sonar-v1 2>&1)" && fail "v1 + sonar.register install should be refused: $out"
grep -q "sonar.register requires plugin API v2" <<<"$out" || fail "expected the grant refusal: $out"
[[ -e "$APHOTIC_PLUGINS_DIR/sonar-v1" ]] && fail "refused install must not copy files"

aphotic_cmd_plugin install scratch-api >/dev/null 2>&1 || fail "api plugin install failed"
stored="$(jq -c '.installed["scratch-api"].api' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$stored" == '{"version":1,"uses":["context.observe","resource.observe"]}' ]] || fail "registry api not stored: $stored"
entry="$(_aphotic_plugin_describe scratch-api)"
[[ "$(jq -r .drifted <<<"$entry")" == "false" ]] || fail "fresh install should not read as drifted: $entry"

# An [api] edit in place is contract drift.
sed -i 's/uses = \["context.observe", "resource.observe"\]/uses = ["context.observe"]/' "$APHOTIC_PLUGINS_DIR/scratch-api/plugin.toml"
[[ "$(jq -r .drifted <<<"$(_aphotic_plugin_describe scratch-api)")" == "true" ]] || fail "an [api] change should read as drift"

aphotic_cmd_plugin install no-api >/dev/null 2>&1 || fail "no-api install failed"
[[ "$(jq -c '.installed["no-api"].api' "$APHOTIC_PLUGINS_STATE_FILE")" == "null" ]] || fail "no [api] should store null"
[[ "$(jq -r .drifted <<<"$(_aphotic_plugin_describe no-api)")" == "false" ]] || fail "no-api plugin should not drift"

# --- aphotic plugin api -------------------------------------------------
out="$(aphotic_cmd_plugin api)"
grep -q "^Plugin API v2" <<<"$out" || fail "api listing header missing: $out"
for use in $APHOTIC_PLUGIN_API_USES; do
    grep -q "  $use " <<<"$out" || fail "api listing missing $use"
done
json="$(aphotic_cmd_plugin api --json)"
[[ "$(jq -r .version <<<"$json")" == "2" ]] || fail "api --json version: $json"
[[ "$(jq -r '[.uses[].id] | join(" ")' <<<"$json")" == "$APHOTIC_PLUGIN_API_USES" ]] || fail "api --json uses: $json"

echo "PASS: plugin API manifest, gate, registry and listing"
