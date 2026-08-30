#!/usr/bin/env bash
# aphotic codex_hook -- Codex's side of the single event pipeline behind
# both the bar's agent popout and the agent graph surface (see
# docs/AGENT_TRACKING.md). Invoked by Codex on SessionStart/PreToolUse/
# PostToolUse/SubagentStop/Stop/SessionEnd with the event JSON piped to
# stdin. Codex's wire payload already uses the same field names
# agent_hook.py reads from Claude Code (session_id, hook_event_name,
# tool_name, tool_use_id, agent_id, agent_type, model, cwd); the two
# things it lacks -- a harness field, and the SessionEnd reason under
# agent_hook.py's name -- are added by codex_hook.py, which then spawns
# agent_hook.py with the translated JSON. Must be fast and must never fail
# the hook since a slow or failing hook blocks the calling session's own
# tool execution -- hence exec (no extra process) into one python3 worker
# and the unconditional exit 0 on the fallback path, exactly like
# agent_hook.sh.
set -u

hook_dir="${BASH_SOURCE[0]%/*}"
[[ "$hook_dir" == "${BASH_SOURCE[0]}" ]] && hook_dir="."

exec python3 "$hook_dir/codex_hook.py" || exit 0
