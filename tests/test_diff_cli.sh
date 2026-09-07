#!/usr/bin/env bash
# tests/test_diff_cli.sh
# `aphotic diff` aggregates lib/aphotic/state.sh's plugin/service/version
# drift plus cmd_sync.sh's existing missing-packages check into one
# report, both human and --json. Exercises the aggregation and the
# "N changes required" count against fabricated plugin/git/service state
# -- not `_aphotic_sync_missing_packages` itself, which this reuses as-is.
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
git -C "$DOTS" init -q -b main
git -C "$DOTS" config user.email test@test.local
git -C "$DOTS" config user.name test
echo "9.9.9" > "$DOTS/VERSION"
git -C "$DOTS" add VERSION
git -C "$DOTS" commit -q -m init
export APHOTIC_DOTS_DIR="$DOTS"

# Stub systemctl/pgrep so daemon+display-manager read as clean and
# deterministic, same shape as test_config_sync_orphan_kill.sh's stubs.
mkdir -p "$TESTHOME/bin"
export PATH="$TESTHOME/bin:$PATH"
cat > "$TESTHOME/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo disabled
exit 1
EOF
chmod +x "$TESTHOME/bin/systemctl"
cat > "$TESTHOME/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TESTHOME/bin/pgrep"

source "$LIB_DIR/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_diff.sh"

# --- nothing declared, daemon not running: exactly one required change ---

out="$(aphotic_cmd_diff)"
[[ "$out" == *"1 change(s) required"* ]] || fail "expected exactly 1 change with nothing else drifted, got: $out"
[[ "$out" == *"not declared in aphotic.toml"* ]] || fail "expected plugins to report undeclared, got: $out"

json="$(aphotic_cmd_diff --json)"
[[ "$(jq -r '.changesRequired' <<<"$json")" == "1" ]] || fail "expected --json changesRequired=1, got: $json"
[[ "$(jq -r '.plugins.declared' <<<"$json")" == "false" ]] || fail "expected --json plugins.declared=false, got: $json"

# --- [plugins] declared: one ok, one missing, one extra ---

cat > "$DOTS/aphotic.toml" <<'EOF'
[plugins]
enabled = ["foo", "bar"]
EOF
mkdir -p "$APHOTIC_PLUGINS_DIR/foo" "$APHOTIC_PLUGINS_DIR/baz"
: > "$APHOTIC_PLUGINS_DIR/foo/plugin.toml"
: > "$APHOTIC_PLUGINS_DIR/baz/plugin.toml"

out="$(aphotic_cmd_diff)"
[[ "$out" == *"bar missing"* ]] || fail "expected bar to report missing, got: $out"
[[ "$out" == *"baz not desired"* ]] || fail "expected baz to report not desired, got: $out"
[[ "$out" == *"3 change(s) required"* ]] || fail "expected 3 changes (bar missing, baz extra, daemon stopped), got: $out"

json="$(aphotic_cmd_diff --json)"
[[ "$(jq -r '.plugins.missing[0]' <<<"$json")" == "bar" ]] || fail "expected --json plugins.missing to include bar, got: $json"
[[ "$(jq -r '.plugins.extra[0]' <<<"$json")" == "baz" ]] || fail "expected --json plugins.extra to include baz, got: $json"

echo "ok: test_diff_cli"
