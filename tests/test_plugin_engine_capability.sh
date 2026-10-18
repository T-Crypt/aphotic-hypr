#!/usr/bin/env bash
# tests/test_plugin_engine_capability.sh
# Manifest v3's `engine` capability: a plugin declares one engine the shell
# serves through a descriptor-driven adapter instead of per-engine core
# code. Covers the manifest parse, the registry round-trip, drift, the
# validate rules, the host gate, and the flat reader's one-engine cap.
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

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-engine"
mkdir -p "$PLUGDIR"
cat > "$PLUGDIR/plugin.toml" <<'TOML'
[plugin]
name = "scratch-engine"
display_name = "Scratch Engine"
description = "test engine plugin"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]

[engine]
id = "vega"
label = "Vega"
protocol = "engine-report"
host_key = "vegaHost"
default_host = "http://127.0.0.1:9911"
endpoint = "/.aphotic/engine.json"
process = "vega-server"
port_flag = "--port"
manages = ["vega-server"]
capabilities = ["models", "claims", "start", "stop"]

[engine.control]
start = "run /usr/bin/vega serve"
stop = "run /usr/bin/vega stop"

[engine.stats]
endpoint = "/slots"
interval = 1000

[engine.progress]
protocol = "engine-progress-report"
file = "~/.config/aphotic/plugins/scratch-engine/progress.json"
stale_after = 15000
rate_unit = "steps/s"
TOML

engine="$(_aphotic_plugin_engine_json "$PLUGDIR/plugin.toml")"
[[ "$(jq -r '.id' <<<"$engine")" == "vega" ]]                    || fail "id not parsed: $engine"
[[ "$(jq -r '.label' <<<"$engine")" == "Vega" ]]                  || fail "label not parsed: $engine"
[[ "$(jq -r '.protocol' <<<"$engine")" == "engine-report" ]]      || fail "protocol not parsed: $engine"
[[ "$(jq -r '.host_key' <<<"$engine")" == "vegaHost" ]]           || fail "host_key not parsed: $engine"
[[ "$(jq -r '.default_host' <<<"$engine")" == "http://127.0.0.1:9911" ]] || fail "default_host not parsed: $engine"
[[ "$(jq -r '.endpoint' <<<"$engine")" == "/.aphotic/engine.json" ]] || fail "endpoint not parsed: $engine"
[[ "$(jq -r '.process' <<<"$engine")" == "vega-server" ]]         || fail "process not parsed: $engine"
[[ "$(jq -r '.manages | join(",")' <<<"$engine")" == "vega-server" ]] || fail "manages not parsed: $engine"
[[ "$(jq -r '.capabilities | join(",")' <<<"$engine")" == "models,claims,start,stop" ]] || fail "capabilities not parsed: $engine"
[[ "$(jq -r '.control.start' <<<"$engine")" == "run /usr/bin/vega serve" ]] || fail "control.start not parsed: $engine"
[[ "$(jq -r '.stats.endpoint' <<<"$engine")" == "/slots" ]]       || fail "stats.endpoint not parsed: $engine"
[[ "$(jq -r '.stats.interval' <<<"$engine")" == "1000" ]]         || fail "stats.interval not parsed: $engine"
[[ "$(jq -r '.progress.protocol' <<<"$engine")" == "engine-progress-report" ]] || fail "progress.protocol not parsed: $engine"
[[ "$(jq -r '.progress.stale_after' <<<"$engine")" == "15000" ]]  || fail "progress.stale_after not parsed: $engine"

# A manifest with no [engine] section reads as null, the same absent
# shape chat_provider and keybinds write -- the drift comparison fills
# exactly that value in for an entry stored before this field existed.
printf '[plugin]\nname = "x"\n' > "$TESTHOME/none.toml"
[[ "$(_aphotic_plugin_engine_json "$TESTHOME/none.toml")" == "null" ]] \
    || fail "a manifest with no [engine] should read as null"

# An unset interval, manages and control read as empty, not an error: the
# shell's own parser fills the defaults.
printf '[plugin]\nname = "x"\n\n[engine]\nid = "y"\nprotocol = "engine-report"\nendpoint = "/x"\ndefault_host = "http://h"\n' > "$TESTHOME/bare.toml"
bare="$(_aphotic_plugin_engine_json "$TESTHOME/bare.toml")"
[[ "$(jq -r '.stats' <<<"$bare")" == "null" ]]                     || fail "an absent [engine.stats] should read null, not an empty object: $bare"
[[ "$(jq -r '.progress' <<<"$bare")" == "null" ]]                  || fail "an absent [engine.progress] should read null: $bare"
[[ "$(jq -r '.manages | length' <<<"$bare")" == "0" ]]             || fail "an unset manages should read empty: $bare"
[[ "$(jq -r '.control.start' <<<"$bare")" == "" ]]                 || fail "an unset control verb should read empty: $bare"

# --- registry round-trip: what the shell actually reads ----------------

_aphotic_plugin_registry_sync scratch-engine || fail "registry sync failed"
entry="$(jq -c '.installed["scratch-engine"].engine' "$APHOTIC_PLUGINS_STATE_FILE")"
[[ "$(jq -r '.id' <<<"$entry")" == "vega" ]]                       || fail "registry did not record the engine: $entry"
[[ "$(jq -r '.capabilities | join(",")' <<<"$entry")" == "models,claims,start,stop" ]] \
    || fail "registry lost the engine capabilities: $entry"

# --- drift -------------------------------------------------------------

[[ "$(_aphotic_plugin_describe scratch-engine | jq -r '.drifted')" == "false" ]] \
    || fail "a freshly synced plugin should not report drift"

sed -i 's/^label = "Vega"/label = "Vega (local)"/' "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-engine | jq -r '.drifted')" == "true" ]] \
    || fail "editing [engine] in place should report drift"
sed -i 's/^label = "Vega (local)"/label = "Vega"/' "$PLUGDIR/plugin.toml"
[[ "$(_aphotic_plugin_describe scratch-engine | jq -r '.drifted')" == "false" ]] \
    || fail "restoring the manifest should clear drift again"

# An entry stored before the engine key existed must not read as drifted
# in the other direction: a plugin that declares no engine, whose stored
# entry also has none, stays clean. A null-fill that wrote {} instead of
# null would flag every engine-less plugin on upgrade.
BARE="$APHOTIC_PLUGINS_DIR/scratch-noengine"
mkdir -p "$BARE"
cat > "$BARE/plugin.toml" <<'TOML'
[plugin]
name = "scratch-noengine"
display_name = "Bare"
description = "no engine here"
version = "1.0.0"
category = "ai"
capabilities = ["cli"]
TOML
_aphotic_plugin_registry_sync scratch-noengine || fail "registry sync failed for the bare plugin"
[[ "$(jq -c '.installed["scratch-noengine"].engine' "$APHOTIC_PLUGINS_STATE_FILE")" == "null" ]] \
    || fail "a manifest with no engine should sync as null"
[[ "$(_aphotic_plugin_describe scratch-noengine | jq -r '.drifted')" == "false" ]] \
    || fail "a plugin with no engine should not drift on the new field"

# --- validate ----------------------------------------------------------

valid_manifest() {
    mkdir -p "$TESTHOME/$1"
    cat > "$TESTHOME/$1/plugin.toml"
}

valid_manifest eng-ok <<'TOML'
[plugin]
name = "eng-ok"
display_name = "Ok"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
id = "vega"
protocol = "engine-report"
endpoint = "/x"
default_host = "http://h"
capabilities = ["models", "claims", "start"]
[engine.control]
start = "run /usr/bin/vega serve"
TOML
_aphotic_plugin_validate "$TESTHOME/eng-ok" >/dev/null 2>&1 \
    || fail "a well-formed engine manifest should validate"
out="$(_aphotic_plugin_validate "$TESTHOME/eng-ok" 2>&1)"
grep -q "isn't one this build recognizes" <<<"$out" \
    && fail "validate called the engine capability unrecognized: $out"

# [engine] present, capability missing: an error, the section would install
# to nothing.
valid_manifest eng-untagged <<'TOML'
[plugin]
name = "eng-untagged"
display_name = "Untagged"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["cli"]
[engine]
id = "vega"
protocol = "engine-report"
endpoint = "/x"
default_host = "http://h"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-untagged" 2>&1)" && fail "an [engine] without the capability should fail validate"
grep -q "capabilities doesn't include 'engine'" <<<"$out" \
    || fail "validate did not name the missing capability: $out"

# The other direction is a warning: a plugin can declare the capability
# ahead of the section.
valid_manifest eng-empty <<'TOML'
[plugin]
name = "eng-empty"
display_name = "Empty"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-empty" 2>&1)" \
    || fail "an engine capability with no section should warn, not fail: $out"
grep -q "no \[engine\] section declares one" <<<"$out" \
    || fail "validate did not warn about the missing section: $out"

# A second engine is warned about: the flat reader serves one.
valid_manifest eng-second <<'TOML'
[plugin]
name = "eng-second"
display_name = "Second"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
id = "vega"
protocol = "engine-report"
endpoint = "/x"
default_host = "http://h"
[engine_2]
id = "other"
protocol = "engine-report"
endpoint = "/y"
default_host = "http://h"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-second" 2>&1)" || fail "a second engine should warn, not fail: $out"
grep -q "\[engine_2\] ignored, one engine per plugin" <<<"$out" \
    || fail "validate did not warn about the second engine: $out"

valid_manifest eng-noid <<'TOML'
[plugin]
name = "eng-noid"
display_name = "No Id"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
protocol = "engine-report"
endpoint = "/x"
default_host = "http://h"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-noid" 2>&1)" && fail "a missing [engine].id should fail validate"
grep -q "\[engine\].id missing" <<<"$out" || fail "validate did not name the missing id: $out"

valid_manifest eng-noproto <<'TOML'
[plugin]
name = "eng-noproto"
display_name = "No Protocol"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
id = "vega"
endpoint = "/x"
default_host = "http://h"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-noproto" 2>&1)" && fail "a missing [engine].protocol should fail validate"
grep -q "\[engine\].protocol missing" <<<"$out" || fail "validate did not name the missing protocol: $out"

valid_manifest eng-badproto <<'TOML'
[plugin]
name = "eng-badproto"
display_name = "Bad Protocol"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
id = "vega"
protocol = "comfyui-ws"
endpoint = "/x"
default_host = "http://h"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-badproto" 2>&1)" && fail "an unknown protocol should fail validate"
grep -q "protocol 'comfyui-ws' is not one this Aphotic speaks" <<<"$out" \
    || fail "validate did not name the protocol: $out"

# A capability token with nothing behind it asks the shell to do something
# the descriptor cannot, so it is a failure.
valid_manifest eng-unbacked <<'TOML'
[plugin]
name = "eng-unbacked"
display_name = "Unbacked"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
id = "vega"
protocol = "engine-report"
endpoint = "/x"
default_host = "http://h"
capabilities = ["models", "unload"]
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-unbacked" 2>&1)" && fail "an unbacked engine capability should fail validate"
grep -q "names 'unload', but the descriptor provides nothing for it" <<<"$out" \
    || fail "validate did not name the unbacked token: $out"

# A verb is either documented form; anything else is refused.
valid_manifest eng-badverb <<'TOML'
[plugin]
name = "eng-badverb"
display_name = "Bad Verb"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
id = "vega"
protocol = "engine-report"
endpoint = "/x"
default_host = "http://h"
[engine.control]
start = "curl /x"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-badverb" 2>&1)" && fail "an ill-formed verb should fail validate"
grep -q "\[engine.control\].start is neither 'http <METHOD> <path>' nor 'run <command>'" <<<"$out" \
    || fail "validate did not name the verb form: $out"

# {model} in start or stop has no model in scope.
valid_manifest eng-model <<'TOML'
[plugin]
name = "eng-model"
display_name = "Model"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
id = "vega"
protocol = "engine-report"
endpoint = "/x"
default_host = "http://h"
[engine.control]
stop = "http POST /stop/{model}"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-model" 2>&1)" && fail "a {model} in stop should fail validate"
grep -q "uses {model} where no model is in scope" <<<"$out" \
    || fail "validate did not name the model placeholder: $out"

# A verb is a command line, so shell syntax is refused rather than run.
# validate never executes the verb, which is the point.
MARKER=/tmp/aphotic-test-engine-injected
rm -f "$MARKER"
valid_manifest eng-inject <<TOML
[plugin]
name = "eng-inject"
display_name = "Inject"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
id = "vega"
protocol = "engine-report"
endpoint = "/x"
default_host = "http://h"
[engine.control]
start = "run /usr/bin/vega serve; touch $MARKER"
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-inject" 2>&1)" && fail "a verb carrying shell syntax should fail validate"
grep -q "carries shell syntax" <<<"$out" || fail "validate did not name the shell syntax: $out"
[[ -e "$MARKER" ]] && fail "validate ran the engine verb"

# An engine capability token this build does not know is a warning, the
# same fail-open direction the plugin capability list takes.
valid_manifest eng-token <<'TOML'
[plugin]
name = "eng-token"
display_name = "Token"
description = "d"
version = "1.0.0"
category = "ai"
capabilities = ["engine"]
[engine]
id = "vega"
protocol = "engine-report"
endpoint = "/x"
default_host = "http://h"
capabilities = ["models", "warp-drive"]
TOML
out="$(_aphotic_plugin_validate "$TESTHOME/eng-token" 2>&1)" || fail "an unknown engine token should warn, not fail: $out"
grep -q "capabilities names 'warp-drive', which isn't a token this Aphotic speaks" <<<"$out" \
    || fail "validate did not warn about the unknown token: $out"

# --- host gate ---------------------------------------------------------

_aphotic_plugin_in_list "engine" "$APHOTIC_PLUGIN_HOSTED_CAPABILITIES" \
    || fail "this build hosts the engine capability but the gate does not say so"
for cap in ui-surface profile cli chat-provider action keybind; do
    _aphotic_plugin_in_list "$cap" "$APHOTIC_PLUGIN_HOSTED_CAPABILITIES" \
        || fail "adding engine dropped '$cap' from the hosted list"
done

# An engine-only plugin is a working plugin: it draws nothing, but the
# shell mounts an adapter for it, so the verdict must not call it inert.
[[ "$(_aphotic_plugin_host_verdict "engine" "")" == "ok" ]] \
    || fail "an engine-only plugin should count as hosted"

echo "PASS: tests/test_plugin_engine_capability.sh"
