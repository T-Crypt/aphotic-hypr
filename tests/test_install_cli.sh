#!/usr/bin/env bash
# tests/test_install_cli.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

output=$(bash install.sh --help)
echo "$output" | grep -q -- "--profile" || fail "--help did not list --profile"

set +e
bash install.sh --bogus-flag >/dev/null 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "unknown flag should exit non-zero"

echo "PASS: install.sh CLI parsing"
