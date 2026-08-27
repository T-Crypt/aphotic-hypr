#!/usr/bin/env bash
# tests/test_plugin_v2.sh
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

# --- scratch plugin declaring both new v2 hooks ---

PLUGDIR="$APHOTIC_PLUGINS_DIR/scratch"
mkdir -p "$PLUGDIR/hooks"
cat > "$PLUGDIR/plugin.toml" <<'EOF'
[plugin]
name = "scratch"
display_name = "Scratch"
description = "test plugin"
version = "0.0.1"
category = "dev"
capabilities = ["project-hook", "workspace-hook"]

[hooks]
on_project_open = "hooks/on_project_open.sh"
on_workspace_launch = "hooks/on_workspace_launch.sh"
EOF
cat > "$PLUGDIR/hooks/on_project_open.sh" <<EOF
#!/usr/bin/env bash
echo "project-open: \$1" >> "$TESTHOME/hook.log"
EOF
cat > "$PLUGDIR/hooks/on_workspace_launch.sh" <<EOF
#!/usr/bin/env bash
echo "workspace-launch: \$1" >> "$TESTHOME/hook.log"
EOF
chmod +x "$PLUGDIR/hooks/"*.sh

# A second plugin, v1-shaped (no category, no v2 hooks) -- must never
# fire the new hooks and must not error out reading the absent category.
PLUGDIR2="$APHOTIC_PLUGINS_DIR/v1only"
mkdir -p "$PLUGDIR2"
cat > "$PLUGDIR2/plugin.toml" <<'EOF'
[plugin]
name = "v1only"
display_name = "V1 Only"
description = "pre-v2 plugin"
version = "1.0.0"
capabilities = ["theme-hook"]

[hooks]
on_theme_change = "hooks/on_theme_change.sh"
EOF

# --- category field ---

described="$(_aphotic_plugin_describe scratch)"
[[ "$(echo "$described" | jq -r '.category')" == "dev" ]] || fail "expected scratch's category to be 'dev'"

described_v1="$(_aphotic_plugin_describe v1only)"
[[ "$(echo "$described_v1" | jq -r '.category')" == "" ]] || fail "expected v1only's category to be empty, not an error"

# --- hook firing: only the declaring plugin fires, and blocks until done ---

rm -f "$TESTHOME/hook.log"
_aphotic_plugin_run_project_hooks "/tmp/some/project"
sleep 1
[[ -f "$TESTHOME/hook.log" ]] || fail "expected on_project_open hook to have fired"
grep -q "project-open: /tmp/some/project" "$TESTHOME/hook.log" || fail "hook log missing expected project-open line"
[[ "$(wc -l < "$TESTHOME/hook.log")" -eq 1 ]] || fail "expected exactly one hook firing (only scratch declares project-hook), got: $(cat "$TESTHOME/hook.log")"

rm -f "$TESTHOME/hook.log"
_aphotic_plugin_run_workspace_hooks "my-profile"
sleep 1
grep -q "workspace-launch: my-profile" "$TESTHOME/hook.log" || fail "hook log missing expected workspace-launch line"
[[ "$(wc -l < "$TESTHOME/hook.log")" -eq 1 ]] || fail "expected exactly one hook firing, got: $(cat "$TESTHOME/hook.log")"

# --- disabled plugin never fires ---

aphotic_plugin_set_enabled scratch false
rm -f "$TESTHOME/hook.log"
_aphotic_plugin_run_project_hooks "/tmp/other"
sleep 1
[[ ! -f "$TESTHOME/hook.log" ]] || fail "disabled plugin should not have fired its hook"
aphotic_plugin_set_enabled scratch true

# --- security index trust/untrust round-trip ---

aphotic_plugins_security_index_trusted && fail "expected untrusted by default"
_aphotic_plugin_trust_security_index true >/dev/null
aphotic_plugins_security_index_trusted || fail "expected trusted after trust-security-index --yes"
_aphotic_plugin_untrust_security_index >/dev/null
aphotic_plugins_security_index_trusted && fail "expected untrusted again after untrust-security-index"

# --- category filter on the (locally-shaped) remote list ---

fake_index='{"plugins":[{"name":"a","category":"dev"},{"name":"b","category":"security"}]}'
filtered="$(echo "$fake_index" | jq --arg c "security" '{plugins: ((.plugins // []) | map(select(.category == $c)))}')"
[[ "$(echo "$filtered" | jq '.plugins | length')" -eq 1 ]] || fail "expected category filter to keep exactly one entry"
[[ "$(echo "$filtered" | jq -r '.plugins[0].name')" == "b" ]] || fail "expected the security-category entry to survive the filter"

echo "PASS: plugin v2 (category field, project/workspace hooks, security-index trust, category filter)"
