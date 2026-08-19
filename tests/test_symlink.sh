#!/usr/bin/env bash
# tests/test_symlink.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/install/symlink.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/src-config"
echo "content" > "$WORKDIR/src-config/file.txt"

DRY_RUN=1 install_config_dir "$WORKDIR/src-config" "$WORKDIR/dest-dry/config"
[[ ! -e "$WORKDIR/dest-dry/config" ]] || fail "dry-run should not have created files"

DRY_RUN=0 install_config_dir "$WORKDIR/src-config" "$WORKDIR/dest-real/config"
[[ -f "$WORKDIR/dest-real/config/file.txt" ]] || fail "real run did not copy config"

mkdir -p "$WORKDIR/variant-top"
DRY_RUN=0 link_active_variant "$WORKDIR/variant-top" "$WORKDIR/active-link"
[[ -L "$WORKDIR/active-link" ]] || fail "expected symlink to be created"

echo "PASS: symlink helpers"
