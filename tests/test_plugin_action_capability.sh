#!/usr/bin/env bash
# tests/test_plugin_action_capability.sh
# Manifest v3.7's `action` capability (ACT-01): a plugin declares named
# actions that turn up wherever the shell offers actions, rather than
# registering per surface. Covers the manifest parse, the five numbered
# sections, the registry round-trip, drift, and the host gate.
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

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-action"
mkdir -p "$PLUGDIR/qml/actions"
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "scratch-action"
display_name = "Scratch Action"
description = "test action plugin"
version = "1.0.0"
category = "productivity"
capabilities = ["action"]

[action]
id = "switchThing"
icon = "swap_horiz"
label = "Switch thing"
component = "qml/actions/SwitchThing.qml"

[action_2]
id = "resetThing"
component = "qml/actions/ResetThing.qml"
TOML

actions="$(_aphotic_plugin_actions_json "$PLUGDIR/plugin.toml")"
[[ "$(jq 'length' <<<"$actions")" == "2" ]]                  || fail "expected two actions: $actions"
[[ "$(jq -r '.[0].id' <<<"$actions")" == "switchThing" ]]    || fail "id not parsed: $actions"
[[ "$(jq -r '.[0].icon' <<<"$actions")" == "swap_horiz" ]]   || fail "icon not parsed: $actions"
[[ "$(jq -r '.[0].label' <<<"$actions")" == "Switch thing" ]] || fail "label not parsed: $actions"
[[ "$(jq -r '.[0].component' <<<"$actions")" == "qml/actions/SwitchThing.qml" ]] \
    || fail "component not parsed: $actions"

# Order is the manifest's own numbered order, so a plugin controls which
# of its actions a picker offers first.
[[ "$(jq -r '.[1].id' <<<"$actions")" == "resetThing" ]] || fail "action_2 not second: $actions"

# An action with no label falls back to its id rather than to empty --
# a nameless row in a palette is a row nobody can pick on purpose.
[[ "$(jq -r '.[1].label' <<<"$actions")" == "resetThing" ]] || fail "label fallback lost: $actions"
# The icon does NOT fall back here: PluginRegistry substitutes one, the
# same place it defaults every other surface's icon.
[[ "$(jq -r '.[1].icon' <<<"$actions")" == "" ]] || fail "icon should default in the shell: $actions"

# --- five numbered sections, and no sixth ------------------------------
# Actions are the first capability where one plugin plausibly declares
# several. The cap is bounded room, not a parser: a manifest declaring a
# sixth gets five, silently, which is what the cap being documented is
# for.
{
    echo '[plugin]'
    echo 'name = "many"'
    for n in "" _2 _3 _4 _5 _6; do
        printf '\n[action%s]\nid = "a%s"\ncomponent = "qml/A.qml"\n' "$n" "${n:-_1}"
    done
} > "$TESTHOME/many.toml"
[[ "$(_aphotic_plugin_actions_json "$TESTHOME/many.toml" | jq 'length')" == "5" ]] \
    || fail "expected the documented cap of five actions"

# --- an incomplete declaration contributes nothing ---------------------
printf '[plugin]\nname = "x"\n\n[action]\nid = "y"\n' > "$TESTHOME/partial.toml"
[[ "$(_aphotic_plugin_actions_json "$TESTHOME/partial.toml")" == "null" ]] \
    || fail "an [action] with no component should contribute nothing"
printf '[plugin]\nname = "x"\n\n[action]\ncomponent = "qml/Y.qml"\n' > "$TESTHOME/noid.toml"
[[ "$(_aphotic_plugin_actions_json "$TESTHOME/noid.toml")" == "null" ]] \
    || fail "an [action] with no id should contribute nothing"

# A manifest declaring no actions at all reads as null, the same "absent
# capability" shape profile/cli/chat_provider already write -- the drift
# comparison fills exactly that value in for an entry stored before this
# field existed.
printf '[plugin]\nname = "x"\n' > "$TESTHOME/none.toml"
[[ "$(_aphotic_plugin_actions_json "$TESTHOME/none.toml")" == "null" ]] \
    || fail "a manifest with no actions should read as null"

# --- gates parse, so an action can be layer-scoped ---------------------
cat > "$TESTHOME/gated.toml" <<'TOML'
[plugin]
name = "x"
[action]
id = "y"
component = "qml/Y.qml"
requires_layer = "gaming"
requires_data = "harness"
TOML
g="$(_aphotic_plugin_actions_json "$TESTHOME/gated.toml" | jq -c '.[0]')"
[[ "$(jq -r '.requires_layer' <<<"$g")" == "gaming" ]]  || fail "layer gate lost: $g"
[[ "$(jq -r '.requires_data' <<<"$g")" == "harness" ]]  || fail "data gate lost: $g"

# --- registry round-trip: what the shell actually reads ----------------

_aphotic_plugin_registry_sync scratch-action || fail "registry sync failed"
entry="$(jq -c '.installed["scratch-action"].actions' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(jq 'length' <<<"$entry")" == "2" ]] \
    || fail "registry did not record the actions: $entry"
[[ "$(jq -r '.[0].id' <<<"$entry")" == "switchThing" ]] \
    || fail "registry lost the action id: $entry"

# --- drift -------------------------------------------------------------

[[ "$(_aphotic_plugin_describe scratch-action | jq -r '.drifted')" == "false" ]] \
    || fail "a freshly synced plugin should not report drift"

sed -i 's/^label = "Switch thing"/label = "Swap thing"/' "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-action | jq -r '.drifted')" == "true" ]] \
    || fail "editing [action] in place should report drift"
sed -i 's/^label = "Swap thing"/label = "Switch thing"/' "$PLUGDIR/plugin.toml"

# An entry stored before this field existed must not read as drifted --
# the whole reason the comparison null-fills. Same case `profile` and
# `cli` each hit when they were added.
tmp="$(mktemp)"
jq 'del(.installed["scratch-action"].actions)' "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp"
mv "$tmp" "$APHOTIC_PLUGINS_STATE_FILE"
[[ "$(_aphotic_plugin_describe scratch-action | jq -r '.drifted')" == "true" ]] \
    || fail "a plugin that genuinely declares actions should drift against an entry missing them"

# --- host gate ---------------------------------------------------------

_aphotic_plugin_in_list "action" "$APHOTIC_PLUGIN_HOSTED_CAPABILITIES" \
    || fail "this build hosts the action capability but the gate does not say so"
for cap in ui-surface profile cli chat-provider; do
    _aphotic_plugin_in_list "$cap" "$APHOTIC_PLUGIN_HOSTED_CAPABILITIES" \
        || fail "adding action dropped '$cap' from the hosted list"
done

echo "PASS: tests/test_plugin_action_capability.sh"
