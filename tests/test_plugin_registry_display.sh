#!/usr/bin/env bash
# tests/test_plugin_registry_display.sh
# The registry (~/.local/state/aphotic/plugins.json) carries a plugin's
# display metadata, not just its contract. Settings -> Plugins renders the
# whole installed list out of that file through PluginRegistry.qml; before
# it did, the pane shelled out to `aphotic plugin list --json` on every
# open, which re-reads every manifest on the machine and measured ~200ms
# per installed plugin.
#
# Two things this guards:
#   - the four display fields are actually written, and backfilled onto
#     entries an older CLI wrote without them
#   - adding them did not make every installed plugin report drift. Drift
#     compares the contract keys only; a whole-object compare would read
#     the new keys as unexpected and flag everything, which is exactly
#     what adding `profile` did once before.
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
SRC="$APHOTIC_PLUGINS_REPO/scratch-display"
mkdir -p "$SRC"
cat > "$SRC/plugin.toml" <<'EOF'
[plugin]
name = "scratch-display"
display_name = "Scratch Display"
description = "carries display metadata"
version = "1.0.0"
category = "dev"
capabilities = ["theme-hook"]

[requires]
binaries = ["jq", "definitely-not-a-real-binary"]

[hooks]
on_theme_change = "hook.sh"
EOF
printf '#!/bin/sh\nexit 0\n' > "$SRC/hook.sh"
chmod +x "$SRC/hook.sh"

mkdir -p "$(dirname "$(_aphotic_plugin_dir scratch-display)")"
cp -r "$SRC" "$(_aphotic_plugin_dir scratch-display)"
_aphotic_plugin_registry_sync scratch-display

entry_of() { jq -c '.installed["scratch-display"]' "$APHOTIC_PLUGINS_STATE_FILE"; }

# --- the four display fields land in the registry ---

[[ "$(entry_of | jq -r '.display_name')" == "Scratch Display" ]] \
    || fail "expected display_name in the registry entry"
[[ "$(entry_of | jq -r '.description')" == "carries display metadata" ]] \
    || fail "expected description in the registry entry"
[[ "$(entry_of | jq -r '.category')" == "dev" ]] \
    || fail "expected category in the registry entry"
[[ "$(entry_of | jq -r '.requires_binaries | join(",")')" == "jq,definitely-not-a-real-binary" ]] \
    || fail "expected requires_binaries in the registry entry, got: $(entry_of | jq -c '.requires_binaries')"

# --- a manifest with no display_name falls back to the plugin id ---

NONAME="$TESTHOME/fake-repo/scratch-noname"
mkdir -p "$NONAME"
cat > "$NONAME/plugin.toml" <<'EOF'
[plugin]
name = "scratch-noname"
version = "1.0.0"
capabilities = []
EOF
cp -r "$NONAME" "$(_aphotic_plugin_dir scratch-noname)"
_aphotic_plugin_registry_sync scratch-noname
[[ "$(jq -r '.installed["scratch-noname"].display_name' "$APHOTIC_PLUGINS_STATE_FILE")" == "scratch-noname" ]] \
    || fail "expected a manifest with no display_name to fall back to the plugin id"
[[ "$(jq -r '.installed["scratch-noname"].requires_binaries | length' "$APHOTIC_PLUGINS_STATE_FILE")" -eq 0 ]] \
    || fail "expected an absent [requires] section to read as an empty list, not an error"

# --- adding the fields did not turn every plugin into a drift report ---

[[ "$(_aphotic_plugin_describe scratch-display | jq -r '.drifted')" == "false" ]] \
    || fail "a freshly synced plugin must not report drift once the registry carries display metadata"

# A contract change is still drift, so the check did not simply go slack.
sed -i 's/^version = "1.0.0"/version = "1.1.0"/' "$(_aphotic_plugin_dir scratch-display)/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-display | jq -r '.drifted')" == "true" ]] \
    || fail "expected a version change to still report drift"
_aphotic_plugin_registry_sync scratch-display
[[ "$(_aphotic_plugin_describe scratch-display | jq -r '.drifted')" == "false" ]] \
    || fail "expected a re-sync to clear the drift flag"

# A display-only edit is deliberately NOT drift: it changes nothing the
# shell binds behaviour to, and the next sync picks it up anyway.
sed -i 's/^description = .*/description = "edited in place"/' "$(_aphotic_plugin_dir scratch-display)/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-display | jq -r '.drifted')" == "false" ]] \
    || fail "a description edit is not a contract change and must not report drift"

# --- an entry written before the fields existed gets backfilled ---

tmp="$(mktemp)"
jq 'del(.installed["scratch-display"].display_name)
    | del(.installed["scratch-display"].description)
    | del(.installed["scratch-display"].category)
    | del(.installed["scratch-display"].requires_binaries)' \
    "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp" && mv "$tmp" "$APHOTIC_PLUGINS_STATE_FILE"
[[ "$(entry_of | jq -r 'has("display_name")')" == "false" ]] \
    || fail "test setup: expected the display fields to be gone"

_aphotic_plugin_registry_backfill

[[ "$(entry_of | jq -r '.display_name')" == "Scratch Display" ]] \
    || fail "expected the backfill to restore display_name on a pre-existing entry"
[[ "$(entry_of | jq -r '.category')" == "dev" ]] \
    || fail "expected the backfill to restore category on a pre-existing entry"

# Second run is a no-op: nothing is missing, so it must not rewrite.
before="$(stat -c %Y "$APHOTIC_PLUGINS_STATE_FILE")"
sleep 1
_aphotic_plugin_registry_backfill
[[ "$(stat -c %Y "$APHOTIC_PLUGINS_STATE_FILE")" == "$before" ]] \
    || fail "expected the backfill to do nothing once every entry carries the fields"

echo "PASS: the registry carries plugin display metadata, backfills it, and drift ignores it"
