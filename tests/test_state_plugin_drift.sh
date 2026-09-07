#!/usr/bin/env bash
# tests/test_state_plugin_drift.sh
# lib/aphotic/state.sh compares aphotic.toml's optional [plugins] enabled
# list (desired) against the plugin registry (actual) for `aphotic diff`/
# `status`/`reconcile` to share. An absent [plugins] section must mean
# "drift tracking opted out", never "desired: nothing" -- an install that
# has never declared the section should report no drift at all, not flag
# every installed plugin as unwanted.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export XDG_DATA_HOME="$TESTHOME/.local/share"

DOTS="$TESTHOME/dots"
mkdir -p "$DOTS"
export APHOTIC_DOTS_DIR="$DOTS"

source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"
source "$ROOT/Configs/.local/lib/aphotic/state.sh"

install_plugin() {
    mkdir -p "$APHOTIC_PLUGINS_DIR/$1"
    : > "$APHOTIC_PLUGINS_DIR/$1/plugin.toml"
}

# --- no [plugins] section: opted out, no drift reported ---

install_plugin "baz"
[[ -z "$(_aphotic_state_plugin_drift)" ]] || fail "expected no drift with no [plugins] section declared"
_aphotic_state_plugins_declared && fail "expected _aphotic_state_plugins_declared to be false with no section"

# --- [plugins] declared: foo desired+installed (ok), bar desired but
#     missing, baz installed+enabled but not desired (extra), qux
#     installed but disabled and not desired (silent -- neither side),
#     quux desired, installed, but disabled (needs `enable`, not
#     `install` -- install refuses on an already-installed plugin) ---

cat > "$DOTS/aphotic.toml" <<'EOF'
[plugins]
enabled = ["foo", "bar", "quux"]
EOF

install_plugin "foo"
install_plugin "qux"
install_plugin "quux"
echo '{"disabled": ["qux", "quux"]}' > "$APHOTIC_PLUGINS_STATE_FILE"

_aphotic_state_plugins_declared || fail "expected _aphotic_state_plugins_declared to be true once [plugins] exists"

drift="$(_aphotic_state_plugin_drift)"
grep -qxF $'foo\tok' <<<"$drift" || fail "expected foo to report ok, got: $drift"
grep -qxF $'bar\tmissing' <<<"$drift" || fail "expected bar to report missing, got: $drift"
grep -qxF $'baz\textra' <<<"$drift" || fail "expected baz to report extra, got: $drift"
grep -qxF $'quux\tdisabled' <<<"$drift" || fail "expected desired+installed+disabled quux to report disabled, got: $drift"
grep -q "^qux" <<<"$drift" && fail "expected disabled+undesired qux to be silent, got: $drift"

echo "ok: test_state_plugin_drift"
