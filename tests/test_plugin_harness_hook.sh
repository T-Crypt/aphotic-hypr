#!/usr/bin/env bash
# tests/test_plugin_harness_hook.sh
# Manifest v3 addition: the "harness-hook" capability (Claude Code/Codex/
# OpenCode agent-hook wiring, ported off `main` as plugins per direct
# maintainer instruction). Unlike theme/project/workspace hooks, wiring
# happens in an *external* program's own config file, which has no idea
# about Aphotic's `disabled` array -- so enable/disable have to actively
# re-wire/unwire, not just gate a symlink the way ui-surface does. See
# docs/archive/PLUGIN_SYSTEM.md "harness-hook capability".
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
export LIB_DIR="$ROOT/Configs/.local/lib/aphotic"

COMMANDS_DIR="$LIB_DIR/commands"
source "$LIB_DIR/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_plugin.sh"

# --- scratch harness-hook plugin ---

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch-harness"
mkdir -p "$PLUGDIR/hooks"
cat > "$PLUGDIR/plugin.toml" <<'EOF'
[plugin]
name = "scratch-harness"
display_name = "Scratch Harness Hook"
description = "test harness-hook plugin"
version = "1.0.0"
category = "ai"
capabilities = ["harness-hook"]

[owns]
external_config = ["~/.scratch-harness/hooks.json (SessionStart entry)"]

[harness]
wire = "hooks/wire.sh"
unwire = "hooks/unwire.sh"
EOF

MARKER="$TESTHOME/wire-calls.log"
cat > "$PLUGDIR/hooks/wire.sh" <<EOF
#!/usr/bin/env bash
echo "wire:\$1" >> "$MARKER"
EOF
cat > "$PLUGDIR/hooks/unwire.sh" <<EOF
#!/usr/bin/env bash
echo "unwire:\$1" >> "$MARKER"
EOF
chmod +x "$PLUGDIR/hooks/wire.sh" "$PLUGDIR/hooks/unwire.sh"

# --- describe: owns.external_config surfaces, same shape as config_keys ---

described="$(_aphotic_plugin_describe scratch-harness)"
[[ "$(echo "$described" | jq -r '.owns.external_config | length')" -eq 1 ]] || fail "expected 1 owned external_config entry"
[[ "$(echo "$described" | jq -r '.owns.external_config[0]')" == "~/.scratch-harness/hooks.json (SessionStart entry)" ]] || fail "expected external_config entry to round-trip verbatim"

# --- a v1/v3-ui-surface-shaped plugin with no [owns] at all still
# describes cleanly (external_config defaults to [], not an error) ---

PLUGDIR_V1="$APHOTIC_PLUGINS_DIR/v1only"
mkdir -p "$PLUGDIR_V1"
cat > "$PLUGDIR_V1/plugin.toml" <<'EOF'
[plugin]
name = "v1only"
display_name = "V1 Only"
description = "pre-v3 plugin"
version = "1.0.0"
capabilities = ["theme-hook"]
EOF
described_v1="$(_aphotic_plugin_describe v1only)"
[[ "$(echo "$described_v1" | jq -r '.owns.external_config | length')" -eq 0 ]] || fail "expected v1only's external_config to be empty"

# --- wire/unwire lifecycle: install wires, enable re-wires, disable
# unwires, remove unwires (called before the plugin dir is deleted, so
# its own unwire.sh is still there to run) ---

[[ -f "$MARKER" ]] && fail "wire/unwire must not run before any lifecycle call"

_aphotic_plugin_wire_harness scratch-harness
[[ "$(cat "$MARKER")" == "wire:${LIB_DIR}" ]] || fail "expected wire.sh to be called once with LIB_DIR, got: $(cat "$MARKER")"

_aphotic_plugin_unwire_harness scratch-harness
[[ "$(sed -n '2p' "$MARKER")" == "unwire:${LIB_DIR}" ]] || fail "expected unwire.sh to be called with LIB_DIR"

rm -f "$MARKER"

# Full install()/remove() round trip against a local repo checkout --
# exercises the real dispatch, not just the two helpers above.
export APHOTIC_PLUGINS_REPO="$TESTHOME/fake-repo"
mkdir -p "$APHOTIC_PLUGINS_REPO/scratch-harness2/hooks"
cp "$PLUGDIR/plugin.toml" "$APHOTIC_PLUGINS_REPO/scratch-harness2/plugin.toml"
sed -i 's/name = "scratch-harness"/name = "scratch-harness2"/' "$APHOTIC_PLUGINS_REPO/scratch-harness2/plugin.toml"
cp "$PLUGDIR/hooks/wire.sh" "$PLUGDIR/hooks/unwire.sh" "$APHOTIC_PLUGINS_REPO/scratch-harness2/hooks/"
git -C "$APHOTIC_PLUGINS_REPO" init -q 2>/dev/null || true

_aphotic_plugin_install scratch-harness2 false >/dev/null
[[ "$(cat "$MARKER")" == "wire:${LIB_DIR}" ]] || fail "expected install() to have wired scratch-harness2"

rm -f "$MARKER"
aphotic_cmd_plugin enable scratch-harness2 >/dev/null
[[ "$(cat "$MARKER")" == "wire:${LIB_DIR}" ]] || fail "expected enable to re-wire scratch-harness2"

rm -f "$MARKER"
aphotic_cmd_plugin disable scratch-harness2 >/dev/null
[[ "$(cat "$MARKER")" == "unwire:${LIB_DIR}" ]] || fail "expected disable to unwire scratch-harness2"
aphotic_plugin_set_enabled scratch-harness2 true # leave enabled for remove's own wire/unwire call below

rm -f "$MARKER"
_aphotic_plugin_remove scratch-harness2 >/dev/null
[[ "$(cat "$MARKER")" == "unwire:${LIB_DIR}" ]] || fail "expected remove() to unwire scratch-harness2 before deleting its directory"
[[ -d "$(_aphotic_plugin_dir scratch-harness2)" ]] && fail "expected scratch-harness2's install dir to be gone after remove()"

# --- a plugin with a [harness] table but NOT the harness-hook capability
# is a no-op -- capability gates the lifecycle, not just the table's
# presence, same rule project-hook/workspace-hook already use ---

PLUGDIR_NOCAP="$APHOTIC_PLUGINS_DIR/scratch-nocap"
mkdir -p "$PLUGDIR_NOCAP/hooks"
cat > "$PLUGDIR_NOCAP/plugin.toml" <<'EOF'
[plugin]
name = "scratch-nocap"
display_name = "Scratch No Capability"
description = "declares [harness] but not the harness-hook capability"
version = "1.0.0"
capabilities = ["theme-hook"]

[harness]
wire = "hooks/wire.sh"
unwire = "hooks/unwire.sh"
EOF
cp "$PLUGDIR/hooks/wire.sh" "$PLUGDIR/hooks/unwire.sh" "$PLUGDIR_NOCAP/hooks/"

rm -f "$MARKER"
_aphotic_plugin_wire_harness scratch-nocap
[[ -f "$MARKER" ]] && fail "expected wire.sh NOT to run for a plugin missing the harness-hook capability"

echo "PASS: harness-hook capability (owns.external_config, wire/unwire lifecycle on install/enable/disable/remove, capability gating)"
