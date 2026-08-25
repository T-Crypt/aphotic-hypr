#!/usr/bin/env bash
# aphotic agent_hook — writes live per-session state for the bar's agent
# popout. Invoked by Claude Code on PreToolUse/PostToolUse/Notification/
# Stop. Must be fast and must never fail the hook (all steps are
# best-effort) since a slow/failing hook blocks the calling session's own
# tool execution.
set -u

APHOTIC_STATE_HOME="${APHOTIC_STATE_HOME:-$HOME/.local/state/aphotic}"
SESSIONS_DIR="$APHOTIC_STATE_HOME/agent-sessions"

payload="$(cat)"

session_id="$(printf '%s' "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("session_id",""))' 2>/dev/null)"
event="$(printf '%s' "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("hook_event_name",""))' 2>/dev/null)"
tool="$(printf '%s' "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null)"

[[ -n "$session_id" ]] || exit 0

mkdir -p "$SESSIONS_DIR" 2>/dev/null || exit 0
session_file="$SESSIONS_DIR/$session_id.json"

if [[ "$event" == "Stop" ]]; then
    rm -f "$session_file" 2>/dev/null
    exit 0
fi

updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp_file="$session_file.tmp.$$"
printf '{"event":"%s","tool":"%s","updatedAt":"%s"}\n' "$event" "$tool" "$updated_at" > "$tmp_file" 2>/dev/null && mv -f "$tmp_file" "$session_file" 2>/dev/null

exit 0
