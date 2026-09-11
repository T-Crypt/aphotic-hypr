#!/usr/bin/env bash
# tests/test_flow_js.sh
#
# Runs the Flow model and contract assertions under node. Those files are
# plain .js that QML loads at runtime, so they can be tested outside a
# compositor -- but CI only collects tests/test_*.sh and pytest, so without
# this wrapper they never run there.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: node not installed"
    exit 0
fi

for f in tests/*.cjs; do
    [[ -e "$f" ]] || continue
    node "$f" || { echo "FAIL: $f"; exit 1; }
done

echo "PASS: flow javascript assertions"
