#!/usr/bin/env bash
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

source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"
source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_plugin.sh"

WORK="$TESTHOME/work"
mkdir -p "$WORK"

# --- A valid plugin passes clean --------------------------------------

VALID="$WORK/scratch-valid"
mkdir -p "$VALID/qml"
cat > "$VALID/plugin.toml" <<'TOML'
[plugin]
name = "scratch-valid"
display_name = "Scratch Valid"
description = "A minimal plugin used only by this test."
version = "1.0.0"
category = "productivity"
capabilities = ["ui-surface"]

[ui.dashboard_tab]
id = "scratchValid"
label = "Scratch Valid"
icon = "check"
component = "qml/Tab.qml"
TOML
echo "// test fixture" > "$VALID/qml/Tab.qml"

_aphotic_plugin_validate "$VALID" || fail "a well-formed plugin should validate clean"

# --- Missing required fields --------------------------------------------

MISSING_FIELDS="$WORK/scratch-missing-fields"
mkdir -p "$MISSING_FIELDS"
cat > "$MISSING_FIELDS/plugin.toml" <<'TOML'
[plugin]
capabilities = []
TOML
out="$(_aphotic_plugin_validate "$MISSING_FIELDS" 2>&1 >/dev/null || true)"
[[ "$out" == *"display_name missing"* ]] || fail "did not flag missing display_name: $out"
[[ "$out" == *"description missing"* ]] || fail "did not flag missing description: $out"
[[ "$out" == *"version missing"* ]] || fail "did not flag missing version: $out"
_aphotic_plugin_validate "$MISSING_FIELDS" >/dev/null 2>&1 && fail "missing required fields should fail validation"

# --- Entry point file does not exist ------------------------------------

MISSING_FILE="$WORK/scratch-missing-file"
mkdir -p "$MISSING_FILE/qml"
cat > "$MISSING_FILE/plugin.toml" <<'TOML'
[plugin]
display_name = "Scratch Missing File"
description = "Declares a component that is never shipped."
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.dashboard_tab]
component = "qml/Nope.qml"
TOML
out="$(_aphotic_plugin_validate "$MISSING_FILE" 2>&1 >/dev/null || true)"
[[ "$out" == *"points at 'qml/Nope.qml', which doesn't exist"* ]] || fail "did not flag missing entry-point file: $out"
_aphotic_plugin_validate "$MISSING_FILE" >/dev/null 2>&1 && fail "a missing entry-point file should fail validation"

# --- Path traversal in a component path ---------------------------------

TRAVERSAL="$WORK/scratch-traversal"
mkdir -p "$TRAVERSAL/qml"
cat > "$TRAVERSAL/plugin.toml" <<'TOML'
[plugin]
display_name = "Scratch Traversal"
description = "Points its component outside its own directory."
version = "1.0.0"
capabilities = ["ui-surface"]

[ui.dashboard_tab]
component = "../../etc/passwd"
TOML
out="$(_aphotic_plugin_validate "$TRAVERSAL" 2>&1 >/dev/null || true)"
[[ "$out" == *"is not a safe relative path"* ]] || fail "did not flag path traversal: $out"
_aphotic_plugin_validate "$TRAVERSAL" >/dev/null 2>&1 && fail "a path-traversal component should fail validation"

# --- Capability/surface mismatch, both directions -----------------------

NO_CAP="$WORK/scratch-no-cap"
mkdir -p "$NO_CAP/qml"
cat > "$NO_CAP/plugin.toml" <<'TOML'
[plugin]
display_name = "Scratch No Cap"
description = "Ships a ui section without declaring ui-surface."
version = "1.0.0"
capabilities = []

[ui.dashboard_tab]
component = "qml/Tab.qml"
TOML
echo "// test fixture" > "$NO_CAP/qml/Tab.qml"
out="$(_aphotic_plugin_validate "$NO_CAP" 2>&1 >/dev/null || true)"
[[ "$out" == *"doesn't include 'ui-surface'"* ]] || fail "did not flag ui section without ui-surface capability: $out"

NO_SURFACE="$WORK/scratch-no-surface"
mkdir -p "$NO_SURFACE"
cat > "$NO_SURFACE/plugin.toml" <<'TOML'
[plugin]
display_name = "Scratch No Surface"
description = "Declares ui-surface without shipping any [ui.*] section."
version = "1.0.0"
capabilities = ["ui-surface"]
TOML
out="$(_aphotic_plugin_validate "$NO_SURFACE" 2>&1 >/dev/null || true)"
[[ "$out" == *"no [ui.*] section declares one"* ]] || fail "did not flag ui-surface capability with no section: $out"

# --- Bad directory name --------------------------------------------------

BAD_NAME="$WORK/Scratch_Bad_Name"
mkdir -p "$BAD_NAME"
cat > "$BAD_NAME/plugin.toml" <<'TOML'
[plugin]
display_name = "Scratch Bad Name"
description = "Directory name is not install-safe."
version = "1.0.0"
capabilities = []
TOML
out="$(_aphotic_plugin_validate "$BAD_NAME" 2>&1 >/dev/null || true)"
[[ "$out" == *"must be lowercase"* ]] || fail "did not flag an unsafe directory name: $out"

# --- Symlink inside the plugin tree --------------------------------------

SYMLINKED="$WORK/scratch-symlink"
mkdir -p "$SYMLINKED"
cat > "$SYMLINKED/plugin.toml" <<'TOML'
[plugin]
display_name = "Scratch Symlink"
description = "Ships a symlink inside its own tree."
version = "1.0.0"
capabilities = []
TOML
ln -s /etc/hostname "$SYMLINKED/sneaky"
out="$(_aphotic_plugin_validate "$SYMLINKED" 2>&1 >/dev/null || true)"
[[ "$out" == *"symlink in plugin tree"* ]] || fail "did not flag a symlink in the plugin tree: $out"
_aphotic_plugin_validate "$SYMLINKED" >/dev/null 2>&1 && fail "a symlinked plugin tree should fail validation"

echo "PASS: tests/test_plugin_validate.sh"
