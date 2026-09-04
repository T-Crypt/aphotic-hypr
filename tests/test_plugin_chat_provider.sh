#!/usr/bin/env bash
# tests/test_plugin_chat_provider.sh
# Manifest v3.3's `chat-provider` capability: a plugin contributes a pill
# to the AI chat provider list without shipping a transport. Covers the
# manifest parse, the registry round-trip the shell reads, drift, and the
# host gate. See docs/PLUGIN_LAYER_MODEL.md §3.
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

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-provider"
mkdir -p "$PLUGDIR"
cat > "$PLUGDIR/plugin.toml" <<'EOF'
[plugin]
name = "scratch-provider"
display_name = "Scratch Provider"
description = "test chat-provider plugin"
version = "1.0.0"
category = "ai"
capabilities = ["chat-provider"]

[chat_provider]
id = "scratchbot"
label = "Scratch Bot"
backend = "ollama"
state = "provider.json"
requires_layer = "ai"
EOF

cp="$(_aphotic_plugin_chat_provider_json "$PLUGDIR/plugin.toml")"
[[ "$(jq -r '.id' <<<"$cp")" == "scratchbot" ]]      || fail "id not parsed: $cp"
[[ "$(jq -r '.label' <<<"$cp")" == "Scratch Bot" ]]  || fail "label not parsed: $cp"
[[ "$(jq -r '.backend' <<<"$cp")" == "ollama" ]]     || fail "backend not parsed: $cp"
[[ "$(jq -r '.state' <<<"$cp")" == "provider.json" ]] || fail "state not parsed: $cp"
[[ "$(jq -r '.requires_layer' <<<"$cp")" == "ai" ]]  || fail "gate not parsed: $cp"

# `state` is what the shell watches for {model, systemPrompt}; a manifest
# that omits it must still resolve to a path rather than to nothing, or
# the provider would register and then never become answerable.
cat > "$TESTHOME/nostate.toml" <<'EOF'
[plugin]
name = "x"
[chat_provider]
id = "y"
backend = "ollama"
EOF
[[ "$(_aphotic_plugin_chat_provider_json "$TESTHOME/nostate.toml" | jq -r '.state')" == "provider.json" ]] \
    || fail "expected 'state' to default to provider.json"
# label defaults to the id rather than to empty -- an unlabelled pill is
# a pill the user cannot identify.
[[ "$(_aphotic_plugin_chat_provider_json "$TESTHOME/nostate.toml" | jq -r '.label')" == "y" ]] \
    || fail "expected label to default to the id"

# --- a partial declaration is null, not a half-registered provider -----

for missing in 'id = "y"' 'backend = "ollama"'; do
    printf '[plugin]\nname = "x"\n\n[chat_provider]\n%s\n' "$missing" > "$TESTHOME/partial.toml"
    [[ "$(_aphotic_plugin_chat_provider_json "$TESTHOME/partial.toml")" == "null" ]] \
        || fail "a [chat_provider] with only '$missing' should read as null"
done

# A manifest with no [chat_provider] at all must read as null, not error --
# the same "optional field, no error" contract every other capability has.
printf '[plugin]\nname = "old"\n' > "$TESTHOME/old.toml"
[[ "$(_aphotic_plugin_chat_provider_json "$TESTHOME/old.toml")" == "null" ]] \
    || fail "a manifest with no [chat_provider] should read as null"

# --- registry round-trip: what the shell actually reads ----------------

_aphotic_plugin_registry_sync scratch-provider || fail "registry sync failed"
entry="$(jq -c '.installed["scratch-provider"].chat_provider' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(jq -r '.id' <<<"$entry")" == "scratchbot" ]] \
    || fail "registry did not record the provider: $entry"
[[ "$(jq -r '.backend' <<<"$entry")" == "ollama" ]] \
    || fail "registry did not record the backend: $entry"

# --- drift ------------------------------------------------------------
# The registry schema growing a field must not make every already-stored
# entry report drift; a real edit to the manifest must.

[[ "$(_aphotic_plugin_describe scratch-provider | jq -r '.drifted')" == "false" ]] \
    || fail "a freshly synced plugin should not report drift"

sed -i 's/^label = "Scratch Bot"/label = "Renamed Bot"/' "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-provider | jq -r '.drifted')" == "true" ]] \
    || fail "editing [chat_provider] in place should report drift"
sed -i 's/^label = "Renamed Bot"/label = "Scratch Bot"/' "$PLUGDIR/plugin.toml"

# An entry stored before chat_provider existed has no such key. It must
# fill with the same null a fresh sync writes, not read as drifted.
tmp="$(mktemp)"
jq '.installed["scratch-provider"] |= del(.chat_provider)' "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp"
mv "$tmp" "$APHOTIC_PLUGINS_STATE_FILE"
printf '[plugin]\nname = "scratch-provider"\ndisplay_name = "Scratch Provider"\nversion = "1.0.0"\ncategory = "ai"\ncapabilities = ["chat-provider"]\n' > "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-provider | jq -r '.drifted')" == "false" ]] \
    || fail "a pre-chat_provider registry entry should fill with null, not report drift"

# --- host gate --------------------------------------------------------

_aphotic_plugin_in_list "chat-provider" "$APHOTIC_PLUGIN_HOSTED_CAPABILITIES" \
    || fail "this build hosts chat-provider but the gate does not say so"
[[ "$(_aphotic_plugin_host_verdict "chat-provider" "")" == "ok" ]] \
    || fail "a chat-provider-only plugin should be ok on this build"

echo "PASS: plugin chat-provider capability (manifest parse, defaults, partial declarations, registry round-trip, drift, host gate)"
