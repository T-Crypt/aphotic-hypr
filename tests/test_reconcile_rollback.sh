#!/usr/bin/env bash
# tests/test_reconcile_rollback.sh
# aphotic reconcile converges the plugin registry to match aphotic.toml's
# [plugins] enabled list: enable/disable only, never installs a missing
# plugin (that stays a printed suggestion). --apply auto-snapshots first
# so aphotic rollback (a thin wrapper over aphotic backup revert) can
# undo it.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$ROOT/Configs/.local/lib/aphotic"
COMMANDS_DIR="$LIB_DIR/commands"
TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export XDG_DATA_HOME="$TESTHOME/.local/share"

DOTS="$TESTHOME/dots"
mkdir -p "$DOTS"
cat > "$DOTS/aphotic.toml" <<'EOF'
[plugins]
enabled = ["foo", "bar"]
EOF
export APHOTIC_DOTS_DIR="$DOTS"

source "$LIB_DIR/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_reconcile.sh"
source "$COMMANDS_DIR/cmd_rollback.sh"

install_plugin() {
    mkdir -p "$APHOTIC_PLUGINS_DIR/$1"
    : > "$APHOTIC_PLUGINS_DIR/$1/plugin.toml"
}

# foo: desired, installed, enabled -- nothing to do.
# bar: desired, installed, disabled -- reconcile should enable it.
# baz: not desired, installed, enabled -- reconcile should disable it.
# nope: desired, never installed -- reconcile must never try to install it.
install_plugin foo
install_plugin bar
install_plugin baz
echo '{"disabled": ["bar"]}' > "$APHOTIC_PLUGINS_STATE_FILE"
cat > "$DOTS/aphotic.toml" <<'EOF'
[plugins]
enabled = ["foo", "bar", "nope"]
EOF

# --- dry run: reports the plan, touches nothing ---

out="$(aphotic_cmd_reconcile)"
[[ "$out" == *"enable   bar"* ]] || fail "expected dry run to plan enabling bar, got: $out"
[[ "$out" == *"disable  baz"* ]] || fail "expected dry run to plan disabling baz, got: $out"
[[ "$out" == *"aphotic plugin install nope"* ]] || fail "expected dry run to suggest installing nope manually, got: $out"
aphotic_plugin_is_enabled bar && fail "expected dry run not to have touched bar"

json="$(aphotic_cmd_reconcile --json)"
[[ "$(jq -c '.toEnable' <<<"$json")" == '["bar"]' ]] || fail "expected --json toEnable=[bar], got: $json"
[[ "$(jq -c '.toDisable' <<<"$json")" == '["baz"]' ]] || fail "expected --json toDisable=[baz], got: $json"
[[ "$(jq -c '.missing' <<<"$json")" == '["nope"]' ]] || fail "expected --json missing=[nope], got: $json"

# --- --apply: converges enable/disable, snapshots first, never installs nope ---

aphotic_cmd_reconcile --apply >/dev/null

aphotic_plugin_is_enabled bar || fail "expected --apply to enable bar"
aphotic_plugin_is_enabled baz && fail "expected --apply to disable baz"
[[ -d "${APHOTIC_PLUGINS_DIR}/nope" ]] && fail "expected --apply to never install nope"

[[ -f "${APHOTIC_PLUGINS_STATE_FILE}" ]] || fail "expected a plugins state file to exist after apply"
snapshot_count="$(find "$APHOTIC_BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -name '*-pre-reconcile' 2>/dev/null | wc -l)"
[[ "$snapshot_count" -eq 1 ]] || fail "expected exactly one pre-reconcile snapshot, found $snapshot_count"

# --- rollback restores the pre-apply state ---

aphotic_cmd_rollback --yes >/dev/null

aphotic_plugin_is_enabled bar && fail "expected rollback to restore bar to disabled"
aphotic_plugin_is_enabled baz || fail "expected rollback to restore baz to enabled"

# --- no [plugins] section: reconcile has nothing to do, doesn't error ---

rm "$DOTS/aphotic.toml"
out="$(aphotic_cmd_reconcile)"
[[ "$out" == *"nothing declared"* ]] || fail "expected reconcile to report nothing declared with no [plugins] section, got: $out"

echo "ok: test_reconcile_rollback"
