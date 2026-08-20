#!/usr/bin/env bash
# tests/test_install_dry_run.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
rm -f noctis.toml

output=$(bash install.sh --dry-run --profile full --with gaming,dev,ai --theme default 2>&1)
status=$?
[[ "$status" -eq 0 ]] || fail "install.sh --dry-run exited $status"

for pkg in quickshell gamemode mangohud neovim ollama spotify; do
  echo "$output" | grep -q -- "$pkg" || fail "expected '$pkg' in dry-run plan"
done

[[ ! -f noctis.toml ]] || fail "dry-run should not have written noctis.toml"

echo "PASS: install.sh --dry-run"
