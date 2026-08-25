#!/usr/bin/env bash
# tests/test_agent_hook.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export APHOTIC_STATE_HOME="$WORKDIR/state"

# Create a temporary hook script that uses 'python' instead of 'python3'
# (Windows Git Bash compatibility for testing; actual hook uses python3 for Linux)
HOOK_SCRIPT="$WORKDIR/agent_hook_test.sh"
sed 's/python3/python/g' "$ROOT/Configs/.local/lib/aphotic/agent_hook.sh" > "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"

echo '{"session_id":"abc123","hook_event_name":"PostToolUse","tool_name":"Bash"}' | bash "$HOOK_SCRIPT"
session_file="$APHOTIC_STATE_HOME/agent-sessions/abc123.json"
[[ -f "$session_file" ]] || fail "PostToolUse did not create session file"
grep -q '"tool":"Bash"' "$session_file" || fail "session file missing tool name"

echo '{"session_id":"abc123","hook_event_name":"Stop"}' | bash "$HOOK_SCRIPT"
[[ ! -f "$session_file" ]] || fail "Stop did not delete session file"

echo '{"hook_event_name":"PostToolUse"}' | bash "$HOOK_SCRIPT"
# No session_id -- must exit 0 without creating anything under agent-sessions/.
[[ ! -d "$APHOTIC_STATE_HOME/agent-sessions" ]] || [[ -z "$(ls -A "$APHOTIC_STATE_HOME/agent-sessions" 2>/dev/null)" ]] || fail "missing session_id should not create a file"

echo "PASS: agent_hook writes on tool events, deletes on Stop, no-ops without session_id"
