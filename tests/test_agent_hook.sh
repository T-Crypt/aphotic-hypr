#!/usr/bin/env bash
# tests/test_agent_hook.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export APHOTIC_STATE_HOME="$WORKDIR/state"

# Create a python3 shim for Windows Git Bash (where python3 is disabled by App Execution Alias).
# On Linux or any system with real python3, this shim is harmless (real python3 on PATH takes precedence,
# or if this shim is found, it correctly delegates to python/python3). This allows the test to run
# Configs/.local/lib/aphotic/agent_hook.sh completely unmodified.
mkdir -p "$WORKDIR/bin"
cat > "$WORKDIR/bin/python3" << 'SHIM'
#!/usr/bin/env bash
# Shim to handle Windows Git Bash where python3 is disabled.
# Delegate to python if available, otherwise try python3 in case we're on a real Linux/Unix system.
if command -v python &>/dev/null; then
  exec python "$@"
elif command -v python3 &>/dev/null; then
  exec python3 "$@"
else
  echo "python or python3 not found" >&2
  exit 1
fi
SHIM
chmod +x "$WORKDIR/bin/python3"

# Prepend the shim directory to PATH so agent_hook.sh finds our python3 shim.
export PATH="$WORKDIR/bin:$PATH"

echo '{"session_id":"abc123","hook_event_name":"PostToolUse","tool_name":"Bash"}' | bash "$ROOT/Configs/.local/lib/aphotic/agent_hook.sh"
session_file="$APHOTIC_STATE_HOME/agent-sessions/abc123.json"
[[ -f "$session_file" ]] || fail "PostToolUse did not create session file"
grep -q '"tool":"Bash"' "$session_file" || fail "session file missing tool name"

echo '{"session_id":"abc123","hook_event_name":"Stop"}' | bash "$ROOT/Configs/.local/lib/aphotic/agent_hook.sh"
[[ ! -f "$session_file" ]] || fail "Stop did not delete session file"

echo '{"hook_event_name":"PostToolUse"}' | bash "$ROOT/Configs/.local/lib/aphotic/agent_hook.sh"
# No session_id -- must exit 0 without creating anything under agent-sessions/.
[[ ! -d "$APHOTIC_STATE_HOME/agent-sessions" ]] || [[ -z "$(ls -A "$APHOTIC_STATE_HOME/agent-sessions" 2>/dev/null)" ]] || fail "missing session_id should not create a file"

echo "PASS: agent_hook writes on tool events, deletes on Stop, no-ops without session_id"
