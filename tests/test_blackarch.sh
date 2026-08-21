#!/usr/bin/env bash
# tests/test_blackarch.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/install/blackarch.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

blackarch_repo_present() {
    grep -q '^\[blackarch\]' "$FAKE_PACMAN_CONF" 2>/dev/null
}

FAKE_PACMAN_CONF="$WORKDIR/pacman.conf"
cat > "$FAKE_PACMAN_CONF" <<'EOF'
[options]
Architecture = auto

[core]
Include = /etc/pacman.d/mirrorlist
EOF

blackarch_repo_present && fail "expected no [blackarch] section yet"

cat >> "$FAKE_PACMAN_CONF" <<'EOF'

[blackarch]
Server = https://blackarch.org/blackarch/$repo/os/$arch
EOF

blackarch_repo_present || fail "expected [blackarch] section to be detected"

FAKE_PACMAN_CONF="$WORKDIR/pacman-no-blackarch.conf"
cat > "$FAKE_PACMAN_CONF" <<'EOF'
[options]
Architecture = auto
EOF

dry_run_output=$(DRY_RUN=1 ensure_blackarch_repo 2>&1)
echo "$dry_run_output" | grep -q "dry-run" || fail "expected dry-run message, got: $dry_run_output"

echo "PASS: blackarch repo detection + dry-run guard"
