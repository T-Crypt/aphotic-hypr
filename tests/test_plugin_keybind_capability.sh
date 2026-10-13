#!/usr/bin/env bash
# tests/test_plugin_keybind_capability.sh
# Manifest v3.11's `keybind` capability: a plugin names a combo and the
# action it runs, and the shell binds the combo while the plugin is
# installed, enabled and past its gate. Covers the manifest parse, the
# five numbered sections, the registry round-trip, drift, validate, the
# host gate, and the static shape of the QML that does the binding.
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

QML="$ROOT/Configs/quickshell/aphotic"
SERVICES="$QML/services"

# --- manifest parse ----------------------------------------------------

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-keybind"
mkdir -p "$PLUGDIR/qml/actions"
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "scratch-keybind"
display_name = "Scratch Keybind"
description = "test keybind plugin"
version = "1.0.0"
category = "productivity"
capabilities = ["action", "keybind"]

[action]
id = "reload"
label = "Reload Acme"
component = "qml/actions/Reload.qml"

[keybind]
combo = "SUPER + SHIFT + R"
action = "reload"
description = "Reload Acme"
requires_layer = "gaming"

[keybind_2]
combo = "SUPER + SHIFT + E"
action = "reload"
TOML

binds="$(_aphotic_plugin_keybinds_json "$PLUGDIR/plugin.toml")"
[[ "$(jq 'length' <<<"$binds")" == "2" ]]                      || fail "expected two keybinds: $binds"
[[ "$(jq -r '.[0].combo' <<<"$binds")" == "SUPER + SHIFT + R" ]] || fail "combo not parsed: $binds"
[[ "$(jq -r '.[0].action' <<<"$binds")" == "reload" ]]         || fail "action not parsed: $binds"
[[ "$(jq -r '.[0].description' <<<"$binds")" == "Reload Acme" ]] || fail "description not parsed: $binds"
[[ "$(jq -r '.[0].requires_layer' <<<"$binds")" == "gaming" ]] || fail "layer gate lost: $binds"
[[ "$(jq -r '.[0].requires_data' <<<"$binds")" == "" ]]        || fail "data gate should default empty: $binds"

# Order is the manifest's own numbered order, same as actions.
[[ "$(jq -r '.[1].combo' <<<"$binds")" == "SUPER + SHIFT + E" ]] || fail "keybind_2 not second: $binds"

# An omitted description stays empty here; the shell falls back to the
# action's label. Defaulting it in the reader would put a label from a
# different section into a field the manifest left blank.
[[ "$(jq -r '.[1].description' <<<"$binds")" == "" ]] || fail "description should default in the shell: $binds"

# --- five numbered sections, and no sixth ------------------------------

{
    echo '[plugin]'
    echo 'name = "many"'
    for n in "" _2 _3 _4 _5 _6; do
        printf '\n[keybind%s]\ncombo = "SUPER + %s"\naction = "a"\n' "$n" "${n:-1}"
    done
} > "$TESTHOME/many.toml"
[[ "$(_aphotic_plugin_keybinds_json "$TESTHOME/many.toml" | jq 'length')" == "5" ]] \
    || fail "expected the documented cap of five keybinds"

# --- an incomplete declaration contributes nothing ---------------------
# A bind with no action would swallow the combo and run nothing.
printf '[plugin]\nname = "x"\n\n[keybind]\ncombo = "SUPER + R"\n' > "$TESTHOME/noaction.toml"
[[ "$(_aphotic_plugin_keybinds_json "$TESTHOME/noaction.toml")" == "null" ]] \
    || fail "a [keybind] with no action should contribute nothing"
printf '[plugin]\nname = "x"\n\n[keybind]\naction = "reload"\n' > "$TESTHOME/nocombo.toml"
[[ "$(_aphotic_plugin_keybinds_json "$TESTHOME/nocombo.toml")" == "null" ]] \
    || fail "a [keybind] with no combo should contribute nothing"

# A manifest declaring no keybind reads as null, the same "absent
# capability" shape actions/profile/cli write -- the drift comparison
# fills exactly that value in for an entry stored before this field
# existed.
printf '[plugin]\nname = "x"\n' > "$TESTHOME/none.toml"
[[ "$(_aphotic_plugin_keybinds_json "$TESTHOME/none.toml")" == "null" ]] \
    || fail "a manifest with no keybind should read as null"

# --- registry round-trip: what the shell actually reads ----------------

_aphotic_plugin_registry_sync scratch-keybind || fail "registry sync failed"
entry="$(jq -c '.installed["scratch-keybind"].keybinds' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(jq 'length' <<<"$entry")" == "2" ]] \
    || fail "registry did not record the keybinds: $entry"
[[ "$(jq -r '.[0].combo' <<<"$entry")" == "SUPER + SHIFT + R" ]] \
    || fail "registry lost the combo: $entry"

# --- drift -------------------------------------------------------------

[[ "$(_aphotic_plugin_describe scratch-keybind | jq -r '.drifted')" == "false" ]] \
    || fail "a freshly synced plugin should not report drift"

sed -i 's/^combo = "SUPER + SHIFT + R"/combo = "SUPER + SHIFT + T"/' "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-keybind | jq -r '.drifted')" == "true" ]] \
    || fail "editing [keybind] in place should report drift"
sed -i 's/^combo = "SUPER + SHIFT + T"/combo = "SUPER + SHIFT + R"/' "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-keybind | jq -r '.drifted')" == "false" ]] \
    || fail "restoring the manifest should clear drift again"

# An entry stored before this field existed must not read as drifted --
# the whole reason the comparison null-fills. Same case `profile`, `cli`
# and `actions` each hit when they were added.
tmp="$(mktemp)"
jq 'del(.installed["scratch-keybind"].keybinds)' "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp"
mv "$tmp" "$APHOTIC_PLUGINS_STATE_FILE"
[[ "$(_aphotic_plugin_describe scratch-keybind | jq -r '.drifted')" == "true" ]] \
    || fail "a plugin that genuinely declares keybinds should drift against an entry missing them"

# The other direction: a plugin with no keybind section, whose stored
# entry has no keybinds either, must stay clean. A null-fill that wrote
# [] instead of null would flag every keybind-less plugin on upgrade.
BARE="$APHOTIC_PLUGINS_DIR/scratch-nokeybind"
mkdir -p "$BARE"
cat > "$BARE/plugin.toml" <<'TOML'
[plugin]
name = "scratch-nokeybind"
display_name = "Bare"
description = "no keybinds here"
version = "1.0.0"
category = "productivity"
capabilities = ["profile"]
TOML
_aphotic_plugin_registry_sync scratch-nokeybind || fail "registry sync failed for the bare plugin"
[[ "$(jq -c '.installed["scratch-nokeybind"].keybinds' "$APHOTIC_PLUGINS_STATE_FILE")" == "null" ]] \
    || fail "a manifest with no keybind should sync as null"
[[ "$(_aphotic_plugin_describe scratch-nokeybind | jq -r '.drifted')" == "false" ]] \
    || fail "a plugin with no keybind should not drift on the new field"

# --- validate ----------------------------------------------------------

valid_manifest() {
    mkdir -p "$TESTHOME/$1/qml"
    : > "$TESTHOME/$1/qml/A.qml"
    cat > "$TESTHOME/$1/plugin.toml"
}

# The capability and its section agree, and the bind names an action the
# same manifest declares.
valid_manifest kb-ok <<'TOML'
[plugin]
name = "kb-ok"
display_name = "Ok"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["action", "keybind"]
[action]
id = "reload"
component = "qml/A.qml"
[keybind]
combo = "SUPER + SHIFT + R"
action = "reload"
TOML
_aphotic_plugin_validate "$TESTHOME/kb-ok" >/dev/null 2>&1 \
    || fail "a well-formed keybind manifest should validate"

# `keybind` has to be in the build's own known-capability list, not just in
# the hosted one: a capability missing there draws a false "isn't one this
# build recognizes" warning on every plugin that declares it. Both
# directions, so this fails when the entry is dropped and when the warning
# stops being produced at all.
out="$(_aphotic_plugin_validate "$TESTHOME/kb-ok" 2>&1)"
grep -q "isn't one this build recognizes" <<<"$out" \
    && fail "validate called the keybind capability unrecognized: $out"

valid_manifest kb-typo <<'TOML'
[plugin]
name = "kb-typo"
display_name = "Typo"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["action", "keybnid"]
[action]
id = "reload"
component = "qml/A.qml"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/kb-typo" 2>&1)" || fail "an unknown capability should warn, not fail: $out"
grep -q "capability 'keybnid' isn't one this build recognizes" <<<"$out" \
    || fail "validate did not flag an unknown capability: $out"

# A bind to an id this manifest does not declare binds the combo to
# nothing, so it is an error rather than a warning.
valid_manifest kb-dangling <<'TOML'
[plugin]
name = "kb-dangling"
display_name = "Dangling"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["keybind"]
[keybind]
combo = "SUPER + SHIFT + R"
action = "reload"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/kb-dangling" 2>&1)" && fail "a dangling keybind action should fail validate"
grep -q "isn't an \[action\] id this manifest declares" <<<"$out" \
    || fail "validate did not name the dangling action: $out"

# The section with no capability tag is the unhosted case the gate
# exists to catch.
valid_manifest kb-untagged <<'TOML'
[plugin]
name = "kb-untagged"
display_name = "Untagged"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["action"]
[action]
id = "reload"
component = "qml/A.qml"
[keybind]
combo = "SUPER + SHIFT + R"
action = "reload"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/kb-untagged" 2>&1)" && fail "a [keybind] without the capability should fail validate"
grep -q "capabilities doesn't include 'keybind'" <<<"$out" \
    || fail "validate did not name the missing capability: $out"

# The other direction is a warning: a plugin can declare the capability
# ahead of the section, and refusing the install would be worse than
# saying so.
valid_manifest kb-empty <<'TOML'
[plugin]
name = "kb-empty"
display_name = "Empty"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["keybind"]
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/kb-empty" 2>&1)" \
    || fail "a keybind capability with no section should warn, not fail: $out"
grep -q "no \[keybind\] section declares one" <<<"$out" \
    || fail "validate did not warn about the missing section: $out"

# Two of the plugin's own sections on one combo: the second bind replaces
# the first, so one action silently never runs.
valid_manifest kb-dupe <<'TOML'
[plugin]
name = "kb-dupe"
display_name = "Dupe"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["action", "keybind"]
[action]
id = "reload"
component = "qml/A.qml"
[keybind]
combo = "SUPER + SHIFT + R"
action = "reload"
[keybind_2]
combo = "SUPER + SHIFT + R"
action = "reload"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/kb-dupe" 2>&1)" || fail "a duplicate combo should warn, not fail: $out"
grep -q "declared more than once" <<<"$out" \
    || fail "validate did not warn about the duplicate combo: $out"

# A combo is manifest text on its way into a shell line, and it has to be
# one the shell can turn into both bind forms: '+' separated tokens, the
# key last, and every token before it a modifier Hyprland's parsers share.
# Anything else -- a substitution, a quote, an unknown name, a spare key --
# is refused at bind time, so validate refuses it here.
MARKER=/tmp/aphotic-test-kb-injected
rm -f "$MARKER"
valid_manifest kb-inject <<'TOML'
[plugin]
name = "kb-inject"
display_name = "Inject"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["action", "keybind"]
[action]
id = "reload"
component = "qml/A.qml"
[keybind]
combo = "SUPER + SHIFT + $(touch /tmp/aphotic-test-kb-injected)"
action = "reload"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/kb-inject" 2>&1)" && fail "a combo carrying shell syntax should fail validate: $out"
grep -q "isn't a key or a modifier name" <<<"$out" \
    || fail "validate did not name the combo token: $out"
[[ -e "$MARKER" ]] && fail "validate ran the combo"

valid_manifest kb-mod <<'TOML'
[plugin]
name = "kb-mod"
display_name = "Mod"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["action", "keybind"]
[action]
id = "reload"
component = "qml/A.qml"
[keybind]
combo = "MOD9 + R"
action = "reload"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/kb-mod" 2>&1)" && fail "a combo no parser shares a modifier with should fail validate: $out"
grep -q "isn't a modifier both Hyprland parsers know" <<<"$out" \
    || fail "validate did not name the modifier: $out"

# The names Hyprland's parsers share for the four this repo's binds use are
# all accepted, aliases included: refusing one of these would block a combo
# the shell binds happily.
valid_manifest kb-alias <<'TOML'
[plugin]
name = "kb-alias"
display_name = "Alias"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["action", "keybind"]
[action]
id = "reload"
component = "qml/A.qml"
[keybind]
combo = "MOD4 + SHIFT + r"
action = "reload"
[keybind_2]
combo = "XF86AudioMute"
action = "reload"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/kb-alias" 2>&1)" || fail "a combo the shell can bind should validate: $out"
grep -qE "combo '.*' (is empty|has |names )" <<<"$out" \
    && fail "validate refused a bindable combo: $out"

# The description is the bind line's own label field, where a comma shifts
# every field after it: the shell drops such a label rather than bind it,
# and validate says so before install.
valid_manifest kb-comma <<'TOML'
[plugin]
name = "kb-comma"
display_name = "Comma"
description = "d"
version = "1.0.0"
category = "dev"
capabilities = ["action", "keybind"]
[action]
id = "reload"
component = "qml/A.qml"
[keybind]
combo = "SUPER + SHIFT + R"
action = "reload"
description = "Reload, Acme"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/kb-comma" 2>&1)" && fail "a description with a comma should fail validate: $out"
grep -q "has a comma or a control character" <<<"$out" \
    || fail "validate did not name the comma: $out"

# --- host gate ---------------------------------------------------------

_aphotic_plugin_in_list "keybind" "$APHOTIC_PLUGIN_HOSTED_CAPABILITIES" \
    || fail "this build hosts the keybind capability but the gate does not say so"
for cap in ui-surface profile cli chat-provider action; do
    _aphotic_plugin_in_list "$cap" "$APHOTIC_PLUGIN_HOSTED_CAPABILITIES" \
        || fail "adding keybind dropped '$cap' from the hosted list"
done

# A keybind-only plugin is a working plugin: the verdict must not call it
# inert just because it draws nothing.
[[ "$(_aphotic_plugin_host_verdict "keybind" "")" == "ok" ]] \
    || fail "a keybind-only plugin should count as hosted"

# --- the QML that binds it ---------------------------------------------
#
# Bound at runtime rather than in keybinds.lua: the combo belongs to a
# plugin that may not be installed, and Hyprland outlives the shell.

KEYBIND="$SERVICES/PluginKeybind.qml"
KEYBINDS="$SERVICES/PluginKeybinds.qml"
CORE="$SERVICES/PluginKeybindCore.js"
QMLDIR="$SERVICES/qmldir"

[[ -f "$KEYBIND" ]] || fail "PluginKeybind worker is missing"
[[ -f "$KEYBINDS" ]] || fail "PluginKeybinds singleton is missing"
[[ -f "$CORE" ]] || fail "PluginKeybindCore is missing"

# The registry entry is the plugin's own combo and the action id the
# shell namespaces, so no core file names a plugin.
grep -qE 'keybindRegistrations' "$SERVICES/PluginRegistry.qml" || fail "PluginRegistry has no keybindRegistrations"
grep -qE 'PluginRegistry\.keybindRegistrations' "$KEYBINDS" || fail "PluginKeybinds does not read the registry"

# Two plugins on one combo are deduped on the combo the conflict check
# itself identifies, and only a bind that can actually be asserted claims
# one: an entry whose action does not resolve binds nothing.
grep -qE 'comboKey\(' "$SERVICES/PluginRegistry.qml" || fail "PluginRegistry dedupes on the raw combo string"
grep -qE 'Actions\.has\(' "$SERVICES/PluginRegistry.qml" || fail "PluginRegistry claims a combo for a bind that cannot happen"

# hyprctl keyword is refused under the Lua parser, and hl.bind is not
# available under the legacy one. Both paths have to exist, and the
# legacy combo is derived from the declared one rather than declared --
# the two lines themselves live in the core module, with the quoting
# every manifest value goes through.
grep -qE 'hl\.bind\(' "$CORE" || fail "PluginKeybind has no Lua-parser bind path"
grep -qE 'hl\.unbind\(' "$CORE" || fail "PluginKeybind no longer clears the Lua bind table"
grep -qE 'keyword bindd' "$KEYBIND" || fail "PluginKeybind has no legacy-parser bind path"
grep -qE 'keyword unbind' "$KEYBIND" || fail "PluginKeybind no longer clears the legacy bind table"
grep -qE 'sh", "-c"' "$KEYBIND" || fail "PluginKeybind does not assert through one shell"

# A manifest is third-party text crossing into a shell, so the combo is
# parsed once and refused when it has no legacy form, and every value the
# assert interpolates is quoted. Without this the manifest is shell syntax.
grep -qE 'KeybindCore\.parse\(' "$KEYBIND" || fail "PluginKeybind does not parse the combo"
grep -qE 'shellQuote\(' "$KEYBIND" || fail "PluginKeybind interpolates a manifest value unquoted"
grep -qE '_comboIssue' "$KEYBIND" || fail "PluginKeybind binds a combo it cannot represent"
grep -qE 'labelIssue\(' "$KEYBIND" || fail "PluginKeybind binds a description the bind line cannot carry"

# `wanted` and `Hypr.usingLua` settle independently, so the form has to
# be watched rather than read once.
grep -qE 'Hypr\.usingLua' "$KEYBIND" || fail "PluginKeybind does not pick a parser form"
grep -qE 'onDesiredFormChanged' "$KEYBIND" || fail "PluginKeybind does not re-sync when the parser resolves"

# A foreign bind on the combo wins. This is the one thing the plugin
# worker must not inherit from WorkspaceKeybind: its clear-then-assert
# would unbind whatever the user had there.
grep -qE 'hyprctl", "-j", "binds"' "$KEYBIND" || fail "PluginKeybind has no conflict check against the live bind table"
grep -qE 'Connections \{' "$KEYBIND" || fail "PluginKeybind does not re-check after a compositor reload"

# The IPC route the ticket names: the bind runs the same action the
# palette runs, and only while that action still resolves.
grep -qE 'ipc call aphotic action' "$KEYBINDS" || fail "PluginKeybinds does not route through the aphotic action IPC"
grep -qE 'Actions\.has\(' "$KEYBINDS" || fail "PluginKeybinds binds an action id without checking it resolves"

grep -qE 'singleton PluginKeybinds 1\.0 PluginKeybinds\.qml' "$QMLDIR" || fail "PluginKeybinds is not exported in qmldir"
grep -qE '^PluginKeybind 1\.0 PluginKeybind\.qml' "$QMLDIR" || fail "PluginKeybind is not exported in qmldir"

# A pragma Singleton nothing names is never constructed, so PluginKeybinds
# needs a construction site or the whole capability does nothing.
grep -qE '_residentSingletons:.*PluginKeybinds' "$QML/shell.qml" || fail "PluginKeybinds has no construction site"

echo "PASS: tests/test_plugin_keybind_capability.sh"
