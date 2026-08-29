#!/usr/bin/env bash
# aphotic agent_hook -- the single event pipeline behind both the bar's
# agent popout (per-session status) and the agent graph surface. Invoked
# by Claude Code on SessionStart/PreToolUse/PostToolUse/
# PostToolUseFailure/Notification/Stop/SubagentStop/SessionEnd with the
# event JSON piped to stdin. Must be fast and must never fail the hook
# since a slow or failing hook blocks the calling session's own tool
# execution -- hence exec (no extra process) into one python3 worker that
# handles the whole payload, rather than the spawn-per-field this used to
# do, and hence the unconditional exit 0 on the fallback path.
set -u

hook_dir="${BASH_SOURCE[0]%/*}"
[[ "$hook_dir" == "${BASH_SOURCE[0]}" ]] && hook_dir="."

exec python3 "$hook_dir/agent_hook.py" || exit 0
