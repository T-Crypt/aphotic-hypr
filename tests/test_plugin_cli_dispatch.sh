#!/usr/bin/env bash
# tests/test_plugin_cli_dispatch.sh
# C-15: a plugin contributes a CLI command, either top-level or as a
# subcommand of an existing core one, resolved by declaration so no core
# file names a plugin. See docs/PLUGIN_LAYER_MODEL.md.
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

APHOTIC="$ROOT/Configs/.local/bin/aphotic"

source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"

# --- a plugin extending an existing core command ----------------------

SUBPLUG="$APHOTIC_PLUGINS_DIR/scratch-sub"
mkdir -p "$SUBPLUG/cli"
cat > "$SUBPLUG/plugin.toml" <<'EOF'
[plugin]
name = "scratch-sub"
display_name = "Scratch Sub"
version = "1.0.0"
category = "ai"
capabilities = ["cli"]

[cli]
command = "ai"
subcommand = "scratchfit"
script = "cli/ai_scratchfit.sh"
summary = "scratch subcommand"
EOF
cat > "$SUBPLUG/cli/ai_scratchfit.sh" <<'EOF'
echo "SCRATCHFIT args=$*"
# Proves the sourced script gets core's helpers, not a bare environment.
declare -F aphotic_err >/dev/null && echo "SCRATCHFIT helpers=yes"
EOF

# --- a plugin owning a top-level command ------------------------------

TOPPLUG="$APHOTIC_PLUGINS_DIR/scratch-top"
mkdir -p "$TOPPLUG/cli"
cat > "$TOPPLUG/plugin.toml" <<'EOF'
[plugin]
name = "scratch-top"
display_name = "Scratch Top"
version = "1.0.0"
category = "ai"
capabilities = ["cli"]

[cli]
command = "scratchtop"
script = "cli/top.sh"
summary = "scratch top-level"
EOF
cat > "$TOPPLUG/cli/top.sh" <<'EOF'
echo "SCRATCHTOP args=$*"
EOF

# --- resolution -------------------------------------------------------

hit="$(aphotic_plugin_cli_resolve ai scratchfit)" \
    || fail "expected to resolve 'ai scratchfit'"
[[ "$hit" == "scratch-sub"$'\t'* ]] || fail "resolve should name the providing plugin, got '$hit'"

aphotic_plugin_cli_resolve ai nosuchthing >/dev/null 2>&1 \
    && fail "expected no resolution for an undeclared subcommand"

# A top-level command must not answer as a subcommand of the same name,
# nor the other way round -- the empty subcommand is part of the match.
aphotic_plugin_cli_resolve scratchtop "" >/dev/null \
    || fail "expected to resolve top-level 'scratchtop'"
aphotic_plugin_cli_resolve ai scratchtop >/dev/null 2>&1 \
    && fail "a top-level command must not resolve as an 'ai' subcommand"

# --- dispatch through the real CLI ------------------------------------

out="$("$APHOTIC" ai scratchfit 7 2>&1)" || fail "dispatch of 'ai scratchfit' failed: $out"
[[ "$out" == *"SCRATCHFIT args=7"* ]] || fail "subcommand did not receive its args: $out"
[[ "$out" == *"SCRATCHFIT helpers=yes"* ]] || fail "sourced command should see core helpers: $out"

out="$("$APHOTIC" scratchtop a b 2>&1)" || fail "dispatch of top-level failed: $out"
[[ "$out" == *"SCRATCHTOP args=a b"* ]] || fail "top-level command did not receive its args: $out"

# --- a disabled plugin contributes nothing ----------------------------

aphotic_plugin_set_enabled scratch-sub false
aphotic_plugin_cli_resolve ai scratchfit >/dev/null 2>&1 \
    && fail "a disabled plugin must not provide its command"
"$APHOTIC" ai scratchfit >/dev/null 2>&1 \
    && fail "expected 'ai scratchfit' to fail once its plugin is disabled"
aphotic_plugin_set_enabled scratch-sub true

# --- a failing plugin command is not reported as missing --------------
# The reason resolution happens before execution: otherwise a command that
# legitimately exits non-zero is indistinguishable from one that does not
# exist, and the user is told the wrong thing.

cat > "$SUBPLUG/cli/ai_scratchfit.sh" <<'EOF'
aphotic_err "the command itself failed"
return 3
EOF
set +e
out="$("$APHOTIC" ai scratchfit 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 3 ]] || fail "expected the plugin command's own exit status 3, got $rc"
[[ "$out" != *"unknown ai subcommand"* ]] || fail "a failing command must not be reported as unknown: $out"

# --- core wins a collision -------------------------------------------

COLLIDE="$APHOTIC_PLUGINS_DIR/scratch-collide"
mkdir -p "$COLLIDE/cli"
cat > "$COLLIDE/plugin.toml" <<'EOF'
[plugin]
name = "scratch-collide"
version = "1.0.0"
capabilities = ["cli"]

[cli]
command = "ai"
script = "cli/hijack.sh"
summary = "should never run"
EOF
echo 'echo "HIJACKED"' > "$COLLIDE/cli/hijack.sh"

out="$("$APHOTIC" ai --help 2>&1)" || true
[[ "$out" != *"HIJACKED"* ]] || fail "a plugin must not shadow a core command"
[[ "$out" == *"Usage: aphotic ai"* ]] || fail "core 'ai' help should still be what runs: $out"

# --- help and discovery list plugin commands --------------------------

[[ "$out" == *"scratchfit"* ]] || fail "core 'ai --help' should list plugin subcommands: $out"
[[ "$out" == *"scratch-sub"* ]] || fail "help should attribute the subcommand to its plugin: $out"

out="$("$APHOTIC" --help 2>&1)"
[[ "$out" == *"scratchtop"* ]] || fail "top-level help should list plugin commands: $out"
[[ "$out" == *"PLUGINS"* ]] || fail "top-level help should group plugin commands: $out"

out="$("$APHOTIC" -s 2>&1)"
[[ "$out" == *"scratchtop"* ]] || fail "'aphotic -s' should list plugin commands: $out"
[[ "$(grep -c '^ai$' <<<"$out")" -eq 1 ]] || fail "'aphotic -s' should not duplicate a name core also owns"

# --- core no longer carries the moved command -------------------------

grep -q "llmfit" "$ROOT/Configs/.local/lib/aphotic/commands/cmd_ai.sh" \
    && fail "cmd_ai.sh still references llmfit -- 'ai fit' should live in its plugin now"
grep -rqi "llm-fit" "$ROOT/Configs/.local/" \
    && fail "a core CLI file names a plugin id, which the layer model forbids"

echo "PASS: plugin CLI dispatch (resolution, subcommand + top-level, disabled, failure vs missing, collision, help/discovery, core cleanup)"
