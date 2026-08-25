#!/usr/bin/env bash
# tests/test_agent_usage_cmd.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export HOME="$WORKDIR/home"
export APHOTIC_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME" "$APHOTIC_STATE_HOME"

aphotic_require() { command -v "$1" >/dev/null 2>&1; }
aphotic_log() { :; }
export -f aphotic_require aphotic_log

source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_agent.sh"

aphotic_cmd_agent usage-update
[[ -f "$APHOTIC_STATE_HOME/agent-usage.json" ]] || fail "usage-update did not write agent-usage.json"
grep -q '"schemaVersion": 1' "$APHOTIC_STATE_HOME/agent-usage.json" || fail "record missing schemaVersion"

if aphotic_cmd_agent bogus-verb 2>/dev/null; then
  fail "expected nonzero exit for unknown subcommand"
fi

echo "PASS: agent usage-update writes a valid record, rejects unknown subcommands"
