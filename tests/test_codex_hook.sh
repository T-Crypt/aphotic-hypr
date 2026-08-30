#!/usr/bin/env bash
# tests/test_codex_hook.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export APHOTIC_STATE_HOME="$WORKDIR/state"

# Create a python3 shim for Windows Git Bash (where python3 is disabled by App Execution Alias).
# On Linux or any system with real python3, this shim is harmless (real python3 on PATH takes precedence,
# or if this shim is found, it correctly delegates to python/python3). This allows the test to run
# Configs/.local/lib/aphotic/codex_hook.sh completely unmodified. See test_agent_hook.sh.
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

# Prepend the shim directory to PATH so codex_hook.sh finds our python3 shim.
export PATH="$WORKDIR/bin:$PATH"

# Codex already sends the same field names agent_hook.py reads from Claude
# Code; the adapter tags the record harness=codex and forwards it. These
# payloads are shaped from Codex's published hook schemas (session-start /
# pre-tool-use / stop / session-end / subagent-stop .command.input.json).
echo '{"session_id":"codex-1","hook_event_name":"SessionStart","cwd":"/tmp","model":"gpt-5","permission_mode":"default","source":"startup","transcript_path":null}' | bash "$ROOT/Configs/.local/lib/aphotic/codex_hook.sh"
session_file="$APHOTIC_STATE_HOME/agent-sessions/codex-1.json"
[[ -f "$session_file" ]] || fail "SessionStart did not create session file"
grep -q '"harness":"codex"' "$session_file" || fail "session file missing harness=codex"

# PreToolUse with Codex's tool alias `shell` normalizes to Claude's Bash.
echo '{"session_id":"codex-1","hook_event_name":"PreToolUse","tool_name":"shell","tool_use_id":"call_1","model":"gpt-5","permission_mode":"default","cwd":"/tmp","turn_id":"turn-1","transcript_path":null}' | bash "$ROOT/Configs/.local/lib/aphotic/codex_hook.sh"
grep -q '"tool":"Bash"' "$session_file" || fail "alias shell was not normalized to Bash"
grep -q '"tool":"Bash".*"harness":"codex"' "$APHOTIC_STATE_HOME/agent-events.jsonl" || fail "PreToolUse not in the live event stream with harness=codex"

# Stop marks the session idle, it does not retire it -- SessionEnd does
# that. See docs/AGENT_TRACKING.md's "Session retirement changed" note.
echo '{"session_id":"codex-1","hook_event_name":"Stop","model":"gpt-5","permission_mode":"default","cwd":"/tmp","stop_hook_active":false,"last_assistant_message":null,"transcript_path":null}' | bash "$ROOT/Configs/.local/lib/aphotic/codex_hook.sh"
[[ -f "$session_file" ]] || fail "Stop deleted the session file; it should only mark it idle"
grep -q '"event":"Stop"' "$session_file" || fail "session file not updated with Stop event"

# SessionEnd -- Codex calls the reason field "reason", agent_hook.py reads
# "end_reason"; the adapter maps it, then retires the session.
echo '{"session_id":"codex-1","hook_event_name":"SessionEnd","reason":"other","cwd":"/tmp","transcript_path":null}' | bash "$ROOT/Configs/.local/lib/aphotic/codex_hook.sh"
[[ ! -f "$session_file" ]] || fail "SessionEnd did not delete the session file"

# No session_id -- must exit 0 without creating anything under agent-sessions/.
echo '{"hook_event_name":"Stop"}' | bash "$ROOT/Configs/.local/lib/aphotic/codex_hook.sh"
[[ ! -d "$APHOTIC_STATE_HOME/agent-sessions" ]] || [[ -z "$(ls -A "$APHOTIC_STATE_HOME/agent-sessions" 2>/dev/null)" ]] || fail "missing session_id should not create a file"

# SubagentStop carries the parent session_id plus agent_id/agent_type and
# lands as a subagent_stop event (agent_hook.py's own event name).
echo '{"session_id":"codex-1","hook_event_name":"SubagentStop","agent_id":"ag-4","agent_type":"triage","model":"gpt-5","permission_mode":"default","cwd":"/tmp","stop_hook_active":false,"last_assistant_message":null,"agent_transcript_path":null,"transcript_path":null}' | bash "$ROOT/Configs/.local/lib/aphotic/codex_hook.sh"
grep -q '"event":"subagent_stop"' "$APHOTIC_STATE_HOME/agent-events.jsonl" || fail "SubagentStop not in the live event stream"
grep -q '"agentId":"ag-4"' "$APHOTIC_STATE_HOME/agent-events.jsonl" || fail "SubagentStop agentId not forwarded"

echo "PASS: codex_hook translates the Codex wire payload into the agent_hook contract (harness=codex, shell->Bash, reason->end_reason, subagent events, SessionEnd retirement)"