#!/usr/bin/env bash
# tests/test_status_cli.sh
# `aphotic status` is the one-screen read of profile/layers, plugin
# counts against aphotic.toml's [plugins], and version/service state --
# same lib/aphotic/state.sh helpers `aphotic diff` uses, summarized
# rather than itemized.
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
git -C "$DOTS" update-ref refs/remotes/origin/main "$(git -C "$DOTS" rev-parse HEAD)"
cat > "$DOTS/aphotic.toml" <<'EOF'
[install]
profile = "full"
layers = ["gaming", "ai"]

[plugins]
enabled = ["foo"]
EOF
export APHOTIC_DOTS_DIR="$DOTS"

source "$LIB_DIR/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_status.sh"

mkdir -p "$APHOTIC_PLUGINS_DIR/foo"
: > "$APHOTIC_PLUGINS_DIR/foo/plugin.toml"

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

out="$(aphotic_cmd_status)"
[[ "$out" == *"Profile: full"* ]] || fail "expected profile full, got: $out"
[[ "$out" == *"Layers:  gaming,ai"* ]] || fail "expected layers gaming,ai, got: $out"
[[ "$out" == *"1 ok, 0 missing, 0 extra"* ]] || fail "expected plugin counts 1/0/0, got: $out"
[[ "$out" == *"up to date with origin/main"* ]] || fail "expected up-to-date version drift, got: $out"

json="$(aphotic_cmd_status --json)"
[[ "$(jq -r '.profile' <<<"$json")" == "full" ]] || fail "expected --json profile=full, got: $json"
[[ "$(jq -c '.layers' <<<"$json")" == '["gaming","ai"]' ]] || fail "expected --json layers array, got: $json"
[[ "$(jq -r '.plugins.ok' <<<"$json")" == "1" ]] || fail "expected --json plugins.ok=1, got: $json"
[[ "$(jq -r '.versionDrift.status' <<<"$json")" == "ok" ]] || fail "expected --json versionDrift.status=ok, got: $json"

echo "ok: test_status_cli"
