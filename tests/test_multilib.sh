#!/usr/bin/env bash
# tests/test_multilib.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$ROOT"
PYTHON_BIN="python3"
source "$ROOT/lib/install/multilib.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

FAKE_PACMAN_CONF="$WORKDIR/pacman.conf"

multilib_repo_present() {
    grep -q '^\[multilib\]' "$FAKE_PACMAN_CONF" 2>/dev/null
}

cat > "$FAKE_PACMAN_CONF" <<'EOF'
[options]
Architecture = auto

[core]
Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
EOF

multilib_repo_present && fail "expected no [multilib] section yet"

cat >> "$FAKE_PACMAN_CONF" <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

multilib_repo_present || fail "expected [multilib] section to be detected"

FAKE_PACMAN_CONF="$WORKDIR/pacman-no-multilib.conf"
cat > "$FAKE_PACMAN_CONF" <<'EOF'
[options]
Architecture = auto
EOF

dry_run_output=$(DRY_RUN=1 ensure_multilib_repo 2>&1)
echo "$dry_run_output" | grep -q "dry-run" || fail "expected dry-run message, got: $dry_run_output"

[[ "$(layer_requires_multilib "gaming")" == "true" ]] || fail "expected gaming layer to require multilib"
[[ "$(layer_requires_multilib "dev")" == "false" ]] || fail "expected dev layer to not require multilib"
[[ "$(any_layer_requires_multilib "dev,gaming")" == "true" ]] || fail "expected any_layer_requires_multilib to catch gaming in a csv list"
[[ "$(any_layer_requires_multilib "dev")" == "false" ]] || fail "expected any_layer_requires_multilib to be false without gaming"

echo "PASS: multilib repo detection + dry-run guard + layer requirement lookup"
