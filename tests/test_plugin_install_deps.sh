#!/usr/bin/env bash
# tests/test_plugin_install_deps.sh
# _aphotic_plugin_install_deps: the AUR fallback, the [requires]
# install_script escape hatch, and the bash-5.3 `local` scoping
# regression that made the whole function a silent no-op.
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

# Fake AUR helper ahead of any real one -- this test must never invoke a
# real package manager.
mkdir -p "$TESTHOME/bin"
cat > "$TESTHOME/bin/yay" <<'EOF'
#!/bin/sh
echo "yay-called: $*"
EOF
chmod +x "$TESTHOME/bin/yay"
export PATH="$TESTHOME/bin:$PATH"

MISSING_BIN="aphotic-test-binary-that-does-not-exist"

new_plugin() {
    local dir="$APHOTIC_PLUGINS_DIR/$1"
    mkdir -p "$dir/hooks"
    {
        echo '[plugin]'
        echo "name = \"$1\""
        echo '[requires]'
        echo "binaries = [\"${MISSING_BIN}\"]"
        [[ -n "${2:-}" ]] && echo "install_script = \"$2\""
    } > "$dir/plugin.toml"
    printf '%s\n' "$dir"
}

# --- the bash 5.3 `local` regression -------------------------------------
# `local dest="$1" manifest="${dest}/plugin.toml"` resolved manifest to
# "/plugin.toml" on bash 5.3+, which never exists, so the function
# returned at its own guard and no dependency was ever installed. Assert
# it actually reaches its work now.

dir="$(new_plugin no-script)"
out="$(_aphotic_plugin_install_deps "$dir" 2>&1)"
[[ "$out" == *"yay-called: -S ${MISSING_BIN}"* ]] \
    || fail "AUR fallback did not run for a missing binary (got: ${out:-<nothing>})"

# --- [requires] install_script replaces the AUR path ---------------------

dir="$(new_plugin with-script hooks/deps.sh)"
cat > "$dir/hooks/deps.sh" <<'EOF'
#!/bin/sh
echo "install-script-ran"
EOF
chmod +x "$dir/hooks/deps.sh"

out="$(_aphotic_plugin_install_deps "$dir" 2>&1)"
[[ "$out" == *"install-script-ran"* ]] || fail "install_script was not executed"
[[ "$out" != *"yay-called"* ]] || fail "install_script did not replace the AUR path"

# --- a declared-but-unusable install_script warns, never silently yays ---

chmod -x "$dir/hooks/deps.sh"
out="$(_aphotic_plugin_install_deps "$dir" 2>&1)"
[[ "$out" == *"not executable"* ]] || fail "non-executable install_script did not warn"
[[ "$out" != *"yay-called"* ]] || fail "non-executable install_script fell through to the AUR"

# --- nothing missing means nothing runs ----------------------------------

dir="$(new_plugin satisfied)"
{
    echo '[plugin]'
    echo 'name = "satisfied"'
    echo '[requires]'
    echo 'binaries = ["sh"]'
} > "$dir/plugin.toml"
out="$(_aphotic_plugin_install_deps "$dir" 2>&1)"
[[ -z "$out" ]] || fail "ran something for an already-satisfied dependency: $out"

echo "PASS: plugin install deps"
