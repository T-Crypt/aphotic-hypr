#!/usr/bin/env bash
# tests/test_install_dry_run.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
rm -f aphotic.toml

# Under set -e a failing command substitution ended the test before any
# message, so an intermittent failure left nothing to diagnose.
status=0
output=$(bash install.sh --dry-run --profile full --with gaming,dev,ai --theme default </dev/null 2>&1) || status=$?
if [[ "$status" -ne 0 ]]; then
  echo "$output" | tail -n 25
  fail "install.sh --dry-run exited $status"
fi

for pkg in quickshell gamemode mangohud neovim ollama llmfit spotify; do
  echo "$output" | grep -q -- "$pkg" || fail "expected '$pkg' in dry-run plan"
done

[[ ! -f aphotic.toml ]] || fail "dry-run should not have written aphotic.toml"

echo "PASS: install.sh --dry-run"
